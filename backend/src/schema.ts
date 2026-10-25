import { sql } from "drizzle-orm";
import {
  check,
  foreignKey,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import type {
  ReportMetrics,
  ReportNarrative,
  ReportPeriod,
  ReportReaction,
  ReportResource,
} from "./reports/contracts.js";

export const reportInstallations = pgTable(
  "report_installations",
  {
    id: uuid("id").primaryKey(),
    tokenHash: text("token_hash").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("report_installations_token_hash_key").on(table.tokenHash),
  ],
);

export const healthReports = pgTable(
  "health_reports",
  {
    id: uuid("id").primaryKey(),
    installationId: uuid("installation_id")
      .notNull()
      .references(() => reportInstallations.id, { onDelete: "cascade" }),
    payloadHash: text("payload_hash").notNull(),
    period: text("period").$type<ReportPeriod>().notNull(),
    anchorDate: text("anchor_date").notNull(),
    timeZone: text("time_zone").notNull(),
    status: text("status").$type<ReportResource["status"]>().notNull(),
    metrics: jsonb("metrics").$type<ReportMetrics>().notNull(),
    model: text("model"),
    evaluation: text("evaluation"),
    reaction: text("reaction").$type<ReportReaction>(),
    recommendations: jsonb("recommendations")
      .$type<ReportNarrative["recommendations"]>()
      .notNull()
      .default(sql`'[]'::jsonb`),
    failureCode: text("failure_code"),
    attempt: integer("attempt").notNull().default(1),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("health_reports_owner_payload_key").on(
      table.installationId,
      table.payloadHash,
    ),
    uniqueIndex("health_reports_owner_id_key").on(
      table.installationId,
      table.id,
    ),
    index("health_reports_owner_created_idx").on(
      table.installationId,
      table.createdAt,
      table.id,
    ),
    check(
      "health_reports_period_check",
      sql`${table.period} in ('week', 'month')`,
    ),
    check(
      "health_reports_status_check",
      sql`${table.status} in ('processing', 'completed', 'failed')`,
    ),
    check("health_reports_attempt_check", sql`${table.attempt} >= 1`),
    check(
      "health_reports_reaction_check",
      sql`${table.reaction} in ('celebrate', 'encourage', 'rest', 'curious')`,
    ),
    check(
      "health_reports_complete_check",
      sql`${table.status} <> 'completed' or (${table.model} is not null and ${table.evaluation} is not null and jsonb_array_length(${table.recommendations}) = 3)`,
    ),
  ],
);

export const reportRequests = pgTable(
  "report_requests",
  {
    installationId: uuid("installation_id").notNull(),
    idempotencyKey: uuid("idempotency_key").notNull(),
    reportId: uuid("report_id").notNull(),
    payloadHash: text("payload_hash").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.installationId, table.idempotencyKey] }),
    foreignKey({
      columns: [table.installationId, table.reportId],
      foreignColumns: [healthReports.installationId, healthReports.id],
    }).onDelete("cascade"),
  ],
);

export const reportRateLimits = pgTable(
  "report_rate_limits",
  {
    key: text("key").notNull(),
    windowStart: timestamp("window_start", { withTimezone: true }).notNull(),
    count: integer("count").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.key, table.windowStart] }),
    index("report_rate_limits_expiry_idx").on(table.expiresAt),
    check("report_rate_limits_count_check", sql`${table.count} > 0`),
  ],
);
