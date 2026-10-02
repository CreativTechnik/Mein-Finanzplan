import assert from "node:assert/strict";
import test from "node:test";
import { createDatabase } from "../server/db.js";

function account(name, balance) {
  return {
    name,
    type: "CHECKING",
    currentBalanceCents: balance,
    balanceAsOf: "2026-09-01",
    minimumBufferCents: 0,
    color: "#197663",
    isPrimary: name === "Giro",
  };
}

function transaction(overrides = {}) {
  return {
    title: "Testbuchung",
    amountCents: 10_000,
    type: "EXPENSE",
    accountId: "",
    transferAccountId: null,
    categoryId: null,
    plannedDate: "2026-09-02",
    actualDate: "2026-09-02",
    status: "BOOKED",
    note: null,
    source: "USER",
    recurrenceId: null,
    isReliable: false,
    applyToBalance: true,
    ...overrides,
  };
}

test("booked transactions update balances and updates are reversible", () => {
  const database = createDatabase({ path: ":memory:", seed: false });
  try {
    const checking = database.createAccount(account("Giro", 100_000));
    const savings = database.createAccount({ ...account("Sparen", 50_000), type: "SAVINGS", isPrimary: false });

    const expense = database.createTransaction(transaction({ accountId: checking.id }));
    assert.equal(database.getAccount(checking.id).currentBalanceCents, 90_000);
    assert.equal(expense.balanceEffectApplied, true);

    database.updateTransaction(expense.id, transaction({ accountId: checking.id, amountCents: 7_500 }));
    assert.equal(database.getAccount(checking.id).currentBalanceCents, 92_500);

    const transfer = database.createTransaction(transaction({
      title: "Umbuchung",
      amountCents: 20_000,
      type: "TRANSFER",
      accountId: checking.id,
      transferAccountId: savings.id,
    }));
    assert.equal(database.getAccount(checking.id).currentBalanceCents, 72_500);
    assert.equal(database.getAccount(savings.id).currentBalanceCents, 70_000);

    assert.equal(database.deleteTransaction(transfer.id), true);
    assert.equal(database.getAccount(checking.id).currentBalanceCents, 92_500);
    assert.equal(database.getAccount(savings.id).currentBalanceCents, 50_000);
  } finally {
    database.close();
  }
});

test("CSV history can be booked without changing a confirmed account balance", () => {
  const database = createDatabase({ path: ":memory:", seed: false });
  try {
    const checking = database.createAccount(account("Giro", 100_000));
    const imported = database.createTransaction(transaction({
      accountId: checking.id,
      source: "CSV",
      applyToBalance: false,
    }));
    assert.equal(imported.status, "BOOKED");
    assert.equal(imported.balanceEffectApplied, false);
    assert.equal(database.getAccount(checking.id).currentBalanceCents, 100_000);
    database.deleteTransaction(imported.id);
    assert.equal(database.getAccount(checking.id).currentBalanceCents, 100_000);
  } finally {
    database.close();
  }
});
