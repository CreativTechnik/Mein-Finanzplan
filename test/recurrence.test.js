import assert from "node:assert/strict";
import test from "node:test";
import { generateOccurrences, materializeOccurrences } from "../server/recurrence.js";

function rule(overrides = {}) {
  return {
    id: "rent",
    title: "Miete",
    amountCents: 80_000,
    type: "EXPENSE",
    accountId: "checking",
    transferAccountId: null,
    categoryId: "housing",
    frequency: "MONTHLY",
    intervalCount: 1,
    intervalUnit: "MONTHS",
    startDate: "2027-01-31",
    endDate: null,
    dueDay: 31,
    isReliable: false,
    active: true,
    note: null,
    ...overrides,
  };
}

test("monthly rules retain their anchor day after a short month", () => {
  const dates = generateOccurrences(rule(), "2027-01-01", "2027-04-30").map((item) => item.plannedDate);
  assert.deepEqual(dates, ["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30"]);
});

test("custom weekly intervals and end dates are respected", () => {
  const dates = generateOccurrences(rule({
    frequency: "CUSTOM",
    intervalCount: 2,
    intervalUnit: "WEEKS",
    startDate: "2026-09-01",
    endDate: "2026-10-01",
    dueDay: null,
  }), "2026-09-01", "2026-12-31").map((item) => item.plannedDate);
  assert.deepEqual(dates, ["2026-09-01", "2026-09-15", "2026-09-29"]);
});

test("materialized transactions replace the matching generated occurrence", () => {
  const transactions = [{ recurrenceId: "rent", plannedDate: "2027-02-28" }];
  const dates = materializeOccurrences([rule()], "2027-01-01", "2027-03-31", transactions)
    .map((item) => item.plannedDate);
  assert.deepEqual(dates, ["2027-01-31", "2027-03-31"]);
});
