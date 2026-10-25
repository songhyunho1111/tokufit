import { Type } from "@sinclair/typebox";
import type { Static } from "@sinclair/typebox";

const objectOptions = { additionalProperties: false };

export const FoodPhotoImageSchema = Type.Object(
  {
    mimeType: Type.Union([
      Type.Literal("image/jpeg"),
      Type.Literal("image/png"),
    ]),
    base64: Type.String({ minLength: 1, maxLength: 2_900_000 }),
  },
  objectOptions,
);
export type FoodPhotoImage = Static<typeof FoodPhotoImageSchema>;
export const FoodPhotoAnalysisRequestSchema = Type.Object(
  { image: FoodPhotoImageSchema },
  objectOptions,
);

export const FoodEstimateSchema = Type.Object(
  {
    name: Type.String({ minLength: 1, maxLength: 120 }),
    portion: Type.String({ minLength: 1, maxLength: 120 }),
    calories: Type.Integer({ minimum: 1, maximum: 5_000 }),
    nutrients: Type.Object(
      {
        carbohydratesG: Type.Number({ minimum: 0, maximum: 2_000 }),
        proteinG: Type.Number({ minimum: 0, maximum: 2_000 }),
        fatG: Type.Number({ minimum: 0, maximum: 2_000 }),
      },
      objectOptions,
    ),
    notes: Type.String({ maxLength: 300 }),
  },
  objectOptions,
);
export type FoodEstimate = Static<typeof FoodEstimateSchema>;
export const FoodAnalysisContentSchema = Type.Object(
  {
    status: Type.Union([
      Type.Literal("recognized"),
      Type.Literal("unrecognized"),
    ]),
    food: Type.Union([FoodEstimateSchema, Type.Null()]),
    message: Type.String({ minLength: 1, maxLength: 300 }),
  },
  objectOptions,
);
export type FoodAnalysisContent = Static<typeof FoodAnalysisContentSchema>;
export const FoodPhotoAnalysisResultSchema = Type.Object(
  {
    ...FoodAnalysisContentSchema.properties,
    model: Type.String({ minLength: 1, maxLength: 160 }),
  },
  objectOptions,
);
export type FoodPhotoAnalysisResult = Static<
  typeof FoodPhotoAnalysisResultSchema
>;
export type FoodPhotoAnalyzer = (
  image: FoodPhotoImage,
  signal?: AbortSignal,
) => Promise<FoodPhotoAnalysisResult>;

export const FoodPhotoAnalysisSchema = Type.Object(
  {
    ...FoodPhotoAnalysisResultSchema.properties,
    id: Type.String({ format: "uuid" }),
    createdAt: Type.String({ format: "date-time", maxLength: 40 }),
  },
  objectOptions,
);
export type FoodPhotoAnalysis = Static<typeof FoodPhotoAnalysisSchema>;
export const FoodPhotoAnalysisResponseSchema = Type.Object(
  { data: FoodPhotoAnalysisSchema },
  objectOptions,
);
