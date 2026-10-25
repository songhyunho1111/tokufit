import { randomBytes, randomUUID } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import type {
  ReportNarrative,
  ReportNarrator,
  ReportPeriod,
  ReportRequest,
  ReportResource,
} from "../src/reports/contracts.js";
import { ReportServiceError } from "../src/reports/errors.js";
import type {
  ReportClaim,
  ReportRepository,
} from "../src/reports/repository.js";
import { HealthReportService } from "../src/reports/service.js";

const now = new Date("2026-10-24T12:00:00.000Z");
const servers: FastifyInstance[] = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map((app) => app.close()));
});

function requestBody(): ReportRequest {
  return {
    period: "week",
    anchorDate: "2026-10-24",
    timeZone: "Asia/Seoul",
    goals: { steps: 6_000, calorieMinimum: null, calorieMaximum: null },
    data: {
      meals: [
        {
          id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          recordedAt: "2026-10-23T03:00:00Z",
          calories: 600,
          nutrients: { carbohydratesG: 70, proteinG: 25, fatG: 20 },
        },
      ],
      workouts: [],
      wellness: [],
    },
  };
}

function narrative(): ReportNarrative {
  return {
    model: "test-model",
    reaction: "curious",
    evaluation: "푸루(보관된 기록을 함께 살펴봤어. 빠진 날은 아직 알 수 없어.)",
    recommendations: [
      { title: "식사 기록", detail: "먹은 음식의 양을 함께 적어 보자." },
      {
        title: "운동 기록",
        detail: "편하게 할 수 있는 활동을 마치고 남겨 보자.",
      },
      { title: "수면 기록", detail: "일어난 뒤 잠과 컨디션을 기록해 보자." },
    ],
  };
}

// Unit boundary fake only; the production repository uses PostgreSQL transactions.
class FakeReports implements ReportRepository {
  readonly installations = new Map<string, string>();
  readonly reports = new Map<
    string,
    { owner: string; hash: string; attempt: number; resource: ReportResource }
  >();
  readonly requests = new Map<string, { hash: string; id: string }>();
  readLimited = false;
  registrationLimited = false;
  submissionLimited = false;
  submissions = 0;

  async createInstallation() {
    if (this.registrationLimited) {
      throw new ReportServiceError(
        429,
        "REPORT_RATE_LIMITED",
        "Try later.",
        60,
      );
    }
    const id = randomUUID();
    const token = randomBytes(32).toString("base64url");
    this.installations.set(token, id);
    return { id, token };
  }

  async authenticate(token: string) {
    return this.installations.get(token) ?? null;
  }

  async limitRead() {
    if (this.readLimited) {
      throw new ReportServiceError(
        429,
        "REPORT_RATE_LIMITED",
        "Try later.",
        12,
      );
    }
  }

  async limitSubmission() {
    this.submissions += 1;
    if (this.submissionLimited) {
      throw new ReportServiceError(
        429,
        "REPORT_RATE_LIMITED",
        "Try later.",
        30,
      );
    }
  }

  async claim(
    input: Parameters<ReportRepository["claim"]>[0],
  ): Promise<ReportClaim> {
    const key = `${input.installationId}:${input.idempotencyKey}`;
    const previous = this.requests.get(key);
    if (previous && previous.hash !== input.payloadHash) {
      throw new ReportServiceError(
        409,
        "IDEMPOTENCY_CONFLICT",
        "This key was used with different data.",
      );
    }
    let row = previous
      ? this.reports.get(previous.id)
      : [...this.reports.values()].find(
          (item) =>
            item.owner === input.installationId &&
            item.hash === input.payloadHash,
        );
    if (row) {
      this.requests.set(key, { hash: input.payloadHash, id: row.resource.id });
      if (row.resource.status !== "failed") {
        return { report: row.resource, attempt: null, created: false };
      }
      row.attempt += 1;
      row.resource = {
        ...row.resource,
        status: "processing",
        failureCode: null,
      };
      return { report: row.resource, attempt: row.attempt, created: false };
    }
    const id = randomUUID();
    row = {
      owner: input.installationId,
      hash: input.payloadHash,
      attempt: 1,
      resource: {
        id,
        period: input.period,
        anchorDate: input.anchorDate,
        timeZone: input.timeZone,
        status: "processing",
        createdAt: now.toISOString(),
        model: null,
        metrics: input.metrics,
        evaluation: null,
        reaction: null,
        recommendations: [],
        failureCode: null,
      },
    };
    this.reports.set(id, row);
    this.requests.set(key, { hash: input.payloadHash, id });
    return { report: row.resource, attempt: 1, created: true };
  }

  async complete(
    owner: string,
    id: string,
    attempt: number,
    result: ReportNarrative,
  ) {
    const row = this.reports.get(id);
    if (!row || row.owner !== owner) throw new Error("Missing fake report.");
    if (row.attempt === attempt) {
      row.resource = {
        ...row.resource,
        ...result,
        status: "completed",
        failureCode: null,
      };
    }
    return row.resource;
  }

  async fail(owner: string, id: string, attempt: number, code: string) {
    const row = this.reports.get(id);
    if (row?.owner === owner && row.attempt === attempt) {
      row.resource = { ...row.resource, status: "failed", failureCode: code };
    }
  }

  async get(owner: string, id: string) {
    const row = this.reports.get(id);
    return row?.owner === owner ? row.resource : null;
  }

  async list(owner: string, period: ReportPeriod | undefined, limit: number) {
    return {
      data: [...this.reports.values()]
        .filter(
          (row) =>
            row.owner === owner &&
            (period === undefined || row.resource.period === period),
        )
        .slice(0, limit)
        .map((row) => row.resource),
      meta: { nextCursor: null },
    };
  }
}

async function server(narrator: ReportNarrator | undefined) {
  const repository = new FakeReports();
  const reports = new HealthReportService(repository, narrator, () => now);
  const app = await buildApp({
    checkDatabase: async () => {},
    reports,
  });
  servers.push(app);
  return { app, repository };
}

async function register(app: FastifyInstance) {
  const response = await app.inject({
    method: "POST",
    url: "/api/v1/report-installations",
    payload: {},
  });
  expect(response.statusCode).toBe(201);
  expect(response.headers["cache-control"]).toBe("no-store");
  const result = response.json<{ data: { id: string; token: string } }>().data;
  expect(result.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  return result;
}

function createReport(
  app: FastifyInstance,
  token: string,
  payload: ReportRequest = requestBody(),
  key: string = randomUUID(),
) {
  return app.inject({
    method: "POST",
    url: "/api/v1/health-reports",
    headers: { authorization: `Bearer ${token}`, "idempotency-key": key },
    payload,
  });
}

describe("health report API boundaries", () => {
  it("creates a report, exposes only its owner's resources and keeps the token out of reports", async () => {
    const generate = vi.fn<ReportNarrator>(async () => narrative());
    const { app } = await server(generate);
    const owner = await register(app);
    const other = await register(app);
    const response = await createReport(app, owner.token);
    expect(response.statusCode).toBe(201);
    const report = response.json<{ data: ReportResource }>().data;
    expect(response.headers.location).toBe(
      `/api/v1/health-reports/${report.id}`,
    );
    expect(report.status).toBe("completed");
    expect(report.reaction).toBe("curious");
    expect(report.recommendations).toHaveLength(3);
    expect(report.metrics.food).toEqual({ loggedDays: 1, mealCount: 1 });
    expect(generate).toHaveBeenCalledOnce();
    expect(response.body).not.toContain(owner.token);
    expect(response.body).not.toContain(owner.id);
    const read = await app.inject({
      url: `/api/v1/health-reports/${report.id}`,
      headers: { authorization: `Bearer ${owner.token}` },
    });
    expect(read.statusCode).toBe(200);
    expect(read.json<{ data: ReportResource }>().data).toEqual(report);
    const denied = await app.inject({
      url: `/api/v1/health-reports/${report.id}`,
      headers: { authorization: `Bearer ${other.token}` },
    });
    expect(denied.statusCode).toBe(404);
    expect(denied.body).not.toContain(report.evaluation);
    const list = await app.inject({
      url: "/api/v1/health-reports?period=week&limit=2",
      headers: { authorization: `Bearer ${owner.token}` },
    });
    expect(list.statusCode).toBe(200);
    expect(list.json<{ data: ReportResource[] }>().data).toEqual([report]);
    const empty = await app.inject({
      url: "/api/v1/health-reports",
      headers: { authorization: `Bearer ${other.token}` },
    });
    expect(empty.json<{ data: ReportResource[] }>().data).toEqual([]);
  });

  it.each(["celebrate", "encourage", "rest", "curious"] as const)(
    "returns the explicit %s reaction on creation and fetch",
    async (reaction) => {
      const { app } = await server(async () => ({ ...narrative(), reaction }));
      const owner = await register(app);
      const response = await createReport(app, owner.token);
      expect(response.statusCode).toBe(201);
      const report = response.json<{ data: ReportResource }>().data;
      expect(report.reaction).toBe(reaction);
      const read = await app.inject({
        url: `/api/v1/health-reports/${report.id}`,
        headers: { authorization: `Bearer ${owner.token}` },
      });
      expect(read.json<{ data: ReportResource }>().data.reaction).toBe(
        reaction,
      );
    },
  );

  it("preserves null reactions on legacy reports without regenerating", async () => {
    const generate = vi.fn<ReportNarrator>(async () => narrative());
    const { app, repository } = await server(generate);
    const owner = await register(app);
    const created = await createReport(app, owner.token);
    const id = created.json<{ data: ReportResource }>().data.id;
    const saved = repository.reports.get(id);
    if (!saved) throw new Error("Missing saved report.");
    saved.resource = { ...saved.resource, reaction: null };
    const replay = await createReport(app, owner.token);
    expect(replay.statusCode).toBe(200);
    expect(replay.json<{ data: ReportResource }>().data.reaction).toBeNull();
    expect(generate).toHaveBeenCalledOnce();
  });

  it.each([undefined, "Bearer invalid", `Bearer ${"x".repeat(43)}`])(
    "rejects missing or invalid bearer credentials",
    async (authorization) => {
      const { app } = await server(async () => narrative());
      const response = await app.inject({
        url: "/api/v1/health-reports",
        headers: authorization ? { authorization } : {},
      });
      expect(response.statusCode).toBe(401);
      expect(response.json<{ code: string }>().code).toBe("UNAUTHORIZED");
      if (authorization) expect(response.body).not.toContain(authorization);
    },
  );

  it("preserves missing values separately from explicit zero through HTTP validation and serialization", async () => {
    const { app } = await server(async () => narrative());
    const { token } = await register(app);
    const input = requestBody();
    input.data.meals = input.data.meals.map((meal) => ({
      ...meal,
      nutrients: null,
    }));
    input.data.wellness = [
      { day: "2026-10-22", sleepMinutes: null, condition: 4 },
      { day: "2026-10-23", sleepMinutes: 0, condition: null },
    ];
    const response = await createReport(app, token, input);
    expect(response.statusCode).toBe(201);
    const metrics = response.json<{ data: ReportResource }>().data.metrics;
    expect(metrics.nutrition).toMatchObject({
      trackedMeals: 0,
      carbohydratesG: null,
      proteinG: null,
      fatG: null,
      carbohydratePercent: null,
      proteinPercent: null,
      fatPercent: null,
    });
    expect(metrics.wellness).toEqual({
      sleepLoggedDays: 1,
      averageSleepMinutes: 0,
      conditionLoggedDays: 1,
      averageCondition: 4,
    });
    expect(metrics.exercise.totalRepetitions).toBeNull();
  });

  it("replays a completed request without another AI call and rejects key reuse with different input", async () => {
    const generate = vi.fn<ReportNarrator>(async () => narrative());
    const { app, repository } = await server(generate);
    const { token } = await register(app);
    const key = randomUUID();
    const first = await createReport(app, token, requestBody(), key);
    const replay = await createReport(app, token, requestBody(), key);
    expect(replay.statusCode).toBe(200);
    expect(replay.json()).toEqual(first.json());
    expect(generate).toHaveBeenCalledOnce();
    const changed = requestBody();
    changed.goals.steps = 7_000;
    const conflict = await createReport(app, token, changed, key);
    expect(conflict.statusCode).toBe(409);
    expect(conflict.json<{ code: string }>().code).toBe("IDEMPOTENCY_CONFLICT");
    expect(generate).toHaveBeenCalledOnce();
    expect(repository.submissions).toBe(3);
    repository.submissionLimited = true;
    const limitedReplay = await createReport(app, token, requestBody(), key);
    expect(limitedReplay.statusCode).toBe(429);
    expect(limitedReplay.headers["retry-after"]).toBe("30");
    expect(generate).toHaveBeenCalledOnce();
  });

  it("keeps the HTTP connection open for a generation lasting longer than ten seconds", async () => {
    const { app } = await server(async () => {
      await new Promise<void>((resolve) => setTimeout(resolve, 10_500));
      return narrative();
    });
    const { token } = await register(app);
    const address = await app.listen({ host: "127.0.0.1", port: 0 });
    const response = await fetch(`${address}/api/v1/health-reports`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": randomUUID(),
        "content-type": "application/json",
      },
      body: JSON.stringify(requestBody()),
      signal: AbortSignal.timeout(18_000),
    });
    expect(response.status).toBe(201);
    expect(await response.json()).toMatchObject({
      data: { status: "completed" },
    });
  }, 20_000);

  it("returns a processing resource for a concurrent retry", async () => {
    let release: ((value: ReportNarrative) => void) | undefined;
    let started: (() => void) | undefined;
    const entered = new Promise<void>((resolve) => {
      started = resolve;
    });
    const pending = new Promise<ReportNarrative>((resolve) => {
      release = resolve;
    });
    const generate = vi.fn<ReportNarrator>(async () => {
      started?.();
      return pending;
    });
    const { app } = await server(generate);
    const { token } = await register(app);
    const key = randomUUID();
    const first = createReport(app, token, requestBody(), key);
    await entered;
    const second = await createReport(app, token, requestBody(), key);
    expect(second.statusCode).toBe(202);
    expect(second.headers["retry-after"]).toBe("2");
    expect(second.json<{ data: ReportResource }>().data.status).toBe(
      "processing",
    );
    if (!release) throw new Error("Narrator did not start.");
    release(narrative());
    expect((await first).statusCode).toBe(201);
    expect(generate).toHaveBeenCalledOnce();
  });

  it("cancels upstream work and records failure when the HTTP client disconnects", async () => {
    const generate = vi.fn<ReportNarrator>(async (_input, signal) => {
      if (!signal) throw new Error("Expected a request cancellation signal.");
      return new Promise<ReportNarrative>((_resolve, reject) => {
        signal.addEventListener(
          "abort",
          () =>
            reject(
              Object.assign(new Error("private cancellation details"), {
                code: "LLM_CANCELLED",
              }),
            ),
          { once: true },
        );
      });
    });
    const { app, repository } = await server(generate);
    const { token } = await register(app);
    const address = await app.listen({ host: "127.0.0.1", port: 0 });
    const controller = new AbortController();
    const pending = fetch(`${address}/api/v1/health-reports`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": randomUUID(),
        "content-type": "application/json",
      },
      body: JSON.stringify(requestBody()),
      signal: controller.signal,
    });
    await vi.waitFor(() => expect(generate).toHaveBeenCalledOnce());
    controller.abort();
    await expect(pending).rejects.toMatchObject({ name: "AbortError" });
    await vi.waitFor(() => {
      const report = [...repository.reports.values()][0]?.resource;
      expect(report?.status).toBe("failed");
      expect(report?.failureCode).toBe("LLM_CANCELLED");
    });
  });

  it("uses safe validation errors and bounds request bytes", async () => {
    const generate = vi.fn<ReportNarrator>(async () => narrative());
    const { app } = await server(generate);
    const { token } = await register(app);
    const extra = await app.inject({
      method: "POST",
      url: "/api/v1/health-reports",
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": randomUUID(),
      },
      payload: { ...requestBody(), userId: "private-owner-value" },
    });
    expect(extra.statusCode).toBe(400);
    expect(extra.body).not.toContain("private-owner-value");
    const invalid = requestBody();
    invalid.timeZone = "private-invalid-zone";
    const semantic = await createReport(app, token, invalid);
    expect(semantic.statusCode).toBe(422);
    expect(semantic.body).not.toContain("private-invalid-zone");
    const empty = requestBody();
    empty.data.meals = [];
    const noData = await createReport(app, token, empty);
    expect(noData.statusCode).toBe(422);
    expect(noData.json<{ code: string }>().code).toBe("NO_REPORT_DATA");
    const oversized = await app.inject({
      method: "POST",
      url: "/api/v1/health-reports",
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": randomUUID(),
        "content-type": "application/json",
      },
      payload: JSON.stringify({
        ...requestBody(),
        padding: "private-input".repeat(30_000),
      }),
    });
    expect(oversized.statusCode).toBe(413);
    expect(oversized.body).not.toContain("private-input");
    expect(generate).not.toHaveBeenCalled();
  });

  it.each([
    "short",
    "duplicate",
    "blank",
    "missing reaction",
    "null reaction",
    "unknown reaction",
  ])(
    "rejects an invalid %s narrative without inventing a replacement",
    async (kind) => {
      const invalid = narrative();
      if (kind === "short") invalid.recommendations.pop();
      if (kind === "duplicate")
        invalid.recommendations = Array.from({ length: 3 }, () => ({
          title: "같은 제목",
          detail: "서로 다른 제목이 필요합니다.",
        }));
      if (kind === "blank") invalid.evaluation = "   ";
      if (kind.endsWith("reaction")) {
        Object.defineProperty(invalid, "reaction", {
          value:
            kind === "missing reaction"
              ? undefined
              : kind === "null reaction"
                ? null
                : "angry",
        });
      }
      const { app } = await server(async () => invalid);
      const { token } = await register(app);
      const response = await createReport(app, token);
      expect(response.statusCode).toBe(502);
      expect(response.json<{ code: string }>().code).toBe(
        "LLM_INVALID_RESPONSE",
      );
      const location = response.headers.location;
      expect(typeof location).toBe("string");
      if (typeof location !== "string")
        throw new Error("Missing failed resource location.");
      const read = await app.inject({
        url: location,
        headers: { authorization: `Bearer ${token}` },
      });
      const failed = read.json<{ data: ReportResource }>().data;
      expect(failed.status).toBe("failed");
      expect(failed.evaluation).toBeNull();
      expect(failed.recommendations).toEqual([]);
    },
  );

  it.each([
    ["LLM_TIMEOUT", 504],
    ["LLM_UPSTREAM_ERROR", 502],
    ["UNKNOWN", 502],
  ] as const)("sanitizes provider failure %s", async (code, status) => {
    const { app } = await server(async () => {
      throw Object.assign(new Error("private-provider-key-and-prompt"), {
        code,
      });
    });
    const { token } = await register(app);
    const response = await createReport(app, token);
    expect(response.statusCode).toBe(status);
    expect(response.body).not.toContain("private-provider");
    expect(response.body).not.toContain(token);
    expect(response.json<{ requestId: string }>().requestId).toEqual(
      expect.any(String),
    );
  });

  it("reports configuration and rate limits without pretending generation succeeded", async () => {
    const { app, repository } = await server(undefined);
    const { token } = await register(app);
    const unavailable = await createReport(app, token);
    expect(unavailable.statusCode).toBe(503);
    expect(unavailable.headers["retry-after"]).toBe("60");
    expect(repository.reports.size).toBe(0);
    repository.readLimited = true;
    const limited = await app.inject({
      url: "/api/v1/health-reports",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(limited.statusCode).toBe(429);
    expect(limited.headers["retry-after"]).toBe("12");
    repository.registrationLimited = true;
    expect(
      (
        await app.inject({
          method: "POST",
          url: "/api/v1/report-installations",
          payload: {},
        })
      ).statusCode,
    ).toBe(429);
  });

  it("publishes report schemas and bearer requirements in OpenAPI", async () => {
    const { app } = await server(async () => narrative());
    const response = await app.inject("/api/v1/openapi.json");
    const spec = response.json<{
      paths: Record<
        string,
        {
          post?: { security: unknown; responses: Record<string, unknown> };
          get?: { security: unknown };
        }
      >;
      components: { securitySchemes: Record<string, { scheme: string }> };
    }>();
    expect(spec.paths["/api/v1/health-reports"]?.post?.security).toEqual([
      { reportBearer: [] },
    ]);
    expect(
      spec.paths["/api/v1/health-reports/:id"]?.get?.security ??
        spec.paths["/api/v1/health-reports/{id}"]?.get?.security,
    ).toEqual([{ reportBearer: [] }]);
    expect(
      spec.paths["/api/v1/health-reports"]?.post?.responses["201"],
    ).toBeDefined();
    expect(spec.components.securitySchemes.reportBearer?.scheme).toBe("bearer");
    const badLimit = await app.inject("/api/v1/health-reports?limit=999");
    expect(badLimit.statusCode).toBe(400);
  });
});
