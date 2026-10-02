import { assertDate, todayInBerlin } from "./date.js";

function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function text(value, label, max = 120) {
  if (typeof value !== "string" || !value.trim()) throw badRequest(`${label} fehlt.`);
  return value.trim().slice(0, max);
}

function optionalText(value, max = 600) {
  if (value == null || value === "") return null;
  if (typeof value !== "string") throw badRequest("Die Notiz ist ungültig.");
  return value.trim().slice(0, max) || null;
}

function cents(value, label = "Betrag", allowZero = false) {
  if (!Number.isInteger(value) || (allowZero ? value < 0 : value <= 0)) {
    throw badRequest(`${label} muss als positiver Cent-Betrag vorliegen.`);
  }
  return value;
}

function oneOf(value, options, label) {
  if (!options.includes(value)) throw badRequest(`${label} ist ungültig.`);
  return value;
}

function optionalDate(value, label) {
  if (value == null || value === "") return null;
  try { return assertDate(value, label); } catch (error) { throw badRequest(error.message); }
}

export function accountInput(body = {}) {
  return {
    name: text(body.name, "Kontoname", 80),
    type: oneOf(body.type, ["CHECKING", "SAVINGS", "CASH", "OTHER"], "Kontoart"),
    currentBalanceCents: Number.isInteger(body.currentBalanceCents) ? body.currentBalanceCents : (() => { throw badRequest("Saldo ist ungültig."); })(),
    balanceAsOf: optionalDate(body.balanceAsOf, "Saldo-Stichtag") ?? todayInBerlin(),
    minimumBufferCents: cents(body.minimumBufferCents ?? 0, "Mindest-Puffer", true),
    color: /^#[0-9a-fA-F]{6}$/.test(body.color ?? "") ? body.color : "#197663",
    isPrimary: Boolean(body.isPrimary),
  };
}

export function categoryInput(body = {}) {
  return {
    name: text(body.name, "Kategoriename", 80),
    kind: oneOf(body.kind, ["INCOME", "EXPENSE", "TRANSFER", "BOTH"], "Kategorieart"),
    parentId: body.parentId ? text(body.parentId, "Oberkategorie", 80) : null,
  };
}

export function transactionInput(body = {}) {
  const type = oneOf(body.type, ["INCOME", "EXPENSE", "TRANSFER"], "Buchungsart");
  const status = oneOf(body.status ?? "PLANNED", ["PLANNED", "BOOKED", "CANCELLED"], "Status");
  const accountId = text(body.accountId, "Konto", 80);
  const transferAccountId = type === "TRANSFER" ? text(body.transferAccountId, "Zielkonto", 80) : null;
  if (transferAccountId === accountId) throw badRequest("Quell- und Zielkonto müssen verschieden sein.");
  const actualDate = status === "BOOKED"
    ? optionalDate(body.actualDate, "Buchungsdatum") ?? todayInBerlin()
    : optionalDate(body.actualDate, "Buchungsdatum");
  return {
    title: text(body.title, "Bezeichnung", 120),
    amountCents: cents(body.amountCents),
    type,
    accountId,
    transferAccountId,
    categoryId: body.categoryId ? text(body.categoryId, "Kategorie", 80) : null,
    plannedDate: optionalDate(body.plannedDate, "Planungsdatum") ?? todayInBerlin(),
    actualDate,
    status,
    note: optionalText(body.note),
    source: body.source === "CSV" ? "CSV" : "USER",
    recurrenceId: body.recurrenceId ? text(body.recurrenceId, "Wiederholung", 120) : null,
    isReliable: type === "INCOME" && Boolean(body.isReliable),
    applyToBalance: body.applyToBalance !== false,
  };
}

export function recurrenceInput(body = {}) {
  const transaction = transactionInput({ ...body, status: "PLANNED", actualDate: null });
  const frequency = oneOf(body.frequency ?? "MONTHLY", ["MONTHLY", "WEEKLY", "YEARLY", "CUSTOM"], "Häufigkeit");
  const intervalCount = Number(body.intervalCount ?? 1);
  if (!Number.isInteger(intervalCount) || intervalCount < 1 || intervalCount > 120) throw badRequest("Intervall ist ungültig.");
  const dueDay = body.dueDay == null || body.dueDay === "" ? null : Number(body.dueDay);
  if (dueDay != null && (!Number.isInteger(dueDay) || dueDay < 1 || dueDay > 31)) throw badRequest("Fälligkeitstag ist ungültig.");
  const startDate = optionalDate(body.startDate, "Startdatum") ?? todayInBerlin();
  const endDate = optionalDate(body.endDate, "Enddatum");
  if (endDate && endDate < startDate) throw badRequest("Das Enddatum liegt vor dem Startdatum.");
  return {
    ...transaction,
    frequency,
    intervalCount,
    intervalUnit: oneOf(body.intervalUnit ?? "MONTHS", ["DAYS", "WEEKS", "MONTHS", "YEARS"], "Intervalleinheit"),
    startDate,
    endDate,
    dueDay,
    active: body.active !== false,
  };
}

export function budgetInput(body = {}) {
  if (typeof body.month !== "string" || !/^\d{4}-\d{2}$/.test(body.month)) throw badRequest("Monat ist ungültig.");
  return {
    month: body.month,
    categoryId: text(body.categoryId, "Kategorie", 80),
    plannedCents: cents(body.plannedCents ?? 0, "Budget", true),
  };
}

export { badRequest };
