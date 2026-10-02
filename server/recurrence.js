import { addDays, addMonths, addYears, assertDate } from "./date.js";

function advance(date, rule, anchorDay) {
  const interval = Math.max(1, Number(rule.intervalCount) || 1);
  const unit = rule.frequency === "CUSTOM" ? rule.intervalUnit : rule.frequency;
  if (unit === "DAYS") return addDays(date, interval);
  if (unit === "WEEKLY" || unit === "WEEKS") return addDays(date, interval * 7);
  if (unit === "YEARLY" || unit === "YEARS") return addYears(date, interval, anchorDay);
  return addMonths(date, interval, anchorDay);
}

export function generateOccurrences(rule, fromDate, toDate) {
  assertDate(fromDate, "Start des Vorschauzeitraums");
  assertDate(toDate, "Ende des Vorschauzeitraums");
  if (!rule.active || rule.startDate > toDate || (rule.endDate && rule.endDate < fromDate)) return [];

  const occurrences = [];
  let date = rule.startDate;
  const anchorDay = rule.dueDay ?? Number(rule.startDate.slice(8, 10));
  let guard = 0;
  while (date < fromDate && guard < 10_000) {
    date = advance(date, rule, anchorDay);
    guard += 1;
  }
  while (date <= toDate && guard < 10_000) {
    if (!rule.endDate || date <= rule.endDate) {
      occurrences.push({
        id: `occ:${rule.id}:${date}`,
        recurrenceId: rule.id,
        title: rule.title,
        amountCents: rule.amountCents,
        type: rule.type,
        accountId: rule.accountId,
        transferAccountId: rule.transferAccountId,
        categoryId: rule.categoryId,
        plannedDate: date,
        actualDate: null,
        status: "PLANNED",
        note: rule.note,
        source: "RECURRENCE",
        isReliable: rule.isReliable,
      });
    }
    date = advance(date, rule, anchorDay);
    guard += 1;
  }
  if (guard >= 10_000) throw new Error("Wiederholungsregel erzeugt zu viele Termine.");
  return occurrences;
}

export function materializeOccurrences(rules, fromDate, toDate, transactions = []) {
  const replacements = new Set(
    transactions
      .filter((item) => item.recurrenceId)
      .map((item) => `${item.recurrenceId}:${item.plannedDate}`),
  );
  return rules.flatMap((rule) =>
    generateOccurrences(rule, fromDate, toDate).filter(
      (item) => !replacements.has(`${item.recurrenceId}:${item.plannedDate}`),
    ),
  );
}
