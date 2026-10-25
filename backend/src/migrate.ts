import { Pool } from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { configuration } from "./config.js";

const pool = new Pool(configuration().database);
try {
  await migrate(drizzle(pool), {
    migrationsFolder: new URL("../drizzle/", import.meta.url).pathname,
  });
  console.log("Committed migrations applied.");
} finally {
  await pool.end();
}
