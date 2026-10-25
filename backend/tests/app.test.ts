import { afterEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import { configuration } from "../src/config.js";

const servers: FastifyInstance[] = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map((app) => app.close()));
});
async function server(healthy = true) {
  const app = await buildApp({
    checkDatabase: async () => {
      if (!healthy) throw new Error("database secret");
    },
  });
  servers.push(app);
  return app;
}
describe("API connectivity", () => {
  it("bounds database connection and query waits", () => {
    const config = configuration({
      PGHOST: "127.0.0.1",
      PGDATABASE: "repick",
      PGUSER: "repick_app",
      PGPASSWORD: "test-only",
    });
    expect(config.database).toMatchObject({
      connectionTimeoutMillis: 2000,
      statement_timeout: 2000,
      query_timeout: 2000,
    });
  });
  it("returns the public contract with a UTC fractional timestamp", async () => {
    const app = await server();
    const response = await app.inject("/api/v1/status");
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      status: "ok",
      service: "RE:PICK",
      timestamp: expect.stringMatching(
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
      ),
    });
    const spec = (await app.inject("/api/v1/openapi.json")).json();
    expect(spec.paths["/api/v1/status"].get.responses["200"]).toBeDefined();
  });
  it("stays live but stops serving when PostgreSQL is unavailable", async () => {
    const app = await server(false);
    expect((await app.inject("/health/live")).statusCode).toBe(200);
    for (const url of ["/health/ready", "/api/v1/status"]) {
      const response = await app.inject(url);
      expect(response.statusCode).toBe(503);
      expect(response.json()).toEqual({
        code: "DEPENDENCY_UNAVAILABLE",
        message: "Service is temporarily unavailable.",
        requestId: expect.any(String),
      });
      expect(response.body).not.toContain("secret");
    }
  });
  it("normalizes validation and missing route errors", async () => {
    const app = await server();
    const invalid = await app.inject("/api/v1/status?unexpected=private");
    expect(invalid.statusCode).toBe(400);
    expect(invalid.json().code).toBe("INVALID_REQUEST");
    expect(invalid.body).not.toContain("private");
    const missing = await app.inject("/not-here");
    expect(missing.statusCode).toBe(404);
    expect(missing.json().code).toBe("NOT_FOUND");
    expect(missing.json().requestId).toEqual(expect.any(String));
    const media = await app.inject({
      method: "POST",
      url: "/api/v1/health-reports",
      headers: { "content-type": "application/octet-stream" },
      payload: "private-payload",
    });
    expect(media.statusCode).toBe(415);
    expect(media.json().code).toBe("UNSUPPORTED_MEDIA_TYPE");
    expect(media.body).not.toContain("private-payload");
  });
  it("rejects incomplete and invalid startup settings without exposing values", () => {
    expect(() => configuration({})).toThrow("Missing configuration: PGHOST");
    expect(() => configuration({ PORT: "NaN" })).toThrow(
      "Invalid configuration: PORT",
    );
    expect(() => configuration({ PORT: "70000" })).toThrow(
      "Invalid configuration: PORT",
    );
  });
});
