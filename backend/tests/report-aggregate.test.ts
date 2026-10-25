import { describe, expect, it } from "vitest";
import Fastify from "fastify";
import { aggregateReport, ReportInputError } from "../src/reports/aggregate.js";
import { ReportRequestSchema } from "../src/reports/contracts.js";
import type { ReportRequest } from "../src/reports/contracts.js";

const now = new Date("2026-10-24T12:00:00.000Z");
const id = (value: number) =>
  `00000000-0000-4000-8000-${String(value).padStart(12, "0")}`;

function meal(
  value: number,
  recordedAt: string,
  calories = 500,
): ReportRequest["data"]["meals"][number] {
  return { id: id(value), recordedAt, calories, nutrients: null };
}

function workout(value: number): ReportRequest["data"]["workouts"][number] {
  return {
    id: id(value),
    mode: "indoor",
    activity: "strength",
    startedAt: "2026-10-24T00:00:00Z",
    endedAt: "2026-10-24T00:30:00Z",
    durationMinutes: 30,
    repetitions: 20,
    distanceMeters: null,
    calories: null,
  };
}

function request(): ReportRequest {
  return {
    period: "week",
    anchorDate: "2026-10-24",
    timeZone: "Asia/Seoul",
    goals: { steps: 6_000, calorieMinimum: null, calorieMaximum: null },
    data: {
      meals: [meal(1, "2026-10-19T00:00:00Z")],
      workouts: [],
      wellness: [],
    },
  };
}

describe("deterministic health report aggregation", () => {
  it("counts recorded days, activity, known macros and partial coverage without zero-filling missing days", () => {
    const input = request();
    input.data.meals = [
      {
        ...meal(1, "2026-10-19T00:00:00Z", 500),
        nutrients: { carbohydratesG: 50, proteinG: 20, fatG: 10 },
      },
      {
        ...meal(2, "2026-10-19T09:00:00Z", 700),
        nutrients: { carbohydratesG: 30, proteinG: 10, fatG: 10 },
      },
      meal(3, "2026-10-20T00:00:00Z", 400),
    ];
    input.data.workouts = [
      workout(10),
      {
        ...workout(11),
        activity: null,
        mode: "outdoor",
        durationMinutes: 40,
        repetitions: null,
      },
    ];
    input.data.wellness = [
      { day: "2026-10-19", sleepMinutes: 0, condition: null },
      { day: "2026-10-20", sleepMinutes: 480, condition: 4 },
      { day: "2026-10-21", sleepMinutes: null, condition: 2 },
    ];
    const metrics = aggregateReport(input, now);
    expect(metrics.window).toEqual({
      startDate: "2026-10-19",
      endDate: "2026-10-25",
      observedThroughDate: "2026-10-24",
      dayCount: 7,
      elapsedDays: 6,
      timeZone: "Asia/Seoul",
    });
    expect(metrics.food).toEqual({ loggedDays: 2, mealCount: 3 });
    expect(metrics.calories).toEqual({
      totalKcal: 1_600,
      averagePerLoggedDay: 800,
      loggedDays: 2,
    });
    expect(metrics.exercise).toEqual({
      sessionCount: 2,
      totalMinutes: 70,
      totalRepetitions: 20,
      byActivity: [
        { activity: "strength", sessions: 1, totalMinutes: 30 },
        { activity: null, sessions: 1, totalMinutes: 40 },
      ],
    });
    expect(metrics.nutrition).toEqual({
      trackedMeals: 2,
      totalMeals: 3,
      carbohydratesG: 80,
      proteinG: 30,
      fatG: 20,
      carbohydratePercent: 51.6,
      proteinPercent: 19.4,
      fatPercent: 29,
    });
    expect(metrics.wellness).toEqual({
      sleepLoggedDays: 2,
      averageSleepMinutes: 240,
      conditionLoggedDays: 2,
      averageCondition: 3,
    });
  });

  it("keeps unknown nutrition and repetitions null, while explicit zero remains known", () => {
    const input = request();
    input.data.workouts = [{ ...workout(2), repetitions: null }];
    let metrics = aggregateReport(input, now);
    expect(metrics.nutrition.trackedMeals).toBe(0);
    expect(metrics.nutrition.carbohydratesG).toBeNull();
    expect(metrics.nutrition.carbohydratePercent).toBeNull();
    expect(metrics.exercise.totalRepetitions).toBeNull();
    expect(metrics.wellness.averageSleepMinutes).toBeNull();
    input.data.meals = [
      {
        ...meal(1, "2026-10-19T00:00:00Z"),
        nutrients: { carbohydratesG: 0, proteinG: 0, fatG: 0 },
      },
    ];
    input.data.workouts = [{ ...workout(2), repetitions: 0 }];
    metrics = aggregateReport(input, now);
    expect(metrics.nutrition.trackedMeals).toBe(1);
    expect(metrics.nutrition.carbohydratesG).toBe(0);
    expect(metrics.nutrition.carbohydratePercent).toBeNull();
    expect(metrics.exercise.totalRepetitions).toBe(0);
  });

  it("reports no food average for a wellness-only report", () => {
    const input = request();
    input.data.meals = [];
    input.data.wellness = [
      { day: "2026-10-24", sleepMinutes: 480, condition: null },
    ];
    const metrics = aggregateReport(input, now);
    expect(metrics.food).toEqual({ loggedDays: 0, mealCount: 0 });
    expect(metrics.calories.averagePerLoggedDay).toBeNull();
    expect(metrics.exercise.totalRepetitions).toBeNull();
  });

  it("uses local calendar boundaries and never includes outside-period or future-skew records", () => {
    const input = request();
    input.data.meals = [
      meal(1, "2026-10-18T14:59:59Z"),
      meal(2, "2026-10-18T15:00:00Z"),
      meal(3, "2026-10-24T12:00:00.001Z"),
      meal(4, "2026-10-24T12:05:00Z"),
    ];
    expect(aggregateReport(input, now).food).toEqual({
      loggedDays: 1,
      mealCount: 1,
    });
    input.data.workouts = [
      {
        ...workout(10),
        startedAt: "2026-10-18T10:00:00Z",
        endedAt: "2026-10-18T15:01:00Z",
      },
    ];
    expect(aggregateReport(input, now).exercise.sessionCount).toBe(1);
  });

  it("rejects materially future records even on today's local date", () => {
    const input = request();
    input.data.meals.push(meal(2, "2026-10-24T14:00:00Z"));
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.meals.pop();
    input.data.workouts.push({
      ...workout(2),
      endedAt: "2026-10-24T12:05:01Z",
    });
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.workouts = [];
    input.data.wellness.push({
      day: "2026-10-25",
      sleepMinutes: 480,
      condition: 3,
    });
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it("uses whole calendar days across DST and year boundaries", () => {
    const input = request();
    input.timeZone = "America/New_York";
    input.anchorDate = "2026-03-08";
    input.data.meals = [
      meal(1, "2026-03-08T04:30:00Z"),
      meal(2, "2026-03-08T07:30:00Z"),
      meal(3, "2026-03-09T03:30:00Z"),
    ];
    const metrics = aggregateReport(input, new Date("2026-03-09T04:00:00Z"));
    expect(metrics.window).toMatchObject({
      startDate: "2026-03-02",
      endDate: "2026-03-08",
      elapsedDays: 7,
      dayCount: 7,
    });
    expect(metrics.food).toEqual({ loggedDays: 2, mealCount: 3 });
    input.timeZone = "UTC";
    input.anchorDate = "2026-01-01";
    input.data.meals = [meal(1, "2025-12-30T00:00:00Z")];
    expect(
      aggregateReport(input, new Date("2026-01-01T12:00:00Z")).window,
    ).toMatchObject({
      startDate: "2025-12-29",
      endDate: "2026-01-04",
      elapsedDays: 4,
    });
  });

  it("counts leap-month days and an incomplete current month", () => {
    const input = request();
    input.period = "month";
    input.timeZone = "UTC";
    input.anchorDate = "2024-02-12";
    input.data.meals = [meal(1, "2024-02-01T00:00:00Z")];
    expect(
      aggregateReport(input, new Date("2024-02-15T12:00:00Z")).window,
    ).toMatchObject({
      startDate: "2024-02-01",
      endDate: "2024-02-29",
      observedThroughDate: "2024-02-15",
      dayCount: 29,
      elapsedDays: 15,
    });
    expect(
      aggregateReport(input, new Date("2024-03-01T12:00:00Z")).window
        .elapsedDays,
    ).toBe(29);
  });

  it("accepts the inclusive366-day anchor boundary and rejects older or future anchors", () => {
    const input = request();
    input.timeZone = "UTC";
    input.anchorDate = "2025-10-23";
    input.data.meals = [meal(1, "2025-10-23T00:00:00Z")];
    expect(aggregateReport(input, now).food.mealCount).toBe(1);
    input.anchorDate = "2025-10-22";
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.anchorDate = "2026-10-25";
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it.each(["2026-02-30", "2026-13-01", "2026-2-01", "private-input"])(
    "rejects malformed calendar anchor %s without echoing it",
    (anchor) => {
      const input = request();
      input.anchorDate = anchor;
      expect(() => aggregateReport(input, now)).toThrow(
        "The report records are invalid.",
      );
    },
  );

  it.each([
    "2026-02-30T00:00:00Z",
    "2026-10-19T24:00:00Z",
    "2026-10-19T12:00:00",
    "2026-10-19T12:60:00Z",
  ])("rejects invalid timestamps %s", (recordedAt) => {
    const input = request();
    input.data.meals = [meal(1, recordedAt)];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it("accepts timezone-bearing fractional timestamps and rejects unknown zones", () => {
    const input = request();
    input.data.meals = [meal(1, "2026-10-19T09:00:00.123+09:00")];
    expect(aggregateReport(input, now).food.mealCount).toBe(1);
    input.timeZone = "Not/A_Zone";
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.timeZone = "+09:00";
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it("rejects duplicate IDs and duplicate wellness days", () => {
    const input = request();
    input.data.meals.push({
      ...meal(2, "2026-10-20T00:00:00Z"),
      id: input.data.meals[0]?.id ?? "",
    });
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.meals.pop();
    input.data.workouts = [workout(2), workout(2)];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.workouts = [];
    input.data.wellness = [
      { day: "2026-10-24", sleepMinutes: 0, condition: null },
      { day: "2026-10-24", sleepMinutes: null, condition: 3 },
    ];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it("validates goals, numeric bounds, date ordering and absent wellness", () => {
    const input = request();
    input.goals.calorieMinimum = 2_000;
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.goals.calorieMaximum = 1_800;
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.goals.calorieMinimum = null;
    input.goals.calorieMaximum = null;
    input.data.workouts = [{ ...workout(2), endedAt: "2026-10-23T23:00:00Z" }];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.workouts = [{ ...workout(2), distanceMeters: Number.NaN }];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.workouts = [];
    input.data.wellness = [
      { day: "2026-10-24", sleepMinutes: null, condition: null },
    ];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it("rejects an empty period, bounded arrays and invalid data even outside the period", () => {
    const input = request();
    input.data.meals = [];
    expect(() => aggregateReport(input, now)).toThrow(
      "No records are available for this period.",
    );
    input.data.meals = [meal(1, "2026-10-18T00:00:00Z", -1)];
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
    input.data.meals = Array.from({ length: 1_001 }, (_, index) =>
      meal(index + 1, "2026-10-19T00:00:00Z"),
    );
    expect(() => aggregateReport(input, now)).toThrow(ReportInputError);
  });

  it("keeps rounded macro shares at100% and does not mutate input", () => {
    const input = request();
    input.data.meals = [
      {
        ...meal(1, "2026-10-19T00:00:00Z"),
        nutrients: { carbohydratesG: 9, proteinG: 9, fatG: 4 },
      },
    ];
    const before = structuredClone(input);
    const nutrition = aggregateReport(input, now).nutrition;
    expect(nutrition.carbohydratePercent).toBe(33.4);
    expect(nutrition.proteinPercent).toBe(33.3);
    expect(nutrition.fatPercent).toBe(33.3);
    expect(input).toEqual(before);
  });

  it("enforces the explicit nullable contract and rejects unexpected private fields through Fastify", async () => {
    const app = Fastify({
      ajv: { customOptions: { removeAdditional: false } },
    });
    app.post("/", { schema: { body: ReportRequestSchema } }, async () => ({
      ok: true,
    }));
    try {
      expect(
        (await app.inject({ method: "POST", url: "/", payload: request() }))
          .statusCode,
      ).toBe(200);
      expect(
        (
          await app.inject({
            method: "POST",
            url: "/",
            payload: { ...request(), name: "private" },
          })
        ).statusCode,
      ).toBe(400);
      const input = request();
      const missingNutrients = {
        ...input,
        data: {
          ...input.data,
          meals: [
            { id: id(1), recordedAt: "2026-10-19T00:00:00Z", calories: 500 },
          ],
        },
      };
      expect(
        (
          await app.inject({
            method: "POST",
            url: "/",
            payload: missingNutrients,
          })
        ).statusCode,
      ).toBe(400);
    } finally {
      await app.close();
    }
  });
});
