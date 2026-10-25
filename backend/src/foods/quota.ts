import { createHash } from "node:crypto";
import { and, like, lt, sql } from "drizzle-orm";
import type { NodePgDatabase } from "drizzle-orm/node-postgres";
import * as schema from "../schema.js";
import { FoodServiceError } from "./errors.js";

export interface FoodAnalysisLimits {
  analysesPerInstallationDay: number;
  analysesPerIPDay: number;
  analysesPerDay: number;
}

export interface FoodAnalysisQuota {
  consume(installationId: string, ip: string): Promise<void>;
}

export class PostgresFoodAnalysisQuota implements FoodAnalysisQuota {
  constructor(
    private readonly database: NodePgDatabase<typeof schema>,
    private readonly limits: FoodAnalysisLimits,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async consume(installationId: string, ip: string) {
    const now = this.now();
    const dayMilliseconds = 86_400_000;
    const start = new Date(
      Math.floor(now.getTime() / dayMilliseconds) * dayMilliseconds,
    );
    const expiry = new Date(start.getTime() + dayMilliseconds);
    const counters: [string, number][] = [
      ["food:generation:global", this.limits.analysesPerDay],
      [
        `food:generation:owner:${installationId}`,
        this.limits.analysesPerInstallationDay,
      ],
      [
        `food:generation:ip:${createHash("sha256").update(ip).digest("hex")}`,
        this.limits.analysesPerIPDay,
      ],
    ];
    await this.database.transaction(async (tx) => {
      await tx
        .delete(schema.reportRateLimits)
        .where(
          and(
            like(schema.reportRateLimits.key, "food:%"),
            lt(schema.reportRateLimits.expiresAt, now),
          ),
        );
      for (const [key, maximum] of counters) {
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
          throw new FoodServiceError(
            429,
            "FOOD_RATE_LIMITED",
            "Please try again later.",
            Math.max(1, Math.ceil((expiry.getTime() - now.getTime()) / 1_000)),
          );
      }
    });
  }
}
