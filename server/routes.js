import { addDays, todayInBerlin } from "./date.js";
import { buildSnapshot } from "./service.js";
import { accountInput, badRequest, budgetInput, categoryInput, recurrenceInput, transactionInput } from "./validation.js";

function requireEntity(entity, label) {
  if (!entity) {
    const error = new Error(`${label} wurde nicht gefunden.`);
    error.statusCode = 404;
    throw error;
  }
  return entity;
}

export async function registerRoutes(app, database) {
  app.get("/api/health", async () => ({ status: "ok", storage: "sqlite", localOnly: true }));

  app.get("/api/bootstrap", async (request) => {
    const days = Number(request.query?.days ?? 90);
    return buildSnapshot(database, { days });
  });

  app.get("/api/accounts", async () => database.listAccounts());
  app.post("/api/accounts", async (request, reply) => reply.code(201).send(database.createAccount(accountInput(request.body))));
  app.put("/api/accounts/:id", async (request) => requireEntity(database.updateAccount(request.params.id, accountInput(request.body)), "Konto"));

  app.get("/api/categories", async () => database.listCategories());
  app.post("/api/categories", async (request, reply) => reply.code(201).send(database.createCategory(categoryInput(request.body))));

  app.get("/api/transactions", async (request) => database.listTransactions(request.query ?? {}));
  app.post("/api/transactions", async (request, reply) => reply.code(201).send(database.createTransaction(transactionInput(request.body))));
  app.put("/api/transactions/:id", async (request) => requireEntity(database.updateTransaction(request.params.id, transactionInput(request.body)), "Buchung"));
  app.delete("/api/transactions/:id", async (request, reply) => {
    requireEntity(database.deleteTransaction(request.params.id), "Buchung");
    return reply.code(204).send();
  });

  app.get("/api/recurrences", async () => database.listRecurrences());
  app.post("/api/recurrences", async (request, reply) => reply.code(201).send(database.createRecurrence(recurrenceInput(request.body))));
  app.put("/api/recurrences/:id", async (request) => requireEntity(database.updateRecurrence(request.params.id, recurrenceInput(request.body)), "Wiederholung"));
  app.delete("/api/recurrences/:id", async (request, reply) => {
    requireEntity(database.deleteRecurrence(request.params.id), "Wiederholung");
    return reply.code(204).send();
  });

  app.get("/api/budgets", async (request) => {
    const month = request.query?.month ?? todayInBerlin().slice(0, 7);
    if (!/^\d{4}-\d{2}$/.test(month)) throw badRequest("Monat ist ungültig.");
    return database.listBudgets(month);
  });
  app.put("/api/budgets", async (request) => database.upsertBudget(budgetInput(request.body)));

  app.post("/api/import/csv", async (request, reply) => {
    const rows = request.body?.rows;
    if (!Array.isArray(rows) || rows.length === 0 || rows.length > 1_000) throw badRequest("CSV-Vorschau enthält keine gültigen Zeilen.");
    const normalized = rows.map((row) => transactionInput({ ...row, source: "CSV", applyToBalance: false }));
    const created = normalized.map((row) => database.createTransaction(row));
    return reply.code(201).send({ imported: created.length, transactions: created });
  });

  app.get("/api/export", async (_request, reply) => {
    const today = todayInBerlin();
    const data = buildSnapshot(database, { days: 365 });
    reply.header("Content-Disposition", `attachment; filename=finanzplan-${today}.json`);
    reply.type("application/json; charset=utf-8");
    return JSON.stringify({ exportedAt: new Date().toISOString(), rangeEnd: addDays(today, 365), data }, null, 2);
  });
}
