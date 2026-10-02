import assert from "node:assert/strict";
import test from "node:test";
import { buildApp } from "../server/app.js";
import { createDatabase } from "../server/db.js";

test("local API serves a complete dashboard and validates unsafe transfers", async () => {
  const database = createDatabase({ path: ":memory:" });
  const app = await buildApp({ database, serveStatic: false });
  try {
    const health = await app.inject({ method: "GET", url: "/api/health" });
    assert.equal(health.statusCode, 200);
    assert.deepEqual(health.json(), { status: "ok", storage: "sqlite", localOnly: true });

    const bootstrap = await app.inject({ method: "GET", url: "/api/bootstrap?days=30" });
    assert.equal(bootstrap.statusCode, 200);
    const data = bootstrap.json();
    assert.equal(data.days, 30);
    assert.ok(data.accounts.length >= 3);
    assert.ok(data.dashboard.liquidity);
    assert.ok(data.dashboard.forecast.daily.length === 31);

    const invalid = await app.inject({
      method: "POST",
      url: "/api/transactions",
      payload: {
        title: "Ungültig",
        amountCents: 100,
        type: "TRANSFER",
        accountId: "acc-giro",
        transferAccountId: "acc-giro",
        plannedDate: "2026-09-12",
        status: "PLANNED",
      },
    });
    assert.equal(invalid.statusCode, 400);
    assert.match(invalid.json().error, /verschieden/);

    const missing = await app.inject({ method: "DELETE", url: "/api/transactions/not-there" });
    assert.equal(missing.statusCode, 404);
  } finally {
    await app.close();
    database.close();
  }
});
