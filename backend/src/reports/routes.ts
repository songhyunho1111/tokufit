import { Type } from "@sinclair/typebox";
import type { FastifyInstance } from "fastify";
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import {
  InstallationResponseSchema,
  ReportErrorSchema,
  ReportListSchema,
  ReportPeriodSchema,
  ReportRequestSchema,
  ReportResponseSchema,
} from "./contracts.js";
import type { HealthReportService } from "./service.js";
import { ReportServiceError } from "./errors.js";

const empty = Type.Object({}, { additionalProperties: false });
const errors = {
  400: ReportErrorSchema,
  401: ReportErrorSchema,
  404: ReportErrorSchema,
  409: ReportErrorSchema,
  413: ReportErrorSchema,
  415: ReportErrorSchema,
  422: ReportErrorSchema,
  429: ReportErrorSchema,
  500: ReportErrorSchema,
  502: ReportErrorSchema,
  503: ReportErrorSchema,
  504: ReportErrorSchema,
};
const security = [{ reportBearer: [] }];

export async function registerReportRoutes(
  instance: FastifyInstance,
  service: HealthReportService | undefined,
) {
  const app = instance.withTypeProvider<TypeBoxTypeProvider>();
  const available = () => {
    if (!service)
      throw new ReportServiceError(
        503,
        "REPORT_SERVICE_UNAVAILABLE",
        "The report service is unavailable.",
        60,
      );
    return service;
  };
  app.post(
    "/api/v1/report-installations",
    {
      schema: {
        body: empty,
        response: { 201: InstallationResponseSchema, ...errors },
        tags: ["Reports"],
        description:
          "Creates an anonymous installation and returns its bearer token once. Store it securely.",
      },
      bodyLimit: 1_024,
    },
    async (request, reply) => {
      const installation = await available().createInstallation(request.ip);
      reply.header("Cache-Control", "no-store");
      reply.header(
        "Location",
        `/api/v1/report-installations/${installation.id}`,
      );
      return reply.code(201).send({ data: installation });
    },
  );

  app.post(
    "/api/v1/health-reports",
    {
      schema: {
        headers: Type.Object({
          "idempotency-key": Type.String({ format: "uuid" }),
        }),
        body: ReportRequestSchema,
        response: {
          200: ReportResponseSchema,
          201: ReportResponseSchema,
          202: ReportResponseSchema,
          ...errors,
        },
        tags: ["Reports"],
        security,
        description:
          "Aggregates the supplied period records and creates a grounded AI narrative. No raw record text is sent to the model.",
      },
      bodyLimit: 262_144,
    },
    async (request, reply) => {
      const reports = available();
      const owner = await reports.authenticate(request.headers.authorization);
      const controller = new AbortController();
      const closed = () => {
        if (!reply.raw.writableEnded) controller.abort();
      };
      reply.raw.once("close", closed);
      try {
        const result = await reports.create(
          owner,
          request.headers["idempotency-key"],
          request.body,
          request.ip,
          controller.signal,
        );
        reply.header("Location", `/api/v1/health-reports/${result.report.id}`);
        reply.header("Cache-Control", "no-store");
        if (result.status === 202) reply.header("Retry-After", "2");
        return reply.code(result.status).send({ data: result.report });
      } finally {
        reply.raw.removeListener("close", closed);
      }
    },
  );

  app.get(
    "/api/v1/health-reports/:id",
    {
      schema: {
        params: Type.Object(
          { id: Type.String({ format: "uuid" }) },
          { additionalProperties: false },
        ),
        querystring: empty,
        response: { 200: ReportResponseSchema, ...errors },
        tags: ["Reports"],
        security,
      },
    },
    async (request, reply) => {
      const reports = available();
      const owner = await reports.authenticate(request.headers.authorization);
      reply.header("Cache-Control", "no-store");
      return reply
        .code(200)
        .send({ data: await reports.get(owner, request.params.id) });
    },
  );

  app.get(
    "/api/v1/health-reports",
    {
      schema: {
        querystring: Type.Object(
          {
            period: Type.Optional(ReportPeriodSchema),
            limit: Type.Optional(
              Type.String({
                pattern: "^(?:[1-9]|[1-4][0-9]|50)$",
                default: "20",
              }),
            ),
            cursor: Type.Optional(
              Type.String({
                minLength: 1,
                maxLength: 512,
                pattern: "^[A-Za-z0-9_-]+$",
              }),
            ),
          },
          { additionalProperties: false },
        ),
        response: { 200: ReportListSchema, ...errors },
        tags: ["Reports"],
        security,
      },
    },
    async (request, reply) => {
      const reports = available();
      const owner = await reports.authenticate(request.headers.authorization);
      reply.header("Cache-Control", "no-store");
      return reply
        .code(200)
        .send(
          await reports.list(
            owner,
            request.query.period,
            Number(request.query.limit ?? "20"),
            request.query.cursor,
          ),
        );
    },
  );
}
