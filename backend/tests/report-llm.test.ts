import { describe, expect, it, vi } from "vitest";
import {
  createReportNarrator,
  ReportNarrationError,
} from "../src/reports/llm.js";
import type {
  ReportMetrics,
  ReportNarrator,
} from "../src/reports/contracts.js";

const configuration = {
  baseURL: "https://provider.example/v1/",
  apiKey: "test-provider-secret",
  weeklyModel: "gpt-5.6-luna",
  monthlyModel: "gpt-6.1-sol",
  timeoutMs: 100,
};
const metrics: ReportMetrics = {
  window: {
    startDate: "2026-10-19",
    endDate: "2026-10-25",
    observedThroughDate: "2026-10-24",
    dayCount: 7,
    elapsedDays: 6,
    timeZone: "Asia/Seoul",
  },
  food: { loggedDays: 2, mealCount: 3 },
  exercise: {
    sessionCount: 1,
    totalMinutes: 20,
    totalRepetitions: null,
    byActivity: [{ activity: null, sessions: 1, totalMinutes: 20 }],
  },
  nutrition: {
    trackedMeals: 0,
    totalMeals: 3,
    carbohydratesG: null,
    proteinG: null,
    fatG: null,
    carbohydratePercent: null,
    proteinPercent: null,
    fatPercent: null,
  },
  calories: { totalKcal: 1_700, averagePerLoggedDay: 850, loggedDays: 2 },
  wellness: {
    sleepLoggedDays: 0,
    averageSleepMinutes: null,
    conditionLoggedDays: 0,
    averageCondition: null,
  },
};
const input: Parameters<ReportNarrator>[0] = {
  period: "week",
  metrics,
  goals: { steps: 6_000, calorieMinimum: null, calorieMaximum: null },
};
const narrative = {
  reaction: "curious",
  evaluation:
    "푸루(기록을 함께 살펴봤어!) 기록이 적어서 전체 습관은 단정하지 않을게.",
  recommendations: [
    {
      title: "식사 기록 이어가기",
      detail: "먹은 음식과 양을 편한 때에 적어 보자.",
    },
    {
      title: "운동 종류 남기기",
      detail: "운동을 마칠 때 어떤 활동이었는지도 선택해 보자.",
    },
    {
      title: "수면과 컨디션 기록하기",
      detail: "잠과 느낀 컨디션을 함께 남겨 보자.",
    },
  ],
};

function completion(content: unknown = narrative, finishReason = "stop") {
  return Response.json({
    choices: [
      {
        finish_reason: finishReason,
        message: { content: JSON.stringify(content) },
      },
    ],
    usage: { total_tokens: 200 },
  });
}

describe("health report AI adapter", () => {
  it("selects the period's model and sends only aggregate data with a strict schema", async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(async () => completion());
    const narrator = createReportNarrator(configuration, transport);
    expect(await narrator(input)).toEqual({
      ...narrative,
      model: "gpt-5.6-luna",
    });
    expect((await narrator({ ...input, period: "month" })).model).toBe(
      "gpt-6.1-sol",
    );
    const call = transport.mock.calls[0];
    if (!call) throw new Error("Missing provider request");
    expect(String(call[0])).toBe(
      "https://provider.example/v1/chat/completions",
    );
    expect(call[1]).toMatchObject({
      method: "POST",
      redirect: "error",
      headers: { Authorization: "Bearer test-provider-secret" },
    });
    expect(call[1]?.signal).toBeInstanceOf(AbortSignal);
    const payload: unknown = JSON.parse(String(call[1]?.body));
    expect(payload).toMatchObject({
      model: "gpt-5.6-luna",
      max_completion_tokens: 1_500,
      response_format: { type: "json_schema", json_schema: { strict: true } },
    });
    const serialized = String(call[1]?.body);
    expect(serialized).not.toContain(configuration.apiKey);
    expect(serialized).not.toContain("heightCM");
    expect(serialized).not.toContain("weightKG");
    expect(serialized).toContain("NOT proof of complete daily food intake");
    expect(serialized).toContain("No prior-period baseline");
    expect(serialized).toContain(
      "Choose one reaction aligned with the evaluation",
    );
    expect(serialized).toContain(
      "Never select a reaction based on weight, calorie deficit",
    );
    expect(payload).toMatchObject({
      response_format: {
        json_schema: {
          schema: { required: expect.arrayContaining(["reaction"]) },
        },
      },
    });
    expect(serialized).toContain(
      "Goals are current settings for future planning",
    );
  });

  it("requests brief colloquial copy without repeating detailed coverage", async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(async () => completion());
    await createReportNarrator(configuration, transport)(input);
    const call = transport.mock.calls[0];
    if (!call) throw new Error("Missing provider request");
    const serialized = String(call[1]?.body);
    expect(serialized).toContain("2–3 short sentences, targeting 100–180");
    expect(serialized).toContain("target 40–90 characters");
    expect(serialized).toContain("Use the Usagi opening once");
    expect(serialized).toContain("at most one simple sentence");
    expect(serialized).toContain(
      "do not recite the safeguards as a long disclaimer",
    );
    expect(serialized).not.toContain("80–400");
  });

  it("does not treat extreme user-entered calorie goals as approved recommendations", async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(async () => completion());
    await createReportNarrator(
      configuration,
      transport,
    )({
      ...input,
      goals: { steps: 6_000, calorieMinimum: 100, calorieMaximum: 200 },
    });
    const call = transport.mock.calls[0];
    if (!call) throw new Error("Missing provider request");
    const serialized = String(call[1]?.body);
    expect(serialized).toContain(
      "User-entered calorie and weight-loss goals are unverified and may be unsafe",
    );
    expect(serialized).toContain("Never endorse a calorie range");
    expect(serialized).toContain(
      "skipping meals, fasting, restrictive diets or compensatory exercise",
    );
    expect(serialized).toContain(
      "enjoyable movement, regular routines and rest",
    );
  });

  it.each([
    "http://provider.example/v1",
    "https://user:secret@provider.example/v1",
    "https://provider.example/v1?secret=yes",
    "https://provider.example/v1#fragment",
    "not-a-url",
  ])("refuses unsafe or malformed provider URLs", (baseURL) => {
    expect(() => createReportNarrator({ ...configuration, baseURL })).toThrow(
      ReportNarrationError,
    );
  });
  it.each([0, -1, 60_001, NaN, 1.5])(
    "bounds the generation timeout",
    (timeoutMs) => {
      expect(() =>
        createReportNarrator({ ...configuration, timeoutMs }),
      ).toThrow(ReportNarrationError);
    },
  );
  it("rejects missing keys and malformed model configuration safely", () => {
    for (const change of [
      { apiKey: " " },
      { apiKey: "secret\nvalue" },
      { monthlyModel: "bad\nmodel" },
    ]) {
      expect(() =>
        createReportNarrator({ ...configuration, ...change }),
      ).toThrow("The AI report could not be generated.");
    }
  });

  it.each([
    {
      reason: "missing reaction",
      value: {
        evaluation: narrative.evaluation,
        recommendations: narrative.recommendations,
      },
    },
    { reason: "unknown reaction", value: { ...narrative, reaction: "angry" } },
    { reason: "null reaction", value: { ...narrative, reaction: null } },
    {
      reason: "missing evaluation",
      value: { recommendations: narrative.recommendations },
    },
    { reason: "extra field", value: { ...narrative, private: "unexpected" } },
    {
      reason: "two recommendations",
      value: {
        ...narrative,
        recommendations: narrative.recommendations.slice(0, 2),
      },
    },
    {
      reason: "duplicate titles",
      value: {
        ...narrative,
        recommendations: narrative.recommendations.map((item) => ({
          ...item,
          title: " 식사   기록 ",
        })),
      },
    },
    {
      reason: "duplicate details",
      value: {
        ...narrative,
        recommendations: narrative.recommendations.map((item) => ({
          ...item,
          detail: "같은 내용",
        })),
      },
    },
    {
      reason: "whitespace",
      value: {
        ...narrative,
        recommendations: narrative.recommendations.map((item) => ({
          ...item,
          title: "  ",
        })),
      },
    },
    {
      reason: "wrong language",
      value: { ...narrative, evaluation: "Here is a report" },
    },
    {
      reason: "mixed-language filler",
      value: {
        ...narrative,
        evaluation: "푸루(기록을 accurately 살펴봤어!) 기록을 남겨 보자.",
      },
    },
    {
      reason: "control characters",
      value: {
        ...narrative,
        evaluation: "푸루(기록을 함께 살펴봤어!)\u0000기록이 필요해.",
      },
    },
    {
      reason: "unpaired surrogate",
      value: {
        ...narrative,
        evaluation: "푸루(기록을 함께 살펴봤어!)\ud800기록이 필요해.",
      },
    },
    {
      reason: "no Usagi voice",
      value: { ...narrative, evaluation: "기록을 읽었어요." },
    },
    {
      reason: "invented numerical target",
      value: {
        ...narrative,
        evaluation: "푸루(매일 900kcal를 먹어야 해.) 기록이 필요해.",
      },
    },
    {
      reason: "excessive length",
      value: { ...narrative, evaluation: "푸루(기록)".repeat(300) },
    },
  ])("rejects $reason without fabricating a replacement", async ({ value }) => {
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(async () => completion(value));
    await expect(
      createReportNarrator(configuration, transport)(input),
    ).rejects.toMatchObject({ code: "LLM_INVALID_RESPONSE" });
    expect(transport).toHaveBeenCalledTimes(1);
  });

  it.each(["celebrate", "encourage", "rest", "curious"])(
    "preserves the explicit %s reaction from valid narration",
    async (reaction) => {
      const transport = vi
        .fn<typeof fetch>()
        .mockImplementation(async () => completion({ ...narrative, reaction }));
      expect(
        (await createReportNarrator(configuration, transport)(input)).reaction,
      ).toBe(reaction);
    },
  );

  it.each(["length", "content_filter", "tool_calls"])(
    "rejects nonfinal completion %s",
    async (reason) => {
      const transport = vi
        .fn<typeof fetch>()
        .mockImplementation(async () => completion(narrative, reason));
      await expect(
        createReportNarrator(configuration, transport)(input),
      ).rejects.toMatchObject({ code: "LLM_INVALID_RESPONSE" });
    },
  );
  it.each([
    { choices: [] },
    {
      choices: [
        { finish_reason: "stop", message: { content: null, refusal: "no" } },
      ],
    },
    {
      choices: [
        { finish_reason: "stop", message: { content: "```json\n{}\n```" } },
      ],
    },
  ])("rejects empty, refused and fenced responses", async (result) => {
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(async () => Response.json(result));
    await expect(
      createReportNarrator(configuration, transport)(input),
    ).rejects.toMatchObject({ code: "LLM_INVALID_RESPONSE" });
  });

  it.each([401, 403, 429, 500, 302])(
    "sanitizes HTTP %i and does not retry",
    async (status) => {
      const transport = vi
        .fn<typeof fetch>()
        .mockImplementation(
          async () =>
            new Response(`provider detail ${configuration.apiKey}`, { status }),
        );
      try {
        await createReportNarrator(configuration, transport)(input);
        throw new Error("Expected rejection");
      } catch (error) {
        expect(error).toBeInstanceOf(ReportNarrationError);
        expect(String(error)).not.toContain(configuration.apiKey);
        expect(error).not.toHaveProperty("cause");
        expect(error).toMatchObject({
          code:
            status === 401 || status === 403
              ? "LLM_UNAVAILABLE"
              : "LLM_UPSTREAM_ERROR",
        });
      }
      expect(transport).toHaveBeenCalledTimes(1);
    },
  );
  it("sanitizes transport exceptions", async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockRejectedValue(new Error(configuration.apiKey));
    await expect(
      createReportNarrator(configuration, transport)(input),
    ).rejects.toMatchObject({
      code: "LLM_UPSTREAM_ERROR",
      message: "The AI report could not be generated.",
    });
  });
  it("rejects a refusal even when plausible content is also present", async () => {
    const transport = vi.fn<typeof fetch>().mockImplementation(async () =>
      Response.json({
        choices: [
          {
            finish_reason: "stop",
            message: { content: JSON.stringify(narrative), refusal: "refused" },
          },
        ],
      }),
    );
    await expect(
      createReportNarrator(configuration, transport)(input),
    ).rejects.toMatchObject({ code: "LLM_INVALID_RESPONSE" });
  });
  it.each([true, false])(
    "bounds streamed response bytes (declared=%s)",
    async (declared) => {
      const transport = vi.fn<typeof fetch>().mockImplementation(
        async () =>
          new Response("x".repeat(65_537), {
            headers: declared ? { "Content-Length": "65537" } : {},
          }),
      );
      await expect(
        createReportNarrator(configuration, transport)(input),
      ).rejects.toMatchObject({ code: "LLM_INVALID_RESPONSE" });
    },
  );
  it("rejects invalid JSON and invalid UTF8", async () => {
    for (const response of [
      new Response("not JSON"),
      new Response(new Uint8Array([255, 255])),
    ]) {
      const transport = vi.fn<typeof fetch>().mockResolvedValue(response);
      await expect(
        createReportNarrator(configuration, transport)(input),
      ).rejects.toMatchObject({ code: "LLM_INVALID_RESPONSE" });
    }
  });

  it("cancels before a request without contacting the provider", async () => {
    const transport = vi.fn<typeof fetch>();
    const controller = new AbortController();
    controller.abort();
    await expect(
      createReportNarrator(configuration, transport)(input, controller.signal),
    ).rejects.toMatchObject({ code: "LLM_CANCELLED" });
    expect(transport).not.toHaveBeenCalled();
  });
  it("bounds a provider that never responds", async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(() => new Promise<Response>(() => undefined));
    await expect(
      createReportNarrator(
        { ...configuration, timeoutMs: 10 },
        transport,
      )(input),
    ).rejects.toMatchObject({ code: "LLM_TIMEOUT" });
  });
  it("bounds stalled response streaming and cancels its reader", async () => {
    const cancel = vi.fn();
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(
        async () => new Response(new ReadableStream<Uint8Array>({ cancel })),
      );
    await expect(
      createReportNarrator(
        { ...configuration, timeoutMs: 10 },
        transport,
      )(input),
    ).rejects.toMatchObject({ code: "LLM_TIMEOUT" });
    expect(cancel).toHaveBeenCalled();
  });
  it("propagates caller cancellation while fetching", async () => {
    const controller = new AbortController();
    const transport = vi
      .fn<typeof fetch>()
      .mockImplementation(() => new Promise<Response>(() => undefined));
    const request = createReportNarrator(configuration, transport)(
      input,
      controller.signal,
    );
    controller.abort();
    await expect(request).rejects.toMatchObject({ code: "LLM_CANCELLED" });
  });
});
