import type { ReportMetrics, ReportRequest } from "./contracts.js";

const dayMilliseconds = 86_400_000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class ReportInputError extends Error {
  constructor(public readonly code = "INVALID_REPORT_INPUT") {
    super(
      code === "NO_REPORT_DATA"
        ? "No records are available for this period."
        : "The report records are invalid.",
    );
    this.name = "ReportInputError";
  }
}

function dayDate(day: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new ReportInputError();
  const date = new Date(`${day}T00:00:00.000Z`);
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== day
  )
    throw new ReportInputError();
  return date;
}

function shiftDay(day: string, amount: number): string {
  const date = dayDate(day);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}

function distanceDays(start: string, end: string): number {
  return (dayDate(end).getTime() - dayDate(start).getTime()) / dayMilliseconds;
}

function timestamp(value: string): Date {
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(
      value,
    )
  )
    throw new ReportInputError();
  dayDate(value.slice(0, 10));
  if (
    Number(value.slice(11, 13)) > 23 ||
    Number(value.slice(14, 16)) > 59 ||
    Number(value.slice(17, 19)) > 59
  )
    throw new ReportInputError();
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new ReportInputError();
  return date;
}

function dayFormatter(timeZone: string): Intl.DateTimeFormat {
  if (
    timeZone.length > 80 ||
    !/^[A-Za-z_]+(?:\/[A-Za-z0-9_+.-]+)*$/.test(timeZone)
  )
    throw new ReportInputError();
  try {
    return new Intl.DateTimeFormat("en-US", {
      timeZone,
      calendar: "iso8601",
      numberingSystem: "latn",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  } catch {
    throw new ReportInputError();
  }
}

function localDay(date: Date, formatter: Intl.DateTimeFormat): string {
  const parts = formatter.formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  const day = parts.find((part) => part.type === "day")?.value;
  if (!year || !month || !day) throw new ReportInputError();
  return `${year.padStart(4, "0")}-${month}-${day}`;
}

function bounded(
  value: number,
  minimum: number,
  maximum: number,
  integer = false,
): void {
  if (
    !Number.isFinite(value) ||
    value < minimum ||
    value > maximum ||
    (integer && !Number.isInteger(value))
  )
    throw new ReportInputError();
}

function uniqueIDs(records: { id: string }[]): void {
  const ids = records.map(({ id }) => id.toLowerCase());
  if (ids.some((id) => !uuid.test(id)) || new Set(ids).size !== ids.length)
    throw new ReportInputError();
}

const round = (value: number) => Math.round(value * 10) / 10;
const average = (values: number[]) =>
  values.length
    ? round(values.reduce((sum, value) => sum + value, 0) / values.length)
    : null;

function energyShares(values: number[]): (number | null)[] {
  const total = values.reduce((sum, value) => sum + value, 0);
  if (total === 0) return [null, null, null];
  const exact = values.map((value) => (value / total) * 1_000);
  const tenths = exact.map(Math.floor);
  let remainder = 1_000 - tenths.reduce((sum, value) => sum + value, 0);
  const order = [0, 1, 2].sort(
    (left, right) =>
      (exact[right] ?? 0) -
      (tenths[right] ?? 0) -
      ((exact[left] ?? 0) - (tenths[left] ?? 0)),
  );
  for (const index of order) {
    if (remainder <= 0) break;
    tenths[index] = (tenths[index] ?? 0) + 1;
    remainder -= 1;
  }
  return tenths.map((value) => value / 10);
}

export function aggregateReport(
  request: ReportRequest,
  now = new Date(),
): ReportMetrics {
  if (
    !Number.isFinite(now.getTime()) ||
    !["week", "month"].includes(request.period)
  )
    throw new ReportInputError();
  const formatter = dayFormatter(request.timeZone);
  const today = localDay(now, formatter);
  const anchor = dayDate(request.anchorDate);
  const age = distanceDays(request.anchorDate, today);
  if (age < 0 || age > 366) throw new ReportInputError();
  bounded(request.goals.steps, 2_000, 10_000, true);
  if (request.goals.steps % 1_000 !== 0) throw new ReportInputError();
  const { calorieMinimum, calorieMaximum } = request.goals;
  if ((calorieMinimum === null) !== (calorieMaximum === null))
    throw new ReportInputError();
  if (calorieMinimum !== null && calorieMaximum !== null) {
    bounded(calorieMinimum, 0, 10_000, true);
    bounded(calorieMaximum, 1, 10_000, true);
    if (calorieMinimum > calorieMaximum) throw new ReportInputError();
  }

  const startDate =
    request.period === "week"
      ? shiftDay(request.anchorDate, -((anchor.getUTCDay() + 6) % 7))
      : `${request.anchorDate.slice(0, 7)}-01`;
  const endDate =
    request.period === "week"
      ? shiftDay(startDate, 6)
      : new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + 1, 0))
          .toISOString()
          .slice(0, 10);
  const observedThroughDate = endDate < today ? endDate : today;
  const includesDay = (day: string) =>
    day >= startDate && day <= observedThroughDate;
  const includesTime = (date: Date) =>
    date <= now && includesDay(localDay(date, formatter));

  const data = request.data;
  if (
    data.meals.length > 1_000 ||
    data.workouts.length > 200 ||
    data.wellness.length > 31
  )
    throw new ReportInputError();
  uniqueIDs(data.meals);
  uniqueIDs(data.workouts);
  const foodDays = new Set<string>();
  let mealCount = 0,
    totalKcal = 0,
    trackedMeals = 0,
    carbohydratesG = 0,
    proteinG = 0,
    fatG = 0;
  for (const meal of data.meals) {
    const date = timestamp(meal.recordedAt);
    if (date.getTime() > now.getTime() + 5 * 60_000)
      throw new ReportInputError();
    bounded(meal.calories, 1, 5_000, true);
    if (meal.nutrients) {
      for (const value of Object.values(meal.nutrients))
        bounded(value, 0, 2_000);
    }
    if (!includesTime(date)) continue;
    mealCount += 1;
    totalKcal += meal.calories;
    foodDays.add(localDay(date, formatter));
    if (meal.nutrients) {
      trackedMeals += 1;
      carbohydratesG += meal.nutrients.carbohydratesG;
      proteinG += meal.nutrients.proteinG;
      fatG += meal.nutrients.fatG;
    }
  }

  let sessionCount = 0,
    totalMinutes = 0;
  const repetitions: number[] = [];
  const activities = new Map<
    ReportRequest["data"]["workouts"][number]["activity"],
    { sessions: number; totalMinutes: number }
  >();
  for (const workout of data.workouts) {
    const start = timestamp(workout.startedAt),
      end = timestamp(workout.endedAt);
    if (end < start) throw new ReportInputError();
    if (end.getTime() > now.getTime() + 5 * 60_000)
      throw new ReportInputError();
    bounded(workout.durationMinutes, 1, 1_440, true);
    if (workout.repetitions !== null)
      bounded(workout.repetitions, 0, 100_000, true);
    if (workout.distanceMeters !== null)
      bounded(workout.distanceMeters, 0, 200_000);
    if (workout.calories !== null) bounded(workout.calories, 0, 10_000, true);
    if (!includesTime(end)) continue;
    sessionCount += 1;
    totalMinutes += workout.durationMinutes;
    if (workout.repetitions !== null) repetitions.push(workout.repetitions);
    const activity = activities.get(workout.activity) ?? {
      sessions: 0,
      totalMinutes: 0,
    };
    activity.sessions += 1;
    activity.totalMinutes += workout.durationMinutes;
    activities.set(workout.activity, activity);
  }

  const wellnessDays = new Set<string>();
  const sleep: number[] = [],
    condition: number[] = [];
  let wellnessRecords = 0;
  for (const entry of data.wellness) {
    dayDate(entry.day);
    if (entry.day > today) throw new ReportInputError();
    if (
      wellnessDays.has(entry.day) ||
      (entry.sleepMinutes === null && entry.condition === null)
    )
      throw new ReportInputError();
    wellnessDays.add(entry.day);
    if (entry.sleepMinutes !== null)
      bounded(entry.sleepMinutes, 0, 1_440, true);
    if (entry.condition !== null) bounded(entry.condition, 1, 5, true);
    if (!includesDay(entry.day)) continue;
    wellnessRecords += 1;
    if (entry.sleepMinutes !== null) sleep.push(entry.sleepMinutes);
    if (entry.condition !== null) condition.push(entry.condition);
  }
  if (mealCount + sessionCount + wellnessRecords === 0)
    throw new ReportInputError("NO_REPORT_DATA");
  const shares = energyShares([carbohydratesG * 4, proteinG * 4, fatG * 9]);
  return {
    window: {
      startDate,
      endDate,
      observedThroughDate,
      dayCount: distanceDays(startDate, endDate) + 1,
      elapsedDays: distanceDays(startDate, observedThroughDate) + 1,
      timeZone: request.timeZone,
    },
    food: { loggedDays: foodDays.size, mealCount },
    exercise: {
      sessionCount,
      totalMinutes,
      totalRepetitions: repetitions.length
        ? repetitions.reduce((sum, value) => sum + value, 0)
        : null,
      byActivity: [...activities]
        .map(([activity, values]) => ({ activity, ...values }))
        .sort((left, right) =>
          (left.activity ?? "z").localeCompare(right.activity ?? "z"),
        ),
    },
    nutrition: {
      trackedMeals,
      totalMeals: mealCount,
      carbohydratesG: trackedMeals ? round(carbohydratesG) : null,
      proteinG: trackedMeals ? round(proteinG) : null,
      fatG: trackedMeals ? round(fatG) : null,
      carbohydratePercent: shares[0] ?? null,
      proteinPercent: shares[1] ?? null,
      fatPercent: shares[2] ?? null,
    },
    calories: {
      totalKcal,
      averagePerLoggedDay: foodDays.size
        ? round(totalKcal / foodDays.size)
        : null,
      loggedDays: foodDays.size,
    },
    wellness: {
      sleepLoggedDays: sleep.length,
      averageSleepMinutes: average(sleep),
      conditionLoggedDays: condition.length,
      averageCondition: average(condition),
    },
  };
}
