import { randomUUID } from "node:crypto";
import { Value } from "@sinclair/typebox/value";
import sharp from "sharp";
import { FoodPhotoAnalysisResultSchema } from "./contracts.js";
import type {
  FoodPhotoAnalysis,
  FoodPhotoAnalyzer,
  FoodPhotoImage,
} from "./contracts.js";
import { FoodServiceError } from "./errors.js";
import type { FoodAnalysisQuota } from "./quota.js";

const maximumBytes = 2_097_152;
const maximumDimension = 2_048;
const maximumConcurrent = 4;
const providerCodes = new Set([
  "FOOD_LLM_TIMEOUT",
  "FOOD_LLM_UPSTREAM_ERROR",
  "FOOD_LLM_INVALID_RESPONSE",
  "FOOD_LLM_UNAVAILABLE",
  "FOOD_LLM_CANCELLED",
]);

async function validatedImage(image: FoodPhotoImage): Promise<FoodPhotoImage> {
  const bytes = Buffer.from(image.base64, "base64");
  if (bytes.length > maximumBytes)
    throw new FoodServiceError(
      413,
      "PAYLOAD_TOO_LARGE",
      "The image is too large.",
    );
  if (!bytes.length || bytes.toString("base64") !== image.base64)
    throw new FoodServiceError(
      422,
      "FOOD_IMAGE_INVALID",
      "A readable JPEG or PNG image is required.",
    );
  try {
    const decoder = sharp(bytes, {
      failOn: "warning",
      limitInputPixels: maximumDimension * maximumDimension,
    });
    const metadata = await decoder.metadata();
    if (
      !metadata.width ||
      !metadata.height ||
      metadata.width > maximumDimension ||
      metadata.height > maximumDimension ||
      (metadata.pages ?? 1) !== 1 ||
      (metadata.format !== "jpeg" && metadata.format !== "png") ||
      image.mimeType !== `image/${metadata.format}`
    ) {
      throw new Error("Unsupported image.");
    }
    // Full decoding catches truncated pixels; re-encoding strips embedded metadata.
    const normalized = await decoder
      .rotate()
      .toFormat(metadata.format)
      .timeout({ seconds: 5 })
      .toBuffer();
    if (normalized.length > maximumBytes)
      throw new FoodServiceError(
        413,
        "PAYLOAD_TOO_LARGE",
        "The image is too large.",
      );
    return { mimeType: image.mimeType, base64: normalized.toString("base64") };
  } catch (error) {
    if (error instanceof FoodServiceError) throw error;
    throw new FoodServiceError(
      422,
      "FOOD_IMAGE_INVALID",
      "A readable JPEG or PNG image up to 2048 pixels is required.",
    );
  }
}

export class FoodPhotoAnalysisService {
  private readonly active = new Set<AbortController>();
  private closing = false;

  constructor(
    private readonly quota: FoodAnalysisQuota,
    private readonly analyze: FoodPhotoAnalyzer | undefined,
    private readonly now: () => Date = () => new Date(),
  ) {}

  close() {
    this.closing = true;
    for (const controller of this.active) controller.abort();
  }

  async create(
    installationId: string,
    image: FoodPhotoImage,
    ip: string,
    signal?: AbortSignal,
  ): Promise<FoodPhotoAnalysis> {
    if (!this.analyze || this.closing)
      throw new FoodServiceError(
        503,
        "FOOD_SERVICE_UNAVAILABLE",
        "Food analysis is unavailable.",
        60,
      );
    if (this.active.size >= maximumConcurrent)
      throw new FoodServiceError(
        429,
        "FOOD_RATE_LIMITED",
        "Please try again later.",
        5,
      );
    const controller = new AbortController();
    const cancelled = () => controller.abort();
    if (signal?.aborted) controller.abort();
    signal?.addEventListener("abort", cancelled, { once: true });
    this.active.add(controller);
    try {
      controller.signal.throwIfAborted();
      try {
        await this.quota.consume(installationId, ip);
      } catch (error) {
        if (error instanceof FoodServiceError) throw error;
        throw new FoodServiceError(
          503,
          "FOOD_SERVICE_UNAVAILABLE",
          "Food analysis is unavailable.",
          60,
        );
      }
      controller.signal.throwIfAborted();
      const normalized = await validatedImage(image);
      controller.signal.throwIfAborted();
      const result = await this.analyze(normalized, controller.signal);
      controller.signal.throwIfAborted();
      if (
        !Value.Check(FoodPhotoAnalysisResultSchema, result) ||
        !result.model.trim() ||
        !result.message.trim() ||
        (result.status === "recognized") !== (result.food !== null) ||
        (result.food !== null &&
          (!result.food.name.trim() || !result.food.portion.trim()))
      ) {
        throw new FoodServiceError(
          502,
          "FOOD_LLM_INVALID_RESPONSE",
          "The food analysis response was incomplete.",
        );
      }
      return {
        ...result,
        id: randomUUID(),
        createdAt: this.now().toISOString(),
      };
    } catch (error) {
      if (error instanceof FoodServiceError) throw error;
      const code = controller.signal.aborted
        ? "FOOD_LLM_CANCELLED"
        : error instanceof Error &&
            "code" in error &&
            typeof error.code === "string" &&
            providerCodes.has(error.code)
          ? error.code
          : "FOOD_LLM_UPSTREAM_ERROR";
      throw new FoodServiceError(
        this.closing || code === "FOOD_LLM_UNAVAILABLE"
          ? 503
          : code === "FOOD_LLM_TIMEOUT"
            ? 504
            : 502,
        code,
        "The food photo could not be analyzed. Please try again.",
      );
    } finally {
      signal?.removeEventListener("abort", cancelled);
      this.active.delete(controller);
    }
  }
}
