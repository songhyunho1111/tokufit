import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Pool } from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
import { and, eq, sql } from "drizzle-orm";
import { configuration } from "../src/config.js";
import * as schema from "../src/schema.js";
import { PostgresReportRepository } from "../src/reports/repository.js";
import {
  HealthReportService,
  reportFingerprint,
} from "../src/reports/service.js";
import { aggregateReport } from "../src/reports/aggregate.js";
import type {
  ReportNarrative,
  ReportRequest,
} from "../src/reports/contracts.js";

describe.skipIf(process.env.REPORT_DATABASE_TESTS !== "1")(
  "Report PostgreSQL integration",
  () => {
    let pool: Pool;
    let database: ReturnType<typeof drizzle<typeof schema>>;
    const now = new Date();
    const clock = () => now;
    const limits = {
      registrationsPerHour: 1_000,
      reportsPerInstallationDay: 1_000,
      reportsPerIPDay: 10_000,
      reportsPerDay: 100_000,
    };
    const narrative: ReportNarrative = {
      model: "test-only",
      reaction: "curious",
      evaluation: "푸루(보관된 기록을 살펴봤어. 없는 기록은 평가하지 않았어.)",
      recommendations: [
        { title: "기록 이어가기", detail: "식사 기록을 남겨 보자." },
        { title: "컨디션 적기", detail: "느낀 컨디션을 적어 보자." },
        { title: "움직임 남기기", detail: "완료한 운동을 기록해 보자." },
      ],
    };
    function input(calories = 500): ReportRequest {
      return {
        period: "week",
        anchorDate: now.toISOString().slice(0, 10),
        timeZone: "UTC",
        goals: { steps: 6_000, calorieMinimum: null, calorieMaximum: null },
        data: {
          meals: [
            {
              id: randomUUID(),
              recordedAt: now.toISOString(),
              calories,
              nutrients: null,
            },
          ],
          workouts: [],
          wellness: [],
        },
      };
    }
    const ip = () => `integration-${randomUUID()}`;
    beforeAll(() => {
      const config = configuration();
      if (
        config.database.host !== "127.0.0.1" ||
        config.database.port !== 25_432
      ) {
        throw new Error(
          "Integration tests require the explicitly isolated loopback database on port25432.",
        );
      }
      pool = new Pool(config.database);
      database = drizzle(pool, { schema });
    });
    afterAll(async () => {
      await pool?.end();
    });

    it("stores only token hashes, scopes reads and deduplicates replay aliases", async () => {
      const repository = new PostgresReportRepository(database, limits, clock);
      const owner = await repository.createInstallation(ip());
      const other = await repository.createInstallation(ip());
      expect(await repository.authenticate(owner.token)).toBe(owner.id);
      expect(await repository.authenticate("invalid")).toBeNull();
      const [saved] = await database
        .select()
        .from(schema.reportInstallations)
        .where(eq(schema.reportInstallations.id, owner.id));
      expect(saved?.tokenHash).toMatch(/^[a-f0-9]{64}$/);
      expect(saved?.tokenHash).not.toBe(owner.token);
      let calls = 0;
      const service = new HealthReportService(
        repository,
        async () => {
          calls++;
          return narrative;
        },
        clock,
      );
      const body = input();
      const firstKey = randomUUID(),
        secondKey = randomUUID();
      const first = await service.create(owner.id, firstKey, body, ip());
      const second = await service.create(owner.id, secondKey, body, ip());
      expect(first.status).toBe(201);
      expect(first.report.reaction).toBe("curious");
      expect(second.status).toBe(200);
      expect(second.report.id).toBe(first.report.id);
      expect(calls).toBe(1);
      await expect(
        service.create(owner.id, secondKey, input(600), ip()),
      ).rejects.toMatchObject({
        statusCode: 409,
        code: "IDEMPOTENCY_CONFLICT",
      });
      expect(await repository.get(other.id, first.report.id)).toBeNull();
      const stored = await database
        .select()
        .from(schema.healthReports)
        .where(eq(schema.healthReports.installationId, owner.id));
      expect(stored).toHaveLength(1);
      expect(stored[0]?.reaction).toBe("curious");
      expect(JSON.stringify(stored)).not.toContain(owner.token);
      expect(JSON.stringify(stored)).not.toContain("recordedAt");
    });

    it("keeps legacy null reactions readable and enforces the reaction domain", async () => {
      const repository = new PostgresReportRepository(database, limits, clock);
      const owner = await repository.createInstallation(ip());
      const body = input();
      let calls = 0;
      const service = new HealthReportService(
        repository,
        async () => {
          calls++;
          return narrative;
        },
        clock,
      );
      const first = await service.create(owner.id, randomUUID(), body, ip());
      await database
        .update(schema.healthReports)
        .set({ reaction: null })
        .where(eq(schema.healthReports.id, first.report.id));
      expect(
        (await repository.get(owner.id, first.report.id))?.reaction,
      ).toBeNull();
      expect(
        (await repository.list(owner.id, undefined, 10, undefined)).data[0]
          ?.reaction,
      ).toBeNull();
      expect(
        (await service.create(owner.id, randomUUID(), body, ip())).report
          .reaction,
      ).toBeNull();
      expect(calls).toBe(1);
      await expect(
        database.execute(
          sql`update health_reports set reaction = 'angry' where id = ${first.report.id}`,
        ),
      ).rejects.toThrow();
    });

    it("returns processing for concurrent duplicates and uses one generation", async () => {
      const repository = new PostgresReportRepository(database, limits, clock);
      const owner = await repository.createInstallation(ip());
      let entered = () => {},
        release = () => {};
      const started = new Promise<void>((resolve) => {
        entered = resolve;
      });
      const gate = new Promise<void>((resolve) => {
        release = resolve;
      });
      let calls = 0;
      const service = new HealthReportService(
        repository,
        async () => {
          calls++;
          entered();
          await gate;
          return narrative;
        },
        clock,
      );
      const body = input();
      const first = service.create(owner.id, randomUUID(), body, ip());
      try {
        await started;
        const pending = await service.create(
          owner.id,
          randomUUID(),
          body,
          ip(),
        );
        expect(pending.status).toBe(202);
        expect(pending.report.status).toBe("processing");
      } finally {
        release();
      }
      expect((await first).report.status).toBe("completed");
      expect(calls).toBe(1);
    });

    it("fences an expired attempt from completing or failing a newer retry", async () => {
      const repository = new PostgresReportRepository(database, limits, clock);
      const owner = await repository.createInstallation(ip());
      const body = input();
      const claimInput = {
        installationId: owner.id,
        idempotencyKey: randomUUID(),
        payloadHash: reportFingerprint(body),
        period: body.period,
        anchorDate: body.anchorDate,
        timeZone: body.timeZone,
        metrics: aggregateReport(body, now),
        ip: ip(),
      };
      const first = await repository.claim(claimInput);
      expect(first.attempt).toBe(1);
      await database
        .update(schema.healthReports)
        .set({ updatedAt: new Date(now.getTime() - 130_000) })
        .where(eq(schema.healthReports.id, first.report.id));
      expect(
        (await repository.get(owner.id, first.report.id))?.failureCode,
      ).toBe("REPORT_INTERRUPTED");
      const retry = await repository.claim(claimInput);
      expect(retry.attempt).toBe(2);
      expect(
        (await repository.complete(owner.id, first.report.id, 1, narrative))
          .status,
      ).toBe("processing");
      await repository.fail(owner.id, first.report.id, 1, "OLD_FAILURE");
      expect((await repository.get(owner.id, first.report.id))?.status).toBe(
        "processing",
      );
      const complete = await repository.complete(
        owner.id,
        retry.report.id,
        2,
        narrative,
      );
      expect(complete.status).toBe("completed");
    });

    it("atomically enforces owner and shared global generation quotas", async () => {
      const repository = new PostgresReportRepository(
        database,
        { ...limits, reportsPerInstallationDay: 1 },
        clock,
      );
      const owner = await repository.createInstallation(ip());
      const service = new HealthReportService(
        repository,
        async () => narrative,
        clock,
      );
      await service.create(owner.id, randomUUID(), input(), ip());
      await expect(
        service.create(owner.id, randomUUID(), input(501), ip()),
      ).rejects.toMatchObject({ statusCode: 429 });
      expect(
        await database
          .select()
          .from(schema.healthReports)
          .where(eq(schema.healthReports.installationId, owner.id)),
      ).toHaveLength(1);

      const [counter] = await database
        .select({ count: schema.reportRateLimits.count })
        .from(schema.reportRateLimits)
        .where(eq(schema.reportRateLimits.key, "generation:global"));
      const maximum = (counter?.count ?? 0) + 1;
      const bounded = new PostgresReportRepository(
        database,
        { ...limits, reportsPerDay: maximum },
        clock,
      );
      const first = await bounded.createInstallation(ip()),
        second = await bounded.createInstallation(ip());
      const boundedService = new HealthReportService(
        bounded,
        async () => narrative,
        clock,
      );
      const results = await Promise.allSettled([
        boundedService.create(first.id, randomUUID(), input(), ip()),
        boundedService.create(second.id, randomUUID(), input(), ip()),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      expect(
        results.filter((result) => result.status === "rejected"),
      ).toHaveLength(1);
      const [after] = await database
        .select({ count: schema.reportRateLimits.count })
        .from(schema.reportRateLimits)
        .where(eq(schema.reportRateLimits.key, "generation:global"));
      expect(after?.count).toBe(maximum);
    });

    it("bounds cached submission aliases without charging extra generations", async () => {
      const repository = new PostgresReportRepository(database, limits, clock);
      const owner = await repository.createInstallation(ip());
      let calls = 0;
      const service = new HealthReportService(
        repository,
        async () => {
          calls++;
          return narrative;
        },
        clock,
      );
      const body = input();
      const source = ip();
      for (let index = 0; index < 60; index++)
        await service.create(owner.id, randomUUID(), body, source);
      await expect(
        service.create(owner.id, randomUUID(), body, source),
      ).rejects.toMatchObject({ statusCode: 429 });
      expect(calls).toBe(1);
      const aliases = await database
        .select({ count: sql<number>`count(*)::int` })
        .from(schema.reportRequests)
        .where(eq(schema.reportRequests.installationId, owner.id));
      expect(aliases[0]?.count).toBe(60);
    });

    it("paginates equal timestamps without leaking another owner's reports", async () => {
      const repository = new PostgresReportRepository(database, limits, clock);
      const owner = await repository.createInstallation(ip());
      const other = await repository.createInstallation(ip());
      const service = new HealthReportService(
        repository,
        async () => narrative,
        clock,
      );
      for (let index = 0; index < 3; index++)
        await service.create(owner.id, randomUUID(), input(500 + index), ip());
      const page = await repository.list(owner.id, "week", 2, undefined);
      expect(page.data).toHaveLength(2);
      expect(page.meta.nextCursor).toBeTruthy();
      const rest = await repository.list(
        owner.id,
        "week",
        2,
        page.meta.nextCursor ?? undefined,
      );
      expect(rest.data).toHaveLength(1);
      expect(
        new Set([...page.data, ...rest.data].map((row) => row.id)).size,
      ).toBe(3);
      expect(
        (
          await repository.list(
            other.id,
            "week",
            2,
            page.meta.nextCursor ?? undefined,
          )
        ).data,
      ).toEqual([]);
      await expect(
        repository.list(owner.id, undefined, 2, "broken"),
      ).rejects.toMatchObject({ statusCode: 400 });
      const keys = await database
        .select()
        .from(schema.reportRequests)
        .where(
          and(
            eq(schema.reportRequests.installationId, owner.id),
            eq(
              schema.reportRequests.reportId,
              page.data[0]?.id ?? randomUUID(),
            ),
          ),
        );
      expect(keys).toHaveLength(1);
    });
  },
);
