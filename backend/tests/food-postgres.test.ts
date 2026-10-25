import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Pool } from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
import { and, eq, inArray, like, lte } from "drizzle-orm";
import { configuration } from "../src/config.js";
import * as schema from "../src/schema.js";
import { PostgresFoodAnalysisQuota } from "../src/foods/quota.js";

describe.skipIf(process.env.FOOD_DATABASE_TESTS !== "1")(
  "Food analysis PostgreSQL quotas",
  () => {
    let pool: Pool;
    let database: ReturnType<typeof drizzle<typeof schema>>;
    let reserved = false;
    const windows = [1, 2, 3, 4, 5].map(
      (day) => new Date(`1960-01-0${day}T00:00:00.000Z`),
    );
    const sentinel = `food-quota-test:${randomUUID()}`;
    const limits = {
      analysesPerInstallationDay: 10,
      analysesPerIPDay: 10,
      analysesPerDay: 100,
    };
    const source = () => `private-test-ip-${randomUUID()}`;
    const rowsAt = (date: Date) =>
      database
        .select()
        .from(schema.reportRateLimits)
        .where(
          and(
            like(schema.reportRateLimits.key, "food:%"),
            eq(schema.reportRateLimits.windowStart, date),
          ),
        );

    beforeAll(async () => {
      const config = configuration();
      if (
        config.database.host !== "127.0.0.1" ||
        config.database.port !== 25_432
      ) {
        throw new Error(
          "Food integration tests require the isolated loopback database on port 25432.",
        );
      }
      pool = new Pool(config.database);
      database = drizzle(pool, { schema });
      // Reserve old windows so cleanup cannot remove active QA quotas.
      const existing = await database
        .select({ key: schema.reportRateLimits.key })
        .from(schema.reportRateLimits)
        .where(
          and(
            like(schema.reportRateLimits.key, "food:%"),
            lte(
              schema.reportRateLimits.windowStart,
              new Date("1960-01-05T00:00:00.000Z"),
            ),
          ),
        )
        .limit(1);
      if (existing.length > 0)
        throw new Error("The food quota test windows are already occupied.");
      reserved = true;
    });

    afterAll(async () => {
      try {
        if (reserved) {
          await database
            .delete(schema.reportRateLimits)
            .where(
              and(
                like(schema.reportRateLimits.key, "food:%"),
                inArray(schema.reportRateLimits.windowStart, windows),
              ),
            );
          await database
            .delete(schema.reportRateLimits)
            .where(eq(schema.reportRateLimits.key, sentinel));
        }
      } finally {
        await pool?.end();
      }
    });

    it("shares owner quotas between instances and rolls back rejected counters", async () => {
      const now = new Date("1960-01-01T12:00:00.000Z");
      const owner = randomUUID();
      const bounded = { ...limits, analysesPerInstallationDay: 1 };
      const first = new PostgresFoodAnalysisQuota(database, bounded, () => now);
      const second = new PostgresFoodAnalysisQuota(
        database,
        bounded,
        () => now,
      );
      const results = await Promise.allSettled([
        first.consume(owner, source()),
        second.consume(owner, source()),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      expect(
        results.find((result) => result.status === "rejected"),
      ).toMatchObject({
        reason: {
          statusCode: 429,
          code: "FOOD_RATE_LIMITED",
          retryAfter: 43_200,
        },
      });
      const rows = await rowsAt(new Date("1960-01-01T00:00:00.000Z"));
      expect(rows).toHaveLength(3);
      expect(rows.every((row) => row.count === 1)).toBe(true);
      expect(JSON.stringify(rows)).not.toContain("private-test-ip");
      expect(rows.find((row) => row.key.includes(":ip:"))?.key).toMatch(
        /:ip:[a-f0-9]{64}$/,
      );
    });

    it("enforces one IP quota across owners without charging the rejected owner", async () => {
      const now = new Date("1960-01-02T12:00:00.000Z");
      const bounded = { ...limits, analysesPerIPDay: 1 };
      const first = new PostgresFoodAnalysisQuota(database, bounded, () => now);
      const second = new PostgresFoodAnalysisQuota(
        database,
        bounded,
        () => now,
      );
      const ip = source();
      const results = await Promise.allSettled([
        first.consume(randomUUID(), ip),
        second.consume(randomUUID(), ip),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      expect(
        results.find((result) => result.status === "rejected"),
      ).toMatchObject({
        reason: { statusCode: 429, code: "FOOD_RATE_LIMITED" },
      });
      const rows = await rowsAt(new Date("1960-01-02T00:00:00.000Z"));
      expect(rows).toHaveLength(3);
      expect(rows.every((row) => row.count === 1)).toBe(true);
    });

    it("atomically caps global usage across distinct owners and instances", async () => {
      const now = new Date("1960-01-03T12:00:00.000Z");
      const bounded = { ...limits, analysesPerDay: 1 };
      const first = new PostgresFoodAnalysisQuota(database, bounded, () => now);
      const second = new PostgresFoodAnalysisQuota(
        database,
        bounded,
        () => now,
      );
      const results = await Promise.allSettled([
        first.consume(randomUUID(), source()),
        second.consume(randomUUID(), source()),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      expect(
        results.find((result) => result.status === "rejected"),
      ).toMatchObject({
        reason: { statusCode: 429, code: "FOOD_RATE_LIMITED" },
      });
      const rows = await rowsAt(new Date("1960-01-03T00:00:00.000Z"));
      expect(rows).toHaveLength(3);
      expect(rows.every((row) => row.count === 1)).toBe(true);
    });

    it("resets at UTC midnight, reports the remaining wait and preserves other quota namespaces", async () => {
      let now = new Date("1960-01-04T23:59:30.000Z");
      const owner = randomUUID(),
        ip = source();
      const quota = new PostgresFoodAnalysisQuota(
        database,
        { ...limits, analysesPerInstallationDay: 1 },
        () => now,
      );
      await database.insert(schema.reportRateLimits).values({
        key: sentinel,
        windowStart: new Date("1960-01-04T00:00:00.000Z"),
        expiresAt: new Date("1960-01-04T01:00:00.000Z"),
        count: 7,
      });
      await quota.consume(owner, ip);
      await expect(quota.consume(owner, ip)).rejects.toMatchObject({
        statusCode: 429,
        retryAfter: 30,
      });
      now = new Date("1960-01-05T00:00:00.001Z");
      await quota.consume(owner, ip);
      expect(await rowsAt(new Date("1960-01-04T00:00:00.000Z"))).toEqual([]);
      const rows = await rowsAt(new Date("1960-01-05T00:00:00.000Z"));
      expect(rows).toHaveLength(3);
      expect(rows.every((row) => row.count === 1)).toBe(true);
      const [preserved] = await database
        .select()
        .from(schema.reportRateLimits)
        .where(eq(schema.reportRateLimits.key, sentinel));
      expect(preserved?.count).toBe(7);
    });
  },
);
