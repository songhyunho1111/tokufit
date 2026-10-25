import { describe, expect, it, vi } from "vitest";
import { Value } from "@sinclair/typebox/value";
import sharp from "sharp";
import {
  FoodAnalysisContentSchema,
  FoodPhotoAnalysisSchema,
} from "../src/foods/contracts.js";
import type {
  FoodAnalysisContent,
  FoodPhotoImage,
  FoodPhotoAnalysisResult,
} from "../src/foods/contracts.js";
import { createFoodPhotoAnalyzer } from "../src/foods/provider.js";
import { FoodPhotoAnalysisService } from "../src/foods/service.js";

const configuration = {
  baseURL: "https://provider.example/v1/",
  apiKey: "test-secret",
  model: "gpt-5.6-luna",
};
const image: FoodPhotoImage = { mimeType: "image/jpeg", base64: "dGVzdA==" };
const primary = {
  name: "비빔국수",
  portion: "약 한 그릇",
  calories: 520,
  nutrients: { carbohydratesG: 89, proteinG: 14, fatG: 12 },
  notes: "양념과 면의 양에 따라 달라져요.",
  eatingStyle: "noodles" as const,
};
const alternative = {
  name: "쫄면",
  portion: "약 한 그릇",
  calories: 610,
  nutrients: { carbohydratesG: 112, proteinG: 15, fatG: 11 },
  notes: "면 종류와 소스의 양을 확인해 주세요.",
  eatingStyle: "noodles" as const,
};
const secondAlternative = { ...alternative, name: "비빔냉면", calories: 580 };
const recognized: FoodAnalysisContent = {
  status: "recognized",
  food: primary,
  alternatives: [alternative, secondAlternative],
  message: "사진으로 추정한 값이에요. 음식과 양을 확인해 주세요.",
};

function transportFor(content: unknown) {
  return vi.fn<typeof fetch>().mockResolvedValue(
    Response.json({
      choices: [
        {
          finish_reason: "stop",
          message: { content: JSON.stringify(content) },
        },
      ],
    }),
  );
}

describe("food alternatives contract", () => {
  it("returns complete distinct candidates with their own nutrition in one vision call", async () => {
    const transport = transportFor(recognized);
    const result = await createFoodPhotoAnalyzer(
      configuration,
      transport,
    )(image);
    expect(result).toEqual({ ...recognized, model: configuration.model });
    expect(result.alternatives[0]).toEqual(alternative);
    expect(result.alternatives[0]?.nutrients).not.toEqual(primary.nutrients);
    expect(transport).toHaveBeenCalledTimes(1);
    const call = transport.mock.calls[0];
    const body: unknown = JSON.parse(String(call?.[1]?.body));
    expect(String(call?.[0])).toBe(
      "https://provider.example/v1/chat/completions",
    );
    expect(body).toMatchObject({
      model: configuration.model,
      max_completion_tokens: 2_500,
      response_format: {
        json_schema: {
          strict: true,
          schema: {
            required: expect.arrayContaining(["alternatives"]),
            properties: {
              alternatives: {
                type: "array",
                minItems: 0,
                maxItems: 2,
                items: {
                  required: expect.arrayContaining([
                    "name",
                    "portion",
                    "calories",
                    "nutrients",
                    "notes",
                    "eatingStyle",
                  ]),
                },
              },
            },
          },
        },
      },
    });
    expect(String(call?.[1]?.body)).toContain("same visible meal and portion");
    expect(String(call?.[1]?.body)).toContain("fixed/default alternatives");
    expect(String(call?.[1]?.body)).not.toContain(configuration.apiKey);
  });

  it.each([0, 1, 2])(
    "accepts %i alternatives without inventing more",
    async (count) => {
      const content = {
        ...recognized,
        alternatives: recognized.alternatives.slice(0, count),
      };
      const transport = transportFor(content);
      expect(
        await createFoodPhotoAnalyzer(configuration, transport)(image),
      ).toEqual({
        ...content,
        model: configuration.model,
      });
      expect(transport).toHaveBeenCalledTimes(1);
    },
  );

  it("keeps an unrecognized image empty", async () => {
    const content = {
      ...recognized,
      status: "unrecognized",
      food: null,
      alternatives: [],
    };
    expect(
      await createFoodPhotoAnalyzer(
        configuration,
        transportFor(content),
      )(image),
    ).toEqual({
      ...content,
      model: configuration.model,
    });
  });

  it.each([
    undefined,
    null,
    {},
    [alternative, secondAlternative, { ...alternative, name: "막국수" }],
    [{ ...alternative, name: " " }],
    [{ ...alternative, portion: " " }],
    [{ ...alternative, notes: "확인\u0000" }],
    [{ ...alternative, calories: 0 }],
    [{ ...alternative, calories: 5_001 }],
    [{ ...alternative, calories: 1.5 }],
    [{ ...alternative, nutrients: { carbohydratesG: 1, proteinG: 1 } }],
    [
      {
        ...alternative,
        nutrients: { carbohydratesG: -1, proteinG: 1, fatG: 1 },
      },
    ],
    [
      {
        ...alternative,
        nutrients: { carbohydratesG: 1, proteinG: 2_001, fatG: 1 },
      },
    ],
    [{ ...alternative, eatingStyle: undefined }],
    [{ ...alternative, eatingStyle: null }],
    [{ ...alternative, eatingStyle: "soup" }],
    [{ ...primary, name: " 비빔 국수 ", calories: 900 }],
    [alternative, { ...alternative, calories: 900 }],
  ])(
    "rejects incomplete or contradictory candidates %#",
    async (alternatives) => {
      const transport = transportFor({ ...recognized, alternatives });
      await expect(
        createFoodPhotoAnalyzer(configuration, transport)(image),
      ).rejects.toMatchObject({
        code: "FOOD_LLM_INVALID_RESPONSE",
      });
      expect(transport).toHaveBeenCalledTimes(1);
    },
  );

  it("rejects candidates for an unrecognized image", async () => {
    const transport = transportFor({
      ...recognized,
      status: "unrecognized",
      food: null,
    });
    await expect(
      createFoodPhotoAnalyzer(configuration, transport)(image),
    ).rejects.toMatchObject({
      code: "FOOD_LLM_INVALID_RESPONSE",
    });
  });

  it("rejects nonfinite candidate nutrition", async () => {
    const content = JSON.stringify(recognized).replace(
      '"proteinG":15',
      '"proteinG":1e309',
    );
    const transport = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        choices: [{ finish_reason: "stop", message: { content } }],
      }),
    );
    await expect(
      createFoodPhotoAnalyzer(configuration, transport)(image),
    ).rejects.toMatchObject({
      code: "FOOD_LLM_INVALID_RESPONSE",
    });
  });

  it("requires the new provider array while keeping the public legacy field optional", () => {
    const legacy = {
      status: recognized.status,
      food: recognized.food,
      message: recognized.message,
    };
    expect(Value.Check(FoodAnalysisContentSchema, legacy)).toBe(false);
    expect(FoodPhotoAnalysisSchema.required).not.toContain("alternatives");
    expect(
      Value.Check(
        FoodPhotoAnalysisSchema.properties.alternatives,
        recognized.alternatives,
      ),
    ).toBe(true);
  });

  it("preserves complete candidates through the service with the original analysis identity", async () => {
    const bytes = await sharp({
      create: { width: 8, height: 8, channels: 3, background: "#feefce" },
    })
      .jpeg()
      .toBuffer();
    const analyze = vi.fn(async () => ({
      ...recognized,
      model: configuration.model,
    }));
    const service = new FoodPhotoAnalysisService(
      { consume: async () => {} },
      analyze,
    );
    try {
      const result = await service.create(
        "test-owner",
        {
          mimeType: "image/jpeg",
          base64: bytes.toString("base64"),
        },
        "127.0.0.1",
      );
      expect(result).toMatchObject({
        ...recognized,
        model: configuration.model,
      });
      expect(result.id).toMatch(/^[a-f0-9-]{36}$/u);
      expect(analyze).toHaveBeenCalledTimes(1);
    } finally {
      service.close();
    }
  });

  it.each<FoodPhotoAnalysisResult>([
    { ...recognized, model: "custom", status: "unrecognized", food: null },
    {
      ...recognized,
      model: "custom",
      alternatives: [{ ...primary, calories: 900 }],
    },
    {
      ...recognized,
      model: "custom",
      alternatives: [
        alternative,
        secondAlternative,
        { ...alternative, name: "막국수" },
      ],
    },
    {
      ...recognized,
      model: "custom",
      alternatives: [{ ...alternative, portion: " " }],
    },
  ])(
    "rejects invalid custom analyzer candidates at the service boundary %#",
    async (content) => {
      const bytes = await sharp({
        create: { width: 8, height: 8, channels: 3, background: "#feefce" },
      })
        .jpeg()
        .toBuffer();
      const service = new FoodPhotoAnalysisService(
        { consume: async () => {} },
        async () => content,
      );
      try {
        await expect(
          service.create(
            "test-owner",
            {
              mimeType: "image/jpeg",
              base64: bytes.toString("base64"),
            },
            "127.0.0.1",
          ),
        ).rejects.toMatchObject({ code: "FOOD_LLM_INVALID_RESPONSE" });
      } finally {
        service.close();
      }
    },
  );
});
