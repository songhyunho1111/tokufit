import { createHash, randomBytes, randomUUID } from "node:crypto";
import { and, desc, eq, lt, or, sql } from "drizzle-orm";
import type { NodePgDatabase } from "drizzle-orm/node-postgres";
import * as schema from "../schema.js";
import type {
  ReportMetrics,
  ReportNarrative,
  ReportPeriod,
  ReportResource,
} from "./contracts.js";
import { ReportServiceError } from "./errors.js";

type Database = NodePgDatabase<typeof schema>;
type ReportRow = typeof schema.healthReports.$inferSelect;
type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];
export interface ReportLimits {
  registrationsPerHour: number;
  reportsPerInstallationDay: number;
  reportsPerIPDay: number;
  reportsPerDay: number;
}
export interface ReportClaim {
  report: ReportResource;
  attempt: number | null;
  created: boolean;
}
export interface ReportRepository {
  createInstallation(ip: string): Promise<{ id: string; token: string }>;
  authenticate(token: string): Promise<string | null>;
  limitRead(installationId: string): Promise<void>;
  limitSubmission(installationId: string, ip: string): Promise<void>;
  claim(input: {
    installationId: string;
    idempotencyKey: string;
    payloadHash: string;
    period: ReportPeriod;
    anchorDate: string;
    timeZone: string;
    metrics: ReportMetrics;
    ip: string;
  }): Promise<ReportClaim>;
  complete(
    installationId: string,
    reportId: string,
    attempt: number,
    narrative: ReportNarrative,
  ): Promise<ReportResource>;
  fail(
    installationId: string,
    reportId: string,
    attempt: number,
    code: string,
  ): Promise<void>;
  get(installationId: string, reportId: string): Promise<ReportResource | null>;
  list(
    installationId: string,
    period: ReportPeriod | undefined,
    limit: number,
    cursor: string | undefined,
  ): Promise<{ data: ReportResource[]; meta: { nextCursor: string | null } }>;
}

const hash = (value: string) =>
  createHash("sha256").update(value).digest("hex");
const leaseMilliseconds = 120_000;

function resource(row: ReportRow): ReportResource {
  return {
    id: row.id,
    period: row.period,
    anchorDate: row.anchorDate,
    timeZone: row.timeZone,
    status: row.status,
    createdAt: row.createdAt.toISOString(),
    model: row.model,
    metrics: row.metrics,
    evaluation: row.evaluation,
    reaction: row.reaction,
    recommendations: row.recommendations,
    failureCode: row.failureCode,
  };
}

export class PostgresReportRepository implements ReportRepository {
  constructor(
    private readonly database: Database,
    private readonly limits: ReportLimits,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private async consume(
    tx: Transaction,
    key: string,
    maximum: number,
    seconds: number,
  ) {
    const now = this.now();
    const start = new Date(
      Math.floor(now.getTime() / (seconds * 1_000)) * seconds * 1_000,
    );
    const expiry = new Date(start.getTime() + seconds * 1_000);
    const rows = await tx
      .insert(schema.reportRateLimits)
      .values({ key, windowStart: start, count: 1, expiresAt: expiry })
      .onConflictDoUpdate({
        target: [
          schema.reportRateLimits.key,
          schema.reportRateLimits.windowStart,
        ],
        set: { count: sql`${schema.reportRateLimits.count} + 1` },
        setWhere: lt(schema.reportRateLimits.count, maximum),
      })
      .returning({ count: schema.reportRateLimits.count });
    if (rows.length === 0)
      throw new ReportServiceError(
        429,
        "REPORT_RATE_LIMITED",
        "Please try again later.",
        Math.max(1, Math.ceil((expiry.getTime() - now.getTime()) / 1_000)),
      );
  }

  async createInstallation(ip: string) {
    const id = randomUUID();
    const token = randomBytes(32).toString("base64url");
    await this.database.transaction(async (tx) => {
      await tx
        .delete(schema.reportRateLimits)
        .where(lt(schema.reportRateLimits.expiresAt, this.now()));
      await this.consume(
        tx,
        `registration:ip:${hash(ip)}`,
        this.limits.registrationsPerHour,
        3_600,
      );
      await this.consume(tx, "registration:global", 1_000, 86_400);
      await tx
        .insert(schema.reportInstallations)
        .values({ id, tokenHash: hash(token), createdAt: this.now() });
    });
    return { id, token };
  }

  async authenticate(token: string) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
    const [row] = await this.database
      .select({ id: schema.reportInstallations.id })
      .from(schema.reportInstallations)
      .where(eq(schema.reportInstallations.tokenHash, hash(token)))
      .limit(1);
    return row?.id ?? null;
  }

  async limitRead(installationId: string) {
    await this.database.transaction(async (tx) => {
      await tx
        .delete(schema.reportRateLimits)
        .where(lt(schema.reportRateLimits.expiresAt, this.now()));
      await this.consume(tx, `read:${installationId}`, 60, 60);
    });
  }

  async limitSubmission(installationId: string, ip: string) {
    await this.database.transaction(async (tx) => {
      await tx
        .delete(schema.reportRateLimits)
        .where(lt(schema.reportRateLimits.expiresAt, this.now()));
      await this.consume(tx, "submission:global", 2_000, 86_400);
      await this.consume(tx, `submission:owner:${installationId}`, 60, 3_600);
      await this.consume(tx, `submission:ip:${hash(ip)}`, 120, 3_600);
    });
  }

  async claim(
    input: Parameters<ReportRepository["claim"]>[0],
  ): Promise<ReportClaim> {
    return this.database.transaction(async (tx) => {
      // Serialize claims for an owner, but release the lock before any network generation.
      await tx.execute(
        sql`select pg_advisory_xact_lock(hashtextextended(${input.installationId}, 0))`,
      );
      const [request] = await tx
        .select()
        .from(schema.reportRequests)
        .where(
          and(
            eq(schema.reportRequests.installationId, input.installationId),
            eq(schema.reportRequests.idempotencyKey, input.idempotencyKey),
          ),
        )
        .limit(1);
      if (request && request.payloadHash !== input.payloadHash)
        throw new ReportServiceError(
          409,
          "IDEMPOTENCY_CONFLICT",
          "This request key was used with different data.",
        );
      let [row] = await tx
        .select()
        .from(schema.healthReports)
        .where(
          and(
            eq(schema.healthReports.installationId, input.installationId),
            request
              ? eq(schema.healthReports.id, request.reportId)
              : eq(schema.healthReports.payloadHash, input.payloadHash),
          ),
        )
        .limit(1);
      const created = row === undefined;
      const now = this.now();
      if (!row) {
        [row] = await tx
          .insert(schema.healthReports)
          .values({
            id: randomUUID(),
            installationId: input.installationId,
            payloadHash: input.payloadHash,
            period: input.period,
            anchorDate: input.anchorDate,
            timeZone: input.timeZone,
            metrics: input.metrics,
            status: "processing",
            attempt: 1,
            createdAt: now,
            updatedAt: now,
          })
          .returning();
      }
      if (!row) throw new Error("Report insertion failed.");
      if (!request)
        await tx.insert(schema.reportRequests).values({
          installationId: input.installationId,
          idempotencyKey: input.idempotencyKey,
          reportId: row.id,
          payloadHash: input.payloadHash,
        });
      if (
        !created &&
        (row.status === "completed" ||
          (row.status === "processing" &&
            now.getTime() - row.updatedAt.getTime() < leaseMilliseconds))
      ) {
        return { report: resource(row), attempt: null, created: false };
      }
      await tx
        .delete(schema.reportRateLimits)
        .where(lt(schema.reportRateLimits.expiresAt, now));
      await this.consume(
        tx,
        "generation:global",
        this.limits.reportsPerDay,
        86_400,
      );
      await this.consume(
        tx,
        `generation:owner:${input.installationId}`,
        this.limits.reportsPerInstallationDay,
        86_400,
      );
      await this.consume(
        tx,
        `generation:ip:${hash(input.ip)}`,
        this.limits.reportsPerIPDay,
        86_400,
      );
      if (!created) {
        [row] = await tx
          .update(schema.healthReports)
          .set({
            status: "processing",
            failureCode: null,
            attempt: row.attempt + 1,
            updatedAt: now,
          })
          .where(
            and(
              eq(schema.healthReports.installationId, input.installationId),
              eq(schema.healthReports.id, row.id),
            ),
          )
          .returning();
      }
      if (!row) throw new Error("Report claim failed.");
      return { report: resource(row), attempt: row.attempt, created };
    });
  }

  async complete(
    installationId: string,
    reportId: string,
    attempt: number,
    narrative: ReportNarrative,
  ) {
    const [row] = await this.database
      .update(schema.healthReports)
      .set({
        status: "completed",
        model: narrative.model,
        evaluation: narrative.evaluation,
        reaction: narrative.reaction,
        recommendations: narrative.recommendations,
        failureCode: null,
        updatedAt: this.now(),
      })
      .where(
        and(
          eq(schema.healthReports.installationId, installationId),
          eq(schema.healthReports.id, reportId),
          eq(schema.healthReports.attempt, attempt),
          eq(schema.healthReports.status, "processing"),
        ),
      )
      .returning();
    if (row) return resource(row);
    const current = await this.get(installationId, reportId);
    if (!current)
      throw new ReportServiceError(
        404,
        "REPORT_NOT_FOUND",
        "The report does not exist.",
      );
    return current;
  }

  async fail(
    installationId: string,
    reportId: string,
    attempt: number,
    code: string,
  ) {
    await this.database
      .update(schema.healthReports)
      .set({ status: "failed", failureCode: code, updatedAt: this.now() })
      .where(
        and(
          eq(schema.healthReports.installationId, installationId),
          eq(schema.healthReports.id, reportId),
          eq(schema.healthReports.attempt, attempt),
          eq(schema.healthReports.status, "processing"),
        ),
      );
  }

  private async expire(installationId: string) {
    await this.database
      .update(schema.healthReports)
      .set({
        status: "failed",
        failureCode: "REPORT_INTERRUPTED",
        updatedAt: this.now(),
      })
      .where(
        and(
          eq(schema.healthReports.installationId, installationId),
          eq(schema.healthReports.status, "processing"),
          lt(
            schema.healthReports.updatedAt,
            new Date(this.now().getTime() - leaseMilliseconds),
          ),
        ),
      );
  }

  async get(installationId: string, reportId: string) {
    await this.expire(installationId);
    const [row] = await this.database
      .select()
      .from(schema.healthReports)
      .where(
        and(
          eq(schema.healthReports.installationId, installationId),
          eq(schema.healthReports.id, reportId),
        ),
      )
      .limit(1);
    return row ? resource(row) : null;
  }

  async list(
    installationId: string,
    period: ReportPeriod | undefined,
    limit: number,
    cursor: string | undefined,
  ) {
    let position: { createdAt: Date; id: string } | undefined;
    if (cursor) {
      try {
        const parsed: unknown = JSON.parse(
          Buffer.from(cursor, "base64url").toString("utf8"),
        );
        if (
          typeof parsed !== "object" ||
          parsed === null ||
          !("createdAt" in parsed) ||
          !("id" in parsed) ||
          typeof parsed.createdAt !== "string" ||
          typeof parsed.id !== "string" ||
          !/^\d{4}-\d{2}-\d{2}T.*Z$/.test(parsed.createdAt) ||
          !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(parsed.id) ||
          !Number.isFinite(Date.parse(parsed.createdAt))
        )
          throw new Error("Invalid cursor.");
        position = { createdAt: new Date(parsed.createdAt), id: parsed.id };
      } catch {
        throw new ReportServiceError(
          400,
          "INVALID_CURSOR",
          "The report cursor is invalid.",
        );
      }
    }
    await this.expire(installationId);
    const rows = await this.database
      .select()
      .from(schema.healthReports)
      .where(
        and(
          eq(schema.healthReports.installationId, installationId),
          period ? eq(schema.healthReports.period, period) : undefined,
          position
            ? or(
                lt(schema.healthReports.createdAt, position.createdAt),
                and(
                  eq(schema.healthReports.createdAt, position.createdAt),
                  lt(schema.healthReports.id, position.id),
                ),
              )
            : undefined,
        ),
      )
      .orderBy(
        desc(schema.healthReports.createdAt),
        desc(schema.healthReports.id),
      )
      .limit(limit + 1);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      data: page.map(resource),
      meta: {
        nextCursor:
          rows.length > limit && last
            ? Buffer.from(
                JSON.stringify({
                  createdAt: last.createdAt.toISOString(),
                  id: last.id,
                }),
              ).toString("base64url")
            : null,
      },
    };
  }
}
