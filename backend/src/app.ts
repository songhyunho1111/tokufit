import Fastify from "fastify";
import swagger from "@fastify/swagger";
import { Type } from "@sinclair/typebox";
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import { registerReportRoutes } from "./reports/routes.js";
import type { HealthReportService } from "./reports/service.js";
import { ReportServiceError } from "./reports/errors.js";
import { ReportInputError } from "./reports/aggregate.js";
import { registerFoodRoutes } from "./foods/routes.js";
import type { FoodPhotoAnalysisService } from "./foods/service.js";
import { FoodServiceError } from "./foods/errors.js";

const OK = Type.Object(
  { status: Type.Literal("ok") },
  { additionalProperties: false },
);
const ErrorResponse = Type.Object(
  {
    code: Type.String(),
    message: Type.String(),
    requestId: Type.String(),
  },
  { additionalProperties: false },
);
const Status = Type.Object(
  {
    status: Type.Literal("ok"),
    service: Type.Literal("RE:PICK"),
    timestamp: Type.String({ format: "date-time" }),
  },
  { additionalProperties: false },
);

export async function buildApp(options: {
  checkDatabase: () => Promise<void>;
  logger?: boolean;
  reports?: HealthReportService;
  foods?: FoodPhotoAnalysisService;
}) {
  const app = Fastify({
    logger: options.logger
      ? {
          redact: [
            "req.headers.authorization",
            "req.headers.cookie",
            'res.headers["set-cookie"]',
          ],
        }
      : false,
    requestTimeout: 10000,
    connectionTimeout: 75000,
    bodyLimit: 16384,
    forceCloseConnections: "idle",
    ajv: { customOptions: { removeAdditional: false, coerceTypes: false } },
  }).withTypeProvider<TypeBoxTypeProvider>();

  await app.register(swagger, {
    openapi: {
      info: { title: "RE:PICK API", version: "0.1.0" },
      components: {
        securitySchemes: {
          reportBearer: {
            type: "http",
            scheme: "bearer",
            bearerFormat: "Opaque installation token",
          },
        },
      },
    },
  });
  app.setErrorHandler((error, request, reply) => {
    if (
      error instanceof ReportServiceError ||
      error instanceof FoodServiceError ||
      error instanceof ReportInputError
    ) {
      reply.header("Cache-Control", "no-store");
      if (
        error instanceof ReportServiceError ||
        error instanceof FoodServiceError
      ) {
        if (error.retryAfter !== undefined)
          reply.header("Retry-After", error.retryAfter);
        if (error instanceof ReportServiceError && error.reportId)
          reply.header("Location", `/api/v1/health-reports/${error.reportId}`);
      }
      request.log.warn({ code: error.code }, "API request failed");
      return void reply
        .code(error instanceof ReportInputError ? 422 : error.statusCode)
        .send({
          code: error.code,
          message: error.message,
          requestId: request.id,
        });
    }
    const validation = error instanceof Error && "validation" in error;
    const tooLarge =
      error instanceof Error &&
      "code" in error &&
      error.code === "FST_ERR_CTP_BODY_TOO_LARGE";
    const badRequest =
      error instanceof Error &&
      "statusCode" in error &&
      error.statusCode === 400;
    const unsupportedMedia =
      error instanceof Error &&
      "statusCode" in error &&
      error.statusCode === 415;
    const status =
      validation || badRequest
        ? 400
        : tooLarge
          ? 413
          : unsupportedMedia
            ? 415
            : 500;
    // Database/validation details can contain sensitive input; log only a classification.
    request.log.error(
      { code: validation ? "VALIDATION_ERROR" : "REQUEST_FAILED" },
      "Request failed",
    );
    void reply.code(status).send({
      code:
        status === 400
          ? "INVALID_REQUEST"
          : status === 413
            ? "PAYLOAD_TOO_LARGE"
            : status === 415
              ? "UNSUPPORTED_MEDIA_TYPE"
              : "INTERNAL_ERROR",
      message:
        status === 400
          ? "The request is invalid."
          : status === 413
            ? "The request is too large."
            : status === 415
              ? "The request content type is not supported."
              : "The request could not be completed.",
      requestId: request.id,
    });
  });
  app.setNotFoundHandler((request, reply) =>
    reply.code(404).send({
      code: "NOT_FOUND",
      message: "The requested endpoint does not exist.",
      requestId: request.id,
    }),
  );

  const checkReady = async () => {
    try {
      await options.checkDatabase();
      return true;
    } catch {
      return false;
    }
  };
  app.get("/health/live", { schema: { response: { 200: OK } } }, async () => ({
    status: "ok" as const,
  }));
  app.get(
    "/health/ready",
    { schema: { response: { 200: OK, 503: ErrorResponse } } },
    async (request, reply) => {
      if (!(await checkReady()))
        return reply.code(503).send({
          code: "DEPENDENCY_UNAVAILABLE",
          message: "Service is temporarily unavailable.",
          requestId: request.id,
        });
      return reply.code(200).send({ status: "ok" });
    },
  );
  app.get(
    "/api/v1/status",
    {
      schema: {
        querystring: Type.Object({}, { additionalProperties: false }),
        response: { 200: Status, 400: ErrorResponse, 503: ErrorResponse },
      },
    },
    async (request, reply) => {
      if (!(await checkReady()))
        return reply.code(503).send({
          code: "DEPENDENCY_UNAVAILABLE",
          message: "Service is temporarily unavailable.",
          requestId: request.id,
        });
      return reply.code(200).send({
        status: "ok",
        service: "RE:PICK",
        timestamp: new Date().toISOString(),
      });
    },
  );
  app.get("/api/v1/openapi.json", { schema: { hide: true } }, async () =>
    app.swagger(),
  );
  await registerReportRoutes(app, options.reports);
  await registerFoodRoutes(app, options.reports, options.foods);
  return app;
}
