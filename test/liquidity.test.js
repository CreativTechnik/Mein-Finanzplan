import assert from "node:assert/strict";
import test from "node:test";
import { buildForecast, calculateLiquidity, toMovements } from "../server/liquidity.js";

test("free amount protects payments before the next reliable income and the buffer", () => {
  const account = {
    id: "checking",
    currentBalanceCents: 50_000,
    minimumBufferCents: 10_000,
  };
  const movements = toMovements([
    {
      id: "expense",
      title: "Versicherung",
      amountCents: 20_000,
      type: "EXPENSE",
      accountId: "checking",
      plannedDate: "2026-09-05",
      actualDate: null,
      status: "PLANNED",
      source: "USER",
      isReliable: false,
    },
    {
      id: "salary",
      title: "Gehalt",
      amountCents: 100_000,
      type: "INCOME",
      accountId: "checking",
      plannedDate: "2026-09-10",
      actualDate: null,
      status: "PLANNED",
      source: "USER",
      isReliable: true,
    },
  ]);

  const result = calculateLiquidity(account, movements, "2026-09-01");

  assert.equal(result.horizon, "2026-09-10");
  assert.equal(result.requiredStartingBalanceCents, 30_000);
  assert.equal(result.availableCents, 20_000);
  assert.equal(result.shortfallCents, 0);
});

test("transfers are neutral overall but move money between account forecasts", () => {
  const accounts = [
    { id: "checking", currentBalanceCents: 100_000, minimumBufferCents: 0 },
    { id: "savings", currentBalanceCents: 200_000, minimumBufferCents: 0 },
  ];
  const movements = toMovements([
    {
      id: "transfer",
      title: "Sparrate",
      amountCents: 25_000,
      type: "TRANSFER",
      accountId: "checking",
      transferAccountId: "savings",
      plannedDate: "2026-09-02",
      actualDate: null,
      status: "PLANNED",
      source: "USER",
      isReliable: false,
    },
  ]);

  assert.equal(movements.reduce((sum, item) => sum + item.deltaCents, 0), 0);
  const forecast = buildForecast(accounts, movements, "2026-09-01", 3);
  assert.equal(forecast.plannedByAccount.checking, 75_000);
  assert.equal(forecast.plannedByAccount.savings, 225_000);
});

test("cancelled events never enter liquidity movements", () => {
  const movements = toMovements([
    {
      id: "cancelled",
      title: "Storniert",
      amountCents: 90_000,
      type: "EXPENSE",
      accountId: "checking",
      plannedDate: "2026-09-02",
      status: "CANCELLED",
      source: "USER",
      isReliable: false,
    },
  ]);
  assert.deepEqual(movements, []);
});
