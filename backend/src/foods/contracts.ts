import { Type } from "@sinclair/typebox";
import { Value } from "@sinclair/typebox/value";
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

export const FoodEatingStyleSchema = Type.Union([
  Type.Literal("grass"),
  Type.Literal("noodles"),
  Type.Literal("rice"),
  Type.Literal("tteokbokki"),
]);
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
    eatingStyle: Type.Optional(
      Type.Union([FoodEatingStyleSchema, Type.Null()]),
    ),
  },
  objectOptions,
);
export type FoodEstimate = Static<typeof FoodEstimateSchema>;
const ProviderFoodEstimateSchema = Type.Object(
  { ...FoodEstimateSchema.properties, eatingStyle: FoodEatingStyleSchema },
  objectOptions,
);
export const FoodAnalysisContentSchema = Type.Object(
  {
    status: Type.Union([
      Type.Literal("recognized"),
      Type.Literal("unrecognized"),
    ]),
    food: Type.Union([ProviderFoodEstimateSchema, Type.Null()]),
    alternatives: Type.Array(ProviderFoodEstimateSchema, {
      minItems: 0,
      maxItems: 2,
    }),
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
    food: Type.Union([FoodEstimateSchema, Type.Null()]),
    alternatives: Type.Optional(
      Type.Array(ProviderFoodEstimateSchema, { minItems: 0, maxItems: 2 }),
    ),
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

function validText(text: string, allowEmpty = false): boolean {
  return (
    (allowEmpty || Boolean(text.trim())) &&
    ![...text].some((character) => {
      const code = character.codePointAt(0) ?? 0;
      return (
        code === 127 ||
        (code < 32 && !["\t", "\n", "\r"].includes(character)) ||
        (code >= 0xd800 && code <= 0xdfff)
      );
    })
  );
}

export function validFoodAnalysisContent(
  content: unknown,
): content is FoodAnalysisContent {
  if (!Value.Check(FoodAnalysisContentSchema, content)) return false;
  if (!validText(content.message) || !/[가-힣]/u.test(content.message))
    return false;
  if (content.status === "unrecognized")
    return content.food === null && content.alternatives.length === 0;
  if (!content.food) return false;
  const estimates = [content.food, ...content.alternatives];
  const names = estimates.map((food) =>
    food.name.normalize("NFKC").replace(/\s+/gu, "").toLowerCase(),
  );
  return (
    new Set(names).size === names.length &&
    estimates.every(
      (food) =>
        validText(food.name) &&
        validText(food.portion) &&
        validText(food.notes, true) &&
        [food.calories, ...Object.values(food.nutrients)].every(
          Number.isFinite,
        ),
    )
  );
}
