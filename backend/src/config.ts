export function configuration(env: NodeJS.ProcessEnv = process.env) {
  const required = (name: string) => {
    const value = env[name];
    if (!value?.trim()) throw new Error(`Missing configuration: ${name}`);
    return value;
  };
  const port = (value: string, name: string) => {
    const number = Number(value);
    if (
      !/^\d+$/.test(value) ||
      !Number.isInteger(number) ||
      number < 1 ||
      number > 65535
    ) {
      throw new Error(`Invalid configuration: ${name}`);
    }
    return number;
  };
  const positiveInteger = (name: string, fallback: number, maximum: number) => {
    const value = env[name] ?? String(fallback);
    const number = Number(value);
    if (
      !/^\d+$/.test(value) ||
      !Number.isSafeInteger(number) ||
      number < 1 ||
      number > maximum
    ) {
      throw new Error(`Invalid configuration: ${name}`);
    }
    return number;
  };
  let llm:
    | {
        baseURL: string;
        apiKey: string;
        weeklyModel: string;
        monthlyModel: string;
        foodModel: string;
        timeoutMs: number;
      }
    | undefined;
  if (env.LLM_API_KEY?.trim()) {
    let url: URL;
    try {
      url = new URL(env.LLM_BASE_URL ?? "https://llm.shh.name/v1");
    } catch {
      throw new Error("Invalid configuration: LLM_BASE_URL");
    }
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    ) {
      throw new Error("Invalid configuration: LLM_BASE_URL");
    }
    const weeklyModel = env.LLM_WEEKLY_MODEL ?? "gpt-5.6-luna";
    const monthlyModel = env.LLM_MONTHLY_MODEL ?? "gpt-6.1-sol";
    const foodModel = env.LLM_FOOD_MODEL ?? "gpt-5.6-luna";
    if (
      ![weeklyModel, monthlyModel, foodModel].every((value) =>
        /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}$/.test(value),
      )
    ) {
      throw new Error("Invalid configuration: LLM model");
    }
    llm = {
      baseURL: url.toString().replace(/\/$/, ""),
      apiKey: env.LLM_API_KEY.trim(),
      weeklyModel,
      monthlyModel,
      foodModel,
      timeoutMs: positiveInteger("LLM_TIMEOUT_MS", 45_000, 60_000),
    };
  }
  return {
    host: env.HOST ?? "127.0.0.1",
    port: port(env.PORT ?? "3000", "PORT"),
    reports: {
      llm,
      limits: {
        registrationsPerHour: positiveInteger(
          "REPORT_REGISTRATIONS_PER_IP_HOUR",
          20,
          1_000,
        ),
        reportsPerInstallationDay: positiveInteger(
          "REPORTS_PER_INSTALLATION_DAY",
          12,
          1_000,
        ),
        reportsPerIPDay: positiveInteger("REPORTS_PER_IP_DAY", 30, 10_000),
        reportsPerDay: positiveInteger("REPORTS_GLOBAL_PER_DAY", 100, 100_000),
      },
    },
    foods: {
      llm: llm
        ? {
            baseURL: llm.baseURL,
            apiKey: llm.apiKey,
            model: llm.foodModel,
            timeoutMs: llm.timeoutMs,
          }
        : undefined,
      limits: {
        analysesPerInstallationDay: positiveInteger(
          "FOOD_ANALYSES_PER_INSTALLATION_DAY",
          20,
          1_000,
        ),
        analysesPerIPDay: positiveInteger(
          "FOOD_ANALYSES_PER_IP_DAY",
          50,
          10_000,
        ),
        analysesPerDay: positiveInteger(
          "FOOD_ANALYSES_GLOBAL_PER_DAY",
          200,
          100_000,
        ),
      },
    },
    database: {
      host: required("PGHOST"),
      port: port(env.PGPORT ?? "5432", "PGPORT"),
      database: required("PGDATABASE"),
      user: required("PGUSER"),
      password: required("PGPASSWORD"),
      max: 5,
      connectionTimeoutMillis: 2000,
      statement_timeout: 2000,
      query_timeout: 2000,
      idleTimeoutMillis: 10000,
    },
  };
}
