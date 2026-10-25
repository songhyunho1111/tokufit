CREATE TABLE "health_reports" (
	"id" uuid PRIMARY KEY NOT NULL,
	"installation_id" uuid NOT NULL,
	"payload_hash" text NOT NULL,
	"period" text NOT NULL,
	"anchor_date" text NOT NULL,
	"time_zone" text NOT NULL,
	"status" text NOT NULL,
	"metrics" jsonb NOT NULL,
	"model" text,
	"evaluation" text,
	"recommendations" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"failure_code" text,
	"attempt" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "health_reports_period_check" CHECK ("health_reports"."period" in ('week', 'month')),
	CONSTRAINT "health_reports_status_check" CHECK ("health_reports"."status" in ('processing', 'completed', 'failed')),
	CONSTRAINT "health_reports_attempt_check" CHECK ("health_reports"."attempt" >= 1),
	CONSTRAINT "health_reports_complete_check" CHECK ("health_reports"."status" <> 'completed' or ("health_reports"."model" is not null and "health_reports"."evaluation" is not null and jsonb_array_length("health_reports"."recommendations") = 3))
);
--> statement-breakpoint
CREATE TABLE "report_installations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"token_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "report_rate_limits" (
	"key" text NOT NULL,
	"window_start" timestamp with time zone NOT NULL,
	"count" integer NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	CONSTRAINT "report_rate_limits_key_window_start_pk" PRIMARY KEY("key","window_start"),
	CONSTRAINT "report_rate_limits_count_check" CHECK ("report_rate_limits"."count" > 0)
);
--> statement-breakpoint
CREATE TABLE "report_requests" (
	"installation_id" uuid NOT NULL,
	"idempotency_key" uuid NOT NULL,
	"report_id" uuid NOT NULL,
	"payload_hash" text NOT NULL,
	CONSTRAINT "report_requests_installation_id_idempotency_key_pk" PRIMARY KEY("installation_id","idempotency_key")
);
--> statement-breakpoint
ALTER TABLE "health_reports" ADD CONSTRAINT "health_reports_installation_id_report_installations_id_fk" FOREIGN KEY ("installation_id") REFERENCES "public"."report_installations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "health_reports_owner_payload_key" ON "health_reports" USING btree ("installation_id","payload_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "health_reports_owner_id_key" ON "health_reports" USING btree ("installation_id","id");--> statement-breakpoint
ALTER TABLE "report_requests" ADD CONSTRAINT "report_requests_installation_id_report_id_health_reports_installation_id_id_fk" FOREIGN KEY ("installation_id","report_id") REFERENCES "public"."health_reports"("installation_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "health_reports_owner_created_idx" ON "health_reports" USING btree ("installation_id","created_at","id");--> statement-breakpoint
CREATE UNIQUE INDEX "report_installations_token_hash_key" ON "report_installations" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "report_rate_limits_expiry_idx" ON "report_rate_limits" USING btree ("expires_at");
