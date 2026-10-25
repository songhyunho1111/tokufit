import { createHash } from "node:crypto";
import { Value } from "@sinclair/typebox/value";
import { aggregateReport } from "./aggregate.js";
import { ReportNarrativeSchema } from "./contracts.js";
import type {
  ReportNarrator,
  ReportPeriod,
  ReportRequest,
} from "./contracts.js";
import { ReportServiceError } from "./errors.js";
import type { ReportRepository } from "./repository.js";

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, child]) => [key, canonical(child)]),
    );
  }
  return value;
}

export function reportFingerprint(request: ReportRequest) {
  const sorted = {
    ...request,
    data: {
      meals: [...request.data.meals].sort((a, b) => a.id.localeCompare(b.id)),
      workouts: [...request.data.workouts].sort((a, b) =>
        a.id.localeCompare(b.id),
      ),
      wellness: [...request.data.wellness].sort((a, b) =>
        a.day.localeCompare(b.day),
      ),
    },
  };
  return createHash("sha256")
    .update(JSON.stringify(canonical(sorted)))
    .digest("hex");
}

const upstreamCodes = new Set([
  "LLM_TIMEOUT",
  "LLM_UPSTREAM_ERROR",
  "LLM_INVALID_RESPONSE",
  "LLM_UNAVAILABLE",
  "LLM_CANCELLED",
]);

export class HealthReportService {
  constructor(
    private readonly repository: ReportRepository,
    private readonly narrator: ReportNarrator | undefined,
    private readonly now: () => Date = () => new Date(),
  ) {}

  createInstallation(ip: string) {
    return this.repository.createInstallation(ip);
  }

  async authenticate(authorization: string | undefined) {
    const token = authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
    const owner = token ? await this.repository.authenticate(token) : null;
    if (!owner)
      throw new ReportServiceError(
        401,
        "UNAUTHORIZED",
        "A valid report token is required.",
      );
    return owner;
  }

  async create(
    installationId: string,
    idempotencyKey: string,
    request: ReportRequest,
    ip: string,
    signal?: AbortSignal,
  ) {
    await this.repository.limitSubmission(installationId, ip);
    if (!this.narrator)
      throw new ReportServiceError(
        503,
        "REPORT_SERVICE_UNAVAILABLE",
        "Report generation is not configured.",
        60,
      );
    const metrics = aggregateReport(request, this.now());
    const claim = await this.repository.claim({
      installationId,
      idempotencyKey,
      payloadHash: reportFingerprint(request),
      period: request.period,
      anchorDate: request.anchorDate,
      timeZone: request.timeZone,
      metrics,
      ip,
    });
    if (claim.attempt === null)
      return {
        report: claim.report,
        status: claim.report.status === "processing" ? 202 : 200,
      };
    try {
      const narrative = await this.narrator(
        { period: request.period, metrics, goals: request.goals },
        signal,
      );
      if (
        !Value.Check(ReportNarrativeSchema, narrative) ||
        !narrative.evaluation.trim() ||
        narrative.recommendations.some(
          (item) => !item.title.trim() || !item.detail.trim(),
        ) ||
        new Set(
          narrative.recommendations.map((item) =>
            item.title.normalize("NFKC").trim().toLowerCase(),
          ),
        ).size !== 3
      ) {
        throw new ReportServiceError(
          502,
          "LLM_INVALID_RESPONSE",
          "The report response was incomplete.",
        );
      }
      const report = await this.repository.complete(
        installationId,
        claim.report.id,
        claim.attempt,
        narrative,
      );
      return {
        report,
        status:
          report.status === "processing" ? 202 : claim.created ? 201 : 200,
      };
    } catch (error) {
      const code =
        error instanceof Error &&
        "code" in error &&
        typeof error.code === "string" &&
        upstreamCodes.has(error.code)
          ? error.code
          : "REPORT_GENERATION_FAILED";
      await this.repository.fail(
        installationId,
        claim.report.id,
        claim.attempt,
        code,
      );
      throw new ReportServiceError(
        code === "LLM_TIMEOUT" ? 504 : 502,
        code,
        "The report could not be generated. Please retry.",
        undefined,
        claim.report.id,
      );
    }
  }

  async get(installationId: string, reportId: string) {
    await this.repository.limitRead(installationId);
    const report = await this.repository.get(installationId, reportId);
    if (!report)
      throw new ReportServiceError(
        404,
        "REPORT_NOT_FOUND",
        "The report does not exist.",
      );
    return report;
  }

  async list(
    installationId: string,
    period: ReportPeriod | undefined,
    limit: number,
    cursor: string | undefined,
  ) {
    await this.repository.limitRead(installationId);
    return this.repository.list(installationId, period, limit, cursor);
  }
}
