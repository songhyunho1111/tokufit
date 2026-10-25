import type { FastifyInstance } from "fastify";
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox";
import { ReportErrorSchema } from "../reports/contracts.js";
import type { HealthReportService } from "../reports/service.js";
import {
  FoodPhotoAnalysisRequestSchema,
  FoodPhotoAnalysisResponseSchema,
} from "./contracts.js";
import { FoodServiceError } from "./errors.js";
import type { FoodPhotoAnalysisService } from "./service.js";

export async function registerFoodRoutes(
  instance: FastifyInstance,
  reports: HealthReportService | undefined,
  service: FoodPhotoAnalysisService | undefined,
) {
  const app = instance.withTypeProvider<TypeBoxTypeProvider>();
  app.addHook("preClose", async () => {
    service?.close();
  });
  app.post(
    "/api/v1/food-analyses",
    {
      bodyLimit: 2_900_000,
      schema: {
        body: FoodPhotoAnalysisRequestSchema,
        response: {
          201: FoodPhotoAnalysisResponseSchema,
          400: ReportErrorSchema,
          401: ReportErrorSchema,
          413: ReportErrorSchema,
          415: ReportErrorSchema,
          422: ReportErrorSchema,
          429: ReportErrorSchema,
          500: ReportErrorSchema,
          502: ReportErrorSchema,
          503: ReportErrorSchema,
          504: ReportErrorSchema,
        },
        tags: ["Food"],
        security: [{ reportBearer: [] }],
        description:
          "Analyzes one food photo for user review. The image and result are not retained. Each explicit request consumes quota; do not automatically retry.",
      },
    },
    async (request, reply) => {
      reply.header("Cache-Control", "no-store");
      if (!reports || !service)
        throw new FoodServiceError(
          503,
          "FOOD_SERVICE_UNAVAILABLE",
          "Food analysis is unavailable.",
          60,
        );
      const owner = await reports.authenticate(request.headers.authorization);
      const controller = new AbortController();
      if (request.raw.aborted || reply.raw.destroyed) controller.abort();
      const closed = () => {
        if (!reply.raw.writableEnded) controller.abort();
      };
      reply.raw.once("close", closed);
      try {
        const data = await service.create(
          owner,
          request.body.image,
          request.ip,
          controller.signal,
        );
        return reply.code(201).send({ data });
      } finally {
        reply.raw.removeListener("close", closed);
      }
    },
  );
}
