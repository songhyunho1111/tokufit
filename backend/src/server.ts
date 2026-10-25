import { Pool } from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
import { sql } from "drizzle-orm";
import { buildApp } from "./app.js";
import { configuration } from "./config.js";
import * as schema from "./schema.js";
import { PostgresReportRepository } from "./reports/repository.js";
import { HealthReportService } from "./reports/service.js";
import { createReportNarrator } from "./reports/llm.js";
import { FoodPhotoAnalysisService } from "./foods/service.js";
import { PostgresFoodAnalysisQuota } from "./foods/quota.js";
import { createFoodPhotoAnalyzer } from "./foods/provider.js";

const config = configuration();
const pool = new Pool(config.database);
const database = drizzle(pool, { schema });
const app = await buildApp({
  checkDatabase: async () => {
    await database.execute(sql`select
      (select id from report_installations limit 1),
      (select reaction from health_reports limit 1),
      (select key from report_rate_limits limit 1)`);
  },
  logger: true,
  reports: new HealthReportService(
    new PostgresReportRepository(database, config.reports.limits),
    config.reports.llm ? createReportNarrator(config.reports.llm) : undefined,
  ),
  foods: new FoodPhotoAnalysisService(
    new PostgresFoodAnalysisQuota(database, config.foods.limits),
    config.foods.llm ? createFoodPhotoAnalyzer(config.foods.llm) : undefined,
  ),
});
pool.on("error", () => app.log.error("An idle database connection failed."));
app.addHook("onClose", async () => {
  await pool.end();
});
let closing = false;
async function shutdown() {
  if (closing) return;
  closing = true;
  const timeout = setTimeout(() => process.exit(1), 10000).unref();
  try {
    await app.close();
  } finally {
    clearTimeout(timeout);
  }
}
process.once("SIGTERM", () => {
  void shutdown();
});
process.once("SIGINT", () => {
  void shutdown();
});
try {
  await app.listen({ host: config.host, port: config.port });
} catch {
  app.log.error("The server could not start.");
  await app.close();
  process.exitCode = 1;
}
