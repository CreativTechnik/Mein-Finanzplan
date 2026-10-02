const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function assertDate(value, label = "Datum") {
  if (typeof value !== "string" || !DATE_RE.test(value)) {
    throw new Error(`${label} muss im Format JJJJ-MM-TT vorliegen.`);
  }
  const date = new Date(`${value}T12:00:00Z`);
  if (Number.isNaN(date.getTime()) || toDateString(date) !== value) {
    throw new Error(`${label} ist ungültig.`);
  }
  return value;
}

export function toDateString(date) {
  return date.toISOString().slice(0, 10);
}

export function parseDate(value) {
  assertDate(value);
  return new Date(`${value}T12:00:00Z`);
}

export function addDays(value, days) {
  const date = parseDate(value);
  date.setUTCDate(date.getUTCDate() + days);
  return toDateString(date);
}

export function addMonths(value, months, preferredDay) {
  const date = parseDate(value);
  const sourceDay = preferredDay ?? date.getUTCDate();
  const monthIndex = date.getUTCFullYear() * 12 + date.getUTCMonth() + months;
  const year = Math.floor(monthIndex / 12);
  const month = monthIndex % 12;
  const lastDay = new Date(Date.UTC(year, month + 1, 0, 12)).getUTCDate();
  return toDateString(new Date(Date.UTC(year, month, Math.min(sourceDay, lastDay), 12)));
}

export function addYears(value, years, preferredDay) {
  return addMonths(value, years * 12, preferredDay);
}

export function daysBetween(from, to) {
  return Math.round((parseDate(to).getTime() - parseDate(from).getTime()) / 86_400_000);
}

export function endOfWeek(value) {
  const date = parseDate(value);
  const weekday = date.getUTCDay();
  const daysToSunday = weekday === 0 ? 0 : 7 - weekday;
  return addDays(value, daysToSunday);
}

export function monthKey(value) {
  return assertDate(value).slice(0, 7);
}

export function todayInBerlin() {
  if (process.env.FINANZPLAN_TODAY) return assertDate(process.env.FINANZPLAN_TODAY);
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Berlin",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
