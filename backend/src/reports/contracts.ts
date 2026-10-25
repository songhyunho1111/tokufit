import { Type } from "@sinclair/typebox";
import type { Static, TSchema } from "@sinclair/typebox";

const objectOptions = { additionalProperties: false };
const nullable = <T extends TSchema>(schema: T) =>
  Type.Union([schema, Type.Null()]);
const Day = Type.String({ format: "date", pattern: "^\\d{4}-\\d{2}-\\d{2}$" });
const Timestamp = Type.String({ format: "date-time", maxLength: 40 });
const UUID = Type.String({ format: "uuid" });
const Nonnegative = Type.Number({ minimum: 0 });
const Count = Type.Integer({ minimum: 0 });

export const ReportPeriodSchema = Type.Union([
  Type.Literal("week"),
  Type.Literal("month"),
]);
export type ReportPeriod = Static<typeof ReportPeriodSchema>;
export const ReportReactionSchema = Type.Union([
  Type.Literal("celebrate"),
  Type.Literal("encourage"),
  Type.Literal("rest"),
  Type.Literal("curious"),
]);
export type ReportReaction = Static<typeof ReportReactionSchema>;
export const WorkoutActivitySchema = Type.Union([
  Type.Literal("walking"),
  Type.Literal("running"),
  Type.Literal("cycling"),
  Type.Literal("strength"),
  Type.Literal("stretching"),
  Type.Literal("other"),
  Type.Null(),
]);

export const ReportRequestSchema = Type.Object(
  {
    period: ReportPeriodSchema,
    anchorDate: Day,
    timeZone: Type.String({ minLength: 1, maxLength: 80 }),
    goals: Type.Object(
      {
        steps: Type.Integer({
          minimum: 2_000,
          maximum: 10_000,
          multipleOf: 1_000,
        }),
        calorieMinimum: nullable(Type.Integer({ minimum: 0, maximum: 10_000 })),
        calorieMaximum: nullable(Type.Integer({ minimum: 1, maximum: 10_000 })),
      },
      objectOptions,
    ),
    data: Type.Object(
      {
        meals: Type.Array(
          Type.Object(
            {
              id: UUID,
              recordedAt: Timestamp,
              calories: Type.Integer({ minimum: 1, maximum: 5_000 }),
              nutrients: Type.Union([
                Type.Object(
                  {
                    carbohydratesG: Type.Number({ minimum: 0, maximum: 2_000 }),
                    proteinG: Type.Number({ minimum: 0, maximum: 2_000 }),
                    fatG: Type.Number({ minimum: 0, maximum: 2_000 }),
                  },
                  objectOptions,
                ),
                Type.Null(),
              ]),
            },
            objectOptions,
          ),
          { maxItems: 1_000 },
        ),
        workouts: Type.Array(
          Type.Object(
            {
              id: UUID,
              mode: Type.Union([
                Type.Literal("outdoor"),
                Type.Literal("indoor"),
              ]),
              activity: WorkoutActivitySchema,
              startedAt: Timestamp,
              endedAt: Timestamp,
              durationMinutes: Type.Integer({ minimum: 1, maximum: 1_440 }),
              repetitions: nullable(
                Type.Integer({ minimum: 0, maximum: 100_000 }),
              ),
              distanceMeters: nullable(
                Type.Number({ minimum: 0, maximum: 200_000 }),
              ),
              calories: nullable(Type.Integer({ minimum: 0, maximum: 10_000 })),
            },
            objectOptions,
          ),
          { maxItems: 200 },
        ),
        wellness: Type.Array(
          Type.Object(
            {
              day: Day,
              sleepMinutes: nullable(
                Type.Integer({ minimum: 0, maximum: 1_440 }),
              ),
              condition: nullable(Type.Integer({ minimum: 1, maximum: 5 })),
            },
            objectOptions,
          ),
          { maxItems: 31 },
        ),
      },
      objectOptions,
    ),
  },
  objectOptions,
);
export type ReportRequest = Static<typeof ReportRequestSchema>;
export type ReportGoals = ReportRequest["goals"];

export const ReportMetricsSchema = Type.Object(
  {
    window: Type.Object(
      {
        startDate: Day,
        endDate: Day,
        observedThroughDate: Day,
        dayCount: Type.Integer({ minimum: 7, maximum: 31 }),
        elapsedDays: Type.Integer({ minimum: 1, maximum: 31 }),
        timeZone: Type.String({ minLength: 1, maxLength: 80 }),
      },
      objectOptions,
    ),
    food: Type.Object({ loggedDays: Count, mealCount: Count }, objectOptions),
    exercise: Type.Object(
      {
        sessionCount: Count,
        totalMinutes: Count,
        totalRepetitions: nullable(Type.Integer({ minimum: 0 })),
        byActivity: Type.Array(
          Type.Object(
            {
              activity: WorkoutActivitySchema,
              sessions: Count,
              totalMinutes: Count,
            },
            objectOptions,
          ),
          { maxItems: 7 },
        ),
      },
      objectOptions,
    ),
    nutrition: Type.Object(
      {
        trackedMeals: Count,
        totalMeals: Count,
        carbohydratesG: nullable(Nonnegative),
        proteinG: nullable(Nonnegative),
        fatG: nullable(Nonnegative),
        carbohydratePercent: nullable(
          Type.Number({ minimum: 0, maximum: 100 }),
        ),
        proteinPercent: nullable(Type.Number({ minimum: 0, maximum: 100 })),
        fatPercent: nullable(Type.Number({ minimum: 0, maximum: 100 })),
      },
      objectOptions,
    ),
    calories: Type.Object(
      {
        totalKcal: Count,
        averagePerLoggedDay: nullable(Nonnegative),
        loggedDays: Count,
      },
      objectOptions,
    ),
    wellness: Type.Object(
      {
        sleepLoggedDays: Count,
        averageSleepMinutes: nullable(
          Type.Number({ minimum: 0, maximum: 1_440 }),
        ),
        conditionLoggedDays: Count,
        averageCondition: nullable(Type.Number({ minimum: 1, maximum: 5 })),
      },
      objectOptions,
    ),
  },
  objectOptions,
);
export type ReportMetrics = Static<typeof ReportMetricsSchema>;

const RecommendationSchema = Type.Object(
  {
    title: Type.String({ minLength: 1, maxLength: 80 }),
    detail: Type.String({ minLength: 1, maxLength: 500 }),
  },
  objectOptions,
);
export const NarrativeContentSchema = Type.Object(
  {
    evaluation: Type.String({ minLength: 1, maxLength: 1_200 }),
    reaction: ReportReactionSchema,
    recommendations: Type.Array(RecommendationSchema, {
      minItems: 3,
      maxItems: 3,
    }),
  },
  objectOptions,
);
export const ReportNarrativeSchema = Type.Object(
  {
    ...NarrativeContentSchema.properties,
    model: Type.String({ minLength: 1, maxLength: 160 }),
  },
  objectOptions,
);
export type ReportNarrative = Static<typeof ReportNarrativeSchema>;
export type ReportNarrator = (
  input: { period: ReportPeriod; metrics: ReportMetrics; goals: ReportGoals },
  signal?: AbortSignal,
) => Promise<ReportNarrative>;

export const ReportSchema = Type.Object(
  {
    id: UUID,
    period: ReportPeriodSchema,
    anchorDate: Day,
    timeZone: Type.String({ minLength: 1, maxLength: 80 }),
    status: Type.Union([
      Type.Literal("processing"),
      Type.Literal("completed"),
      Type.Literal("failed"),
    ]),
    createdAt: Timestamp,
    model: nullable(Type.String({ minLength: 1, maxLength: 160 })),
    metrics: ReportMetricsSchema,
    evaluation: nullable(Type.String({ minLength: 1, maxLength: 1_200 })),
    reaction: Type.Optional(nullable(ReportReactionSchema)),
    recommendations: Type.Array(RecommendationSchema, { maxItems: 3 }),
    failureCode: nullable(Type.String({ minLength: 1, maxLength: 80 })),
  },
  objectOptions,
);
export type ReportResource = Static<typeof ReportSchema>;
export const ReportResponseSchema = Type.Object(
  { data: ReportSchema },
  objectOptions,
);
export const ReportListSchema = Type.Object(
  {
    data: Type.Array(ReportSchema, { maxItems: 50 }),
    meta: Type.Object(
      { nextCursor: nullable(Type.String({ maxLength: 512 })) },
      objectOptions,
    ),
  },
  objectOptions,
);
export const InstallationResponseSchema = Type.Object(
  {
    data: Type.Object(
      { id: UUID, token: Type.String({ minLength: 32, maxLength: 128 }) },
      objectOptions,
    ),
  },
  objectOptions,
);
export const ReportErrorSchema = Type.Object(
  {
    code: Type.String(),
    message: Type.String(),
    requestId: Type.String(),
  },
  objectOptions,
);
