import { afterEach, describe, expect, it, vi } from "vitest";
import type { FastifyInstance } from "fastify";
import sharp from "sharp";
import { buildApp } from "../src/app.js";
import { configuration } from "../src/config.js";
import type {
  FoodPhotoAnalysis,
  FoodPhotoAnalysisResult,
  FoodPhotoAnalyzer,
  FoodPhotoImage,
} from "../src/foods/contracts.js";
import { FoodServiceError } from "../src/foods/errors.js";
import { FoodPhotoAnalysisService } from "../src/foods/service.js";
import { HealthReportService } from "../src/reports/service.js";

const token = "a".repeat(43);
const owner = "b725f6ed-9917-4ce4-b6ac-a1c3eed88135";
const now = new Date("2026-10-24T05:06:07.123Z");
const servers: FastifyInstance[] = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map((app) => app.close()));
});

function result(): FoodPhotoAnalysisResult {
  return {
    model: "test-vision-model",
    status: "recognized",
    message: "사진으로 추정한 값이에요. 음식과 양을 확인해 주세요.",
    food: {
      name: "바나나",
      portion: "한 개",
      calories: 105,
      nutrients: { carbohydratesG: 27, proteinG: 1.3, fatG: 0.4 },
      notes: "실제 크기에 따라 달라질 수 있어요.",
    },
  };
}
async function image(
  format: "jpeg" | "png" = "jpeg",
  width = 32,
): Promise<FoodPhotoImage> {
  const bytes = await sharp({
    create: { width, height: 32, channels: 3, background: "#ead95d" },
  })
    .withExif({ IFD0: { Artist: "private-photo-metadata" } })
    .toFormat(format)
    .toBuffer();
  return { mimeType: `image/${format}`, base64: bytes.toString("base64") };
}
async function unexpected(): Promise<never> {
  throw new Error("Unexpected report operation.");
}
async function server(
  analyze: FoodPhotoAnalyzer | undefined = async () => result(),
) {
  const quota = {
    consume: vi.fn<(owner: string, ip: string) => Promise<void>>(
      async () => {},
    ),
  };
  const reports = new HealthReportService(
    {
      authenticate: async (value) => (value === token ? owner : null),
      createInstallation: unexpected,
      limitRead: unexpected,
      limitSubmission: unexpected,
      claim: unexpected,
      complete: unexpected,
      fail: unexpected,
      get: unexpected,
      list: unexpected,
    },
    undefined,
  );
  const foods = new FoodPhotoAnalysisService(quota, analyze, () => now);
  const app = await buildApp({ checkDatabase: async () => {}, reports, foods });
  servers.push(app);
  return { app, quota, foods };
}
function post(
  app: FastifyInstance,
  photo: FoodPhotoImage,
  authorization: string = `Bearer ${token}`,
) {
  return app.inject({
    method: "POST",
    url: "/api/v1/food-analyses",
    headers: { authorization },
    payload: { image: photo },
  });
}

describe("food photo analysis API", () => {
  it.each(["jpeg", "png"] as const)(
    "validates and strips %s metadata before returning a typed review resource",
    async (format) => {
      const analyze = vi.fn<FoodPhotoAnalyzer>(async (photo) => {
        const metadata = await sharp(
          Buffer.from(photo.base64, "base64"),
        ).metadata();
        expect(metadata.format).toBe(format);
        expect(metadata.exif).toBeUndefined();
        return result();
      });
      const { app, quota } = await server(analyze);
      const photo = await image(format);
      const response = await post(app, photo);
      expect(response.statusCode).toBe(201);
      expect(response.headers["cache-control"]).toBe("no-store");
      const analysis = response.json<{ data: FoodPhotoAnalysis }>().data;
      expect(analysis).toMatchObject({
        ...result(),
        createdAt: now.toISOString(),
        id: expect.any(String),
      });
      expect(analysis.id).toMatch(/^[0-9a-f-]{36}$/);
      expect(quota.consume).toHaveBeenCalledExactlyOnceWith(owner, "127.0.0.1");
      expect(analyze).toHaveBeenCalledOnce();
      expect(response.body).not.toContain(photo.base64);
      expect(response.body).not.toContain(token);
      expect(response.body).not.toContain(owner);
    },
  );

  it("returns unrecognized without inventing food or nutrients", async () => {
    const { app } = await server(async () => ({
      model: "test",
      status: "unrecognized",
      food: null,
      message: "음식이 잘 보이도록 다시 찍어 주세요.",
    }));
    const response = await post(app, await image());
    expect(response.statusCode).toBe(201);
    expect(response.json<{ data: FoodPhotoAnalysis }>().data).toMatchObject({
      status: "unrecognized",
      food: null,
    });
  });

  it.each(["", "Bearer invalid", `Bearer ${"z".repeat(43)}`])(
    "requires a valid installation bearer (%s)",
    async (credential) => {
      const analyze = vi.fn<FoodPhotoAnalyzer>(async () => result());
      const { app, quota } = await server(analyze);
      const response = await post(app, await image(), credential);
      expect(response.statusCode).toBe(401);
      expect(response.json<{ code: string }>().code).toBe("UNAUTHORIZED");
      expect(analyze).not.toHaveBeenCalled();
      expect(quota.consume).not.toHaveBeenCalled();
    },
  );

  it("rejects unknown fields and unsupported declared MIME types with safe schema errors", async () => {
    const { app } = await server();
    for (const payload of [
      { image: await image(), secret: "private-extra" },
      { image: { mimeType: "image/heic", base64: "private-image" } },
    ]) {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/food-analyses",
        headers: { authorization: `Bearer ${token}` },
        payload,
      });
      expect(response.statusCode).toBe(400);
      expect(response.body).not.toContain("private-");
    }
  });

  it("rejects malformed base64, unreadable pixels, mismatched formats and oversized dimensions before provider use", async () => {
    const analyze = vi.fn<FoodPhotoAnalyzer>(async () => result());
    const { app, quota } = await server(analyze);
    const jpeg = await image();
    const png = await image("png");
    const bytes = Buffer.from(jpeg.base64, "base64");
    const cases: FoodPhotoImage[] = [
      { mimeType: "image/jpeg", base64: "private-not-base64" },
      {
        mimeType: "image/jpeg",
        base64: Buffer.from("private-text").toString("base64"),
      },
      {
        mimeType: "image/jpeg",
        base64: bytes.subarray(0, bytes.length - 30).toString("base64"),
      },
      { ...png, mimeType: "image/jpeg" },
      { ...jpeg, base64: `${jpeg.base64}\n` },
      await image("png", 2049),
    ];
    for (const photo of cases) {
      const response = await post(app, photo);
      expect(response.statusCode).toBe(422);
      expect(response.json<{ code: string }>().code).toBe("FOOD_IMAGE_INVALID");
      expect(response.body).not.toContain("private-");
    }
    expect(analyze).not.toHaveBeenCalled();
    expect(quota.consume).toHaveBeenCalledTimes(cases.length);
  });

  it("bounds decoded image and JSON body bytes", async () => {
    const analyze = vi.fn<FoodPhotoAnalyzer>(async () => result());
    const { app, quota } = await server(analyze);
    const decoded = await post(app, {
      mimeType: "image/png",
      base64: Buffer.alloc(2_097_153).toString("base64"),
    });
    expect(decoded.statusCode).toBe(413);
    const body = await post(app, {
      mimeType: "image/png",
      base64: "a".repeat(2_900_001),
    });
    expect(body.statusCode).toBe(413);
    expect(analyze).not.toHaveBeenCalled();
    expect(quota.consume).toHaveBeenCalledOnce();
  });

  it.each(["blank", "pairing", "nan", "infinity", "range"])(
    "rejects invalid %s output without mock success",
    async (kind) => {
      const invalid = result();
      if (kind === "blank") invalid.message = "  ";
      if (kind === "pairing") invalid.status = "unrecognized";
      if (!invalid.food) throw new Error("Fixture requires food.");
      if (kind === "nan") invalid.food.nutrients.proteinG = NaN;
      if (kind === "infinity") invalid.food.nutrients.proteinG = Infinity;
      if (kind === "range") invalid.food.calories = 5001;
      const { app } = await server(async () => invalid);
      const response = await post(app, await image());
      expect(response.statusCode).toBe(502);
      expect(response.json<{ code: string }>().code).toBe(
        "FOOD_LLM_INVALID_RESPONSE",
      );
    },
  );

  it.each([
    ["FOOD_LLM_TIMEOUT", 504],
    ["FOOD_LLM_UPSTREAM_ERROR", 502],
    ["FOOD_LLM_INVALID_RESPONSE", 502],
    ["FOOD_LLM_UNAVAILABLE", 503],
    ["UNKNOWN", 502],
  ] as const)("sanitizes %s and does not retry", async (code, status) => {
    const analyze = vi.fn<FoodPhotoAnalyzer>(async () => {
      throw Object.assign(new Error("private-key-provider-output"), { code });
    });
    const { app } = await server(analyze);
    const response = await post(app, await image());
    expect(response.statusCode).toBe(status);
    expect(response.body).not.toContain("private-");
    expect(response.json<{ requestId: string }>().requestId).toEqual(
      expect.any(String),
    );
    expect(analyze).toHaveBeenCalledOnce();
  });

  it("enforces persistent quota before decoding even an unreadable image", async () => {
    const analyze = vi.fn<FoodPhotoAnalyzer>(async () => result());
    const { app, quota } = await server(analyze);
    quota.consume.mockRejectedValue(
      new FoodServiceError(
        429,
        "FOOD_RATE_LIMITED",
        "Please try again later.",
        123,
      ),
    );
    const response = await post(app, {
      mimeType: "image/png",
      base64: Buffer.from("unreadable").toString("base64"),
    });
    expect(response.statusCode).toBe(429);
    expect(response.headers["retry-after"]).toBe("123");
    expect(analyze).not.toHaveBeenCalled();
  });

  it("does not call the provider when PostgreSQL quota accounting is unavailable", async () => {
    const analyze = vi.fn<FoodPhotoAnalyzer>(async () => result());
    const { app, quota } = await server(analyze);
    quota.consume.mockRejectedValue(new Error("private-database-connection"));
    const response = await post(app, await image());
    expect(response.statusCode).toBe(503);
    expect(response.json<{ code: string }>().code).toBe(
      "FOOD_SERVICE_UNAVAILABLE",
    );
    expect(response.body).not.toContain("private-");
    expect(analyze).not.toHaveBeenCalled();
  });

  it("does not charge quota when the provider is unconfigured", async () => {
    const { app, quota, foods } = await server();
    foods.close();
    const response = await post(app, await image());
    expect(response.statusCode).toBe(503);
    expect(quota.consume).not.toHaveBeenCalled();
    const unconfigured = new FoodPhotoAnalysisService(quota, undefined);
    await expect(
      unconfigured.create(owner, await image(), "ip"),
    ).rejects.toMatchObject({ statusCode: 503 });
  });

  it.each(["disconnect", "shutdown"] as const)(
    "cancels upstream analysis on %s",
    async (mode) => {
      let cancelled = false;
      const analyze = vi.fn<FoodPhotoAnalyzer>(
        async (_photo, signal) =>
          new Promise((_resolve, reject) => {
            if (!signal) throw new Error("Expected cancellation signal.");
            signal.addEventListener(
              "abort",
              () => {
                cancelled = true;
                reject(
                  Object.assign(new Error("private-abort-details"), {
                    code: "FOOD_LLM_CANCELLED",
                  }),
                );
              },
              { once: true },
            );
          }),
      );
      const { app } = await server(analyze);
      const address = await app.listen({ host: "127.0.0.1", port: 0 });
      const controller = new AbortController();
      const pending = fetch(`${address}/api/v1/food-analyses`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ image: await image() }),
        signal: controller.signal,
      });
      await vi.waitFor(() => expect(analyze).toHaveBeenCalledOnce());
      if (mode === "disconnect") {
        controller.abort();
        await expect(pending).rejects.toMatchObject({ name: "AbortError" });
      } else {
        await app.close();
        expect((await pending).status).toBe(503);
      }
      await vi.waitFor(() => expect(cancelled).toBe(true));
    },
  );

  it("bounds simultaneous image decoding and analysis, then cancels all work on shutdown", async () => {
    const analyze = vi.fn<FoodPhotoAnalyzer>(
      async (_photo, signal) =>
        new Promise((_resolve, reject) => {
          if (!signal) throw new Error("Expected cancellation signal.");
          signal.addEventListener(
            "abort",
            () => reject(new Error("private-cancelled")),
            { once: true },
          );
        }),
    );
    const { foods, quota } = await server(analyze);
    const photo = await image();
    const work = Array.from({ length: 4 }, () =>
      foods.create(owner, photo, "ip"),
    );
    const settled = Promise.allSettled(work);
    await vi.waitFor(() => expect(analyze).toHaveBeenCalledTimes(4));
    await expect(foods.create(owner, photo, "ip")).rejects.toMatchObject({
      statusCode: 429,
      retryAfter: 5,
    });
    expect(quota.consume).toHaveBeenCalledTimes(4);
    foods.close();
    expect((await settled).every((item) => item.status === "rejected")).toBe(
      true,
    );
  });

  it("publishes the installation bearer, bounded request and errors in OpenAPI", async () => {
    const { app } = await server();
    const spec = (await app.inject("/api/v1/openapi.json")).json<{
      paths: Record<
        string,
        { post: { security: unknown; responses: Record<string, unknown> } }
      >;
    }>();
    const route = spec.paths["/api/v1/food-analyses"]?.post;
    expect(route?.security).toEqual([{ reportBearer: [] }]);
    for (const status of [
      "201",
      "401",
      "413",
      "422",
      "429",
      "502",
      "503",
      "504",
    ])
      expect(route?.responses[status]).toBeDefined();
  });

  it("validates food model and quota configuration", () => {
    const env = {
      PGHOST: "127.0.0.1",
      PGDATABASE: "repick",
      PGUSER: "repick_app",
      PGPASSWORD: "test-only",
      LLM_API_KEY: "test-only",
    };
    expect(configuration(env).foods).toMatchObject({
      llm: { model: "gpt-5.6-luna" },
      limits: {
        analysesPerInstallationDay: 20,
        analysesPerIPDay: 50,
        analysesPerDay: 200,
      },
    });
    expect(() =>
      configuration({ ...env, LLM_FOOD_MODEL: "bad model\n" }),
    ).toThrow("Invalid configuration: LLM model");
    expect(() =>
      configuration({ ...env, FOOD_ANALYSES_GLOBAL_PER_DAY: "0" }),
    ).toThrow("Invalid configuration: FOOD_ANALYSES_GLOBAL_PER_DAY");
  });
});
