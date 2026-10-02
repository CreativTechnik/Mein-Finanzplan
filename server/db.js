import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { todayInBerlin } from "./date.js";

function boolean(value) {
  return Boolean(Number(value));
}

function accountFromRow(row) {
  return {
    id: row.id,
    name: row.name,
    type: row.type,
    currentBalanceCents: Number(row.current_balance_cents),
    balanceAsOf: row.balance_as_of,
    minimumBufferCents: Number(row.minimum_buffer_cents),
    color: row.color,
    isPrimary: boolean(row.is_primary),
    needsReview: boolean(row.needs_review),
  };
}

function categoryFromRow(row) {
  return {
    id: row.id,
    name: row.name,
    kind: row.kind,
    parentId: row.parent_id,
    parentName: row.parent_name ?? null,
  };
}

function transactionFromRow(row) {
  return {
    id: row.id,
    title: row.title,
    amountCents: Number(row.amount_cents),
    type: row.type,
    accountId: row.account_id,
    accountName: row.account_name ?? null,
    transferAccountId: row.transfer_account_id,
    transferAccountName: row.transfer_account_name ?? null,
    categoryId: row.category_id,
    categoryName: row.category_name ?? null,
    plannedDate: row.planned_date,
    actualDate: row.actual_date,
    status: row.status,
    note: row.note,
    source: row.source,
    recurrenceId: row.recurrence_id,
    isReliable: boolean(row.is_reliable),
    balanceEffectApplied: boolean(row.balance_effect_applied),
  };
}

function recurrenceFromRow(row) {
  return {
    id: row.id,
    title: row.title,
    amountCents: Number(row.amount_cents),
    type: row.type,
    accountId: row.account_id,
    accountName: row.account_name ?? null,
    transferAccountId: row.transfer_account_id,
    transferAccountName: row.transfer_account_name ?? null,
    categoryId: row.category_id,
    categoryName: row.category_name ?? null,
    frequency: row.frequency,
    intervalCount: Number(row.interval_count),
    intervalUnit: row.interval_unit,
    startDate: row.start_date,
    endDate: row.end_date,
    dueDay: row.due_day == null ? null : Number(row.due_day),
    isReliable: boolean(row.is_reliable),
    active: boolean(row.active),
    needsReview: boolean(row.needs_review),
    note: row.note,
    source: row.source,
  };
}

function transactionDelta(item) {
  if (item.status !== "BOOKED") return [];
  if (item.type === "INCOME") return [[item.accountId, item.amountCents]];
  if (item.type === "EXPENSE") return [[item.accountId, -item.amountCents]];
  return [
    [item.accountId, -item.amountCents],
    [item.transferAccountId, item.amountCents],
  ];
}

export function createDatabase(options = {}) {
  const databasePath = options.path ?? process.env.FINANZPLAN_DB_PATH ?? resolve("data/finanzplan.sqlite");
  if (databasePath !== ":memory:") mkdirSync(dirname(databasePath), { recursive: true });
  const db = new DatabaseSync(databasePath, { timeout: 5_000 });
  db.exec("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA temp_store = MEMORY;");

  db.exec(`
    CREATE TABLE IF NOT EXISTS accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL CHECK (type IN ('CHECKING','SAVINGS','CASH','OTHER')),
      current_balance_cents INTEGER NOT NULL DEFAULT 0,
      balance_as_of TEXT NOT NULL,
      minimum_buffer_cents INTEGER NOT NULL DEFAULT 0 CHECK (minimum_buffer_cents >= 0),
      color TEXT NOT NULL DEFAULT '#197663',
      is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0,1)),
      needs_review INTEGER NOT NULL DEFAULT 0 CHECK (needs_review IN (0,1)),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) STRICT;

    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('INCOME','EXPENSE','TRANSFER','BOTH')),
      parent_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(name, parent_id)
    ) STRICT;

    CREATE TABLE IF NOT EXISTS recurrences (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      type TEXT NOT NULL CHECK (type IN ('INCOME','EXPENSE','TRANSFER')),
      account_id TEXT NOT NULL REFERENCES accounts(id),
      transfer_account_id TEXT REFERENCES accounts(id),
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      frequency TEXT NOT NULL CHECK (frequency IN ('MONTHLY','WEEKLY','YEARLY','CUSTOM')),
      interval_count INTEGER NOT NULL DEFAULT 1 CHECK (interval_count > 0),
      interval_unit TEXT NOT NULL DEFAULT 'MONTHS' CHECK (interval_unit IN ('DAYS','WEEKS','MONTHS','YEARS')),
      start_date TEXT NOT NULL,
      end_date TEXT,
      due_day INTEGER CHECK (due_day BETWEEN 1 AND 31),
      is_reliable INTEGER NOT NULL DEFAULT 0 CHECK (is_reliable IN (0,1)),
      active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
      needs_review INTEGER NOT NULL DEFAULT 0 CHECK (needs_review IN (0,1)),
      note TEXT,
      source TEXT NOT NULL DEFAULT 'USER',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) STRICT;
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      type TEXT NOT NULL CHECK (type IN ('INCOME','EXPENSE','TRANSFER')),
      account_id TEXT NOT NULL REFERENCES accounts(id),
      transfer_account_id TEXT REFERENCES accounts(id),
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      planned_date TEXT NOT NULL,
      actual_date TEXT,
      status TEXT NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED','BOOKED','CANCELLED')),
      note TEXT,
      source TEXT NOT NULL DEFAULT 'USER',
      recurrence_id TEXT REFERENCES recurrences(id) ON DELETE SET NULL,
      is_reliable INTEGER NOT NULL DEFAULT 0 CHECK (is_reliable IN (0,1)),
      balance_effect_applied INTEGER NOT NULL DEFAULT 0 CHECK (balance_effect_applied IN (0,1)),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (type != 'TRANSFER' OR (transfer_account_id IS NOT NULL AND transfer_account_id != account_id))
    ) STRICT;

    CREATE TABLE IF NOT EXISTS budgets (
      id TEXT PRIMARY KEY,
      month TEXT NOT NULL,
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      planned_cents INTEGER NOT NULL CHECK (planned_cents >= 0),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(month, category_id)
    ) STRICT;

    CREATE INDEX IF NOT EXISTS idx_transactions_planned_date ON transactions(planned_date);
    CREATE INDEX IF NOT EXISTS idx_transactions_actual_date ON transactions(actual_date);
    CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id);
    CREATE INDEX IF NOT EXISTS idx_recurrences_active ON recurrences(active, start_date);
    CREATE INDEX IF NOT EXISTS idx_budgets_month ON budgets(month);
  `);

  const transactionColumns = db.prepare("PRAGMA table_info(transactions)").all();
  if (!transactionColumns.some((column) => column.name === "balance_effect_applied")) {
    db.exec("ALTER TABLE transactions ADD COLUMN balance_effect_applied INTEGER NOT NULL DEFAULT 0 CHECK (balance_effect_applied IN (0,1))");
  }

  function inTransaction(callback) {
    db.exec("BEGIN IMMEDIATE");
    try {
      const result = callback();
      db.exec("COMMIT");
      return result;
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  }

  function applyBookedEffect(item, direction = 1) {
    const effectDate = item.actualDate ?? todayInBerlin();
    for (const [accountId, delta] of transactionDelta(item)) {
      if (direction > 0) {
        db.prepare("UPDATE accounts SET current_balance_cents = current_balance_cents + ?, balance_as_of = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
          .run(delta, effectDate, accountId);
      } else {
        db.prepare("UPDATE accounts SET current_balance_cents = current_balance_cents + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
          .run(-delta, accountId);
      }
    }
  }

  function seed() {
    const count = Number(db.prepare("SELECT COUNT(*) AS count FROM accounts").get().count);
    if (count > 0) return;
    const today = todayInBerlin();
    inTransaction(() => {
      const insertAccount = db.prepare(`
        INSERT INTO accounts (id, name, type, current_balance_cents, balance_as_of, minimum_buffer_cents, color, is_primary, needs_review)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      insertAccount.run("acc-giro", "Girokonto", "CHECKING", 0, today, 10000, "#197663", 1, 1);
      insertAccount.run("acc-sparen", "Tagesgeld", "SAVINGS", 290000, today, 50000, "#3974a8", 0, 1);
      insertAccount.run("acc-cash", "Bargeld", "CASH", 0, today, 0, "#9a6c35", 0, 1);

      const categories = [
        ["cat-income", "Einkommen", "INCOME", null],
        ["cat-salary", "Gehalt Netto", "INCOME", "cat-income"],
        ["cat-pension", "Waisenrente Netto", "INCOME", "cat-income"],
        ["cat-child", "Kindergeld Netto", "INCOME", "cat-income"],
        ["cat-income-other", "Sonstige Einnahmen", "INCOME", "cat-income"],
        ["cat-housing", "Wohnen", "EXPENSE", null],
        ["cat-rent", "Miete", "EXPENSE", "cat-housing"],
        ["cat-electricity", "Strom", "EXPENSE", "cat-housing"],
        ["cat-streaming", "TV/Streaming", "EXPENSE", "cat-housing"],
        ["cat-phone", "Telefon", "EXPENSE", "cat-housing"],
        ["cat-mobility", "Mobilität", "EXPENSE", null],
        ["cat-car-insurance", "KFZ-Haftpflicht", "EXPENSE", "cat-mobility"],
        ["cat-tickets", "Fahrkarten", "EXPENSE", "cat-mobility"],
        ["cat-repairs", "Reparaturen", "EXPENSE", "cat-mobility"],
        ["cat-insurance", "Versicherungen", "EXPENSE", null],
        ["cat-liability", "Privathaftpflicht", "EXPENSE", "cat-insurance"],
        ["cat-household-insurance", "Hausrat", "EXPENSE", "cat-insurance"],
        ["cat-legal", "Rechtsschutz", "EXPENSE", "cat-insurance"],
        ["cat-disability", "BU", "EXPENSE", "cat-insurance"],
        ["cat-living", "Lebenshaltung", "EXPENSE", null],
        ["cat-food", "Lebensmittel", "EXPENSE", "cat-living"],
        ["cat-clothing", "Kleidung", "EXPENSE", "cat-living"],
        ["cat-leisure", "Freizeit", "EXPENSE", null],
        ["cat-orders", "Bestellungen", "EXPENSE", "cat-leisure"],
        ["cat-subscriptions", "Abos", "EXPENSE", "cat-leisure"],
        ["cat-broadcast", "Rundfunkbeitrag", "EXPENSE", "cat-leisure"],
        ["cat-leisure-other", "Sonstiges", "EXPENSE", "cat-leisure"],
        ["cat-savings", "Sparen", "TRANSFER", null],
      ];
      const insertCategory = db.prepare("INSERT INTO categories (id, name, kind, parent_id) VALUES (?, ?, ?, ?)");
      for (const item of categories) insertCategory.run(...item);

      const insertRecurrence = db.prepare(`
        INSERT INTO recurrences
          (id, title, amount_cents, type, account_id, transfer_account_id, category_id, frequency, interval_count, interval_unit, start_date, end_date, due_day, is_reliable, active, needs_review, note, source, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 'EXCEL', CURRENT_TIMESTAMP)
      `);
      const rules = [
        ["rec-salary", "Gehalt", 108151, "INCOME", "acc-giro", null, "cat-salary", "MONTHLY", 1, "MONTHS", "2026-09-25", "2027-08-25", 25, 1, 1, "Fälligkeitstag angenommen"],
        ["rec-salary-2027", "Gehalt", 110825, "INCOME", "acc-giro", null, "cat-salary", "MONTHLY", 1, "MONTHS", "2027-09-25", "2028-08-25", 25, 1, 1, "Fälligkeitstag angenommen"],
        ["rec-salary-2028", "Gehalt", 113274, "INCOME", "acc-giro", null, "cat-salary", "MONTHLY", 1, "MONTHS", "2028-09-25", "2029-08-25", 25, 1, 1, "Fälligkeitstag angenommen"],
        ["rec-salary-2029", "Gehalt", 117504, "INCOME", "acc-giro", null, "cat-salary", "MONTHLY", 1, "MONTHS", "2029-09-25", null, 25, 1, 1, "Fälligkeitstag angenommen"],
        ["rec-pension", "Waisenrente", 36600, "INCOME", "acc-giro", null, "cat-pension", "MONTHLY", 1, "MONTHS", "2026-10-01", null, 1, 1, 1, "Fälligkeitstag angenommen"],
        ["rec-child", "Kindergeld", 25900, "INCOME", "acc-giro", null, "cat-child", "MONTHLY", 1, "MONTHS", "2026-10-08", null, 8, 1, 1, "Fälligkeitstag angenommen"],
        ["rec-rent-high", "Miete", 82000, "EXPENSE", "acc-giro", null, "cat-rent", "MONTHLY", 1, "MONTHS", "2026-11-03", "2027-02-03", 3, 0, 1, "Fälligkeitstag angenommen"],
        ["rec-rent", "Miete", 57000, "EXPENSE", "acc-giro", null, "cat-rent", "MONTHLY", 1, "MONTHS", "2027-03-03", null, 3, 0, 1, "Fälligkeitstag angenommen"],
        ["rec-insurance", "Versicherungen", 4800, "EXPENSE", "acc-giro", null, "cat-insurance", "MONTHLY", 1, "MONTHS", "2026-09-15", null, 15, 0, 1, "Vier Excel-Positionen zusammengefasst"],
        ["rec-phone", "Telefon", 1000, "EXPENSE", "acc-giro", null, "cat-phone", "MONTHLY", 1, "MONTHS", "2026-10-12", null, 12, 0, 1, "Fälligkeitstag angenommen"],
        ["rec-tickets", "Fahrkarten", 11000, "EXPENSE", "acc-giro", null, "cat-tickets", "MONTHLY", 1, "MONTHS", "2026-10-01", null, 1, 0, 1, "Fälligkeitstag angenommen"],
        ["rec-subscriptions", "Abos", 2000, "EXPENSE", "acc-giro", null, "cat-subscriptions", "MONTHLY", 1, "MONTHS", "2026-09-10", null, 10, 0, 1, "Fälligkeitstag angenommen"],
        ["rec-broadcast-quarterly", "Rundfunkbeitrag", 5508, "EXPENSE", "acc-giro", null, "cat-broadcast", "CUSTOM", 3, "MONTHS", "2026-10-15", "2027-10-15", 15, 0, 0, "Intervall aus Excel abgeleitet"],
        ["rec-broadcast-monthly", "Rundfunkbeitrag", 1800, "EXPENSE", "acc-giro", null, "cat-broadcast", "MONTHLY", 1, "MONTHS", "2028-01-15", null, 15, 0, 0, "Monatswert aus Excel"],
      ];
      for (const rule of rules) insertRecurrence.run(...rule);

      const insertTransaction = db.prepare(`
        INSERT INTO transactions
          (id, title, amount_cents, type, account_id, transfer_account_id, category_id, planned_date, status, note, source, is_reliable)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PLANNED', ?, 'EXCEL', ?)
      `);
      insertTransaction.run("tx-savings-oct", "Sparrate Oktober", 100000, "TRANSFER", "acc-giro", "acc-sparen", "cat-savings", "2026-10-02", "Aus Excel übernommen", 0);
      insertTransaction.run("tx-savings-nov", "Sparrate November", 30000, "TRANSFER", "acc-giro", "acc-sparen", "cat-savings", "2026-11-02", "Aus Excel übernommen", 0);
      insertTransaction.run("tx-savings-dec", "Sparrate Dezember", 35000, "TRANSFER", "acc-giro", "acc-sparen", "cat-savings", "2026-12-02", "Aus Excel übernommen", 0);
      insertTransaction.run("tx-other-income-dec", "Sonstige Einnahme", 20000, "INCOME", "acc-giro", null, "cat-income-other", "2026-12-15", "Aus Excel übernommen", 0);

      const insertBudget = db.prepare("INSERT INTO budgets (id, month, category_id, planned_cents) VALUES (?, ?, ?, ?)");
      const budgets = [
        ["budget-2026-09-food", "2026-09", "cat-food", 25000],
        ["budget-2026-09-tickets", "2026-09", "cat-tickets", 11000],
        ["budget-2026-09-leisure", "2026-09", "cat-leisure", 2000],
        ["budget-2026-09-other", "2026-09", "cat-leisure-other", 25000],
        ["budget-2026-09-orders", "2026-09", "cat-orders", 1000],
      ];
      for (const budget of budgets) insertBudget.run(...budget);
    });
  }

  if (options.seed !== false) seed();

  const api = {
    path: databasePath,
    close: () => db.close(),
    raw: db,
    listAccounts() {
      return db.prepare("SELECT * FROM accounts ORDER BY is_primary DESC, name").all().map(accountFromRow);
    },
    createAccount(input) {
      const id = randomUUID();
      inTransaction(() => {
        if (input.isPrimary) db.exec("UPDATE accounts SET is_primary = 0");
        db.prepare(`
          INSERT INTO accounts (id, name, type, current_balance_cents, balance_as_of, minimum_buffer_cents, color, is_primary, needs_review)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
        `).run(id, input.name, input.type, input.currentBalanceCents, input.balanceAsOf, input.minimumBufferCents, input.color, input.isPrimary ? 1 : 0);
      });
      return this.getAccount(id);
    },
    getAccount(id) {
      const row = db.prepare("SELECT * FROM accounts WHERE id = ?").get(id);
      return row ? accountFromRow(row) : null;
    },
    updateAccount(id, input) {
      inTransaction(() => {
        if (input.isPrimary) db.prepare("UPDATE accounts SET is_primary = 0 WHERE id != ?").run(id);
        db.prepare(`
          UPDATE accounts SET name = ?, type = ?, current_balance_cents = ?, balance_as_of = ?, minimum_buffer_cents = ?,
            color = ?, is_primary = ?, needs_review = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?
        `).run(input.name, input.type, input.currentBalanceCents, input.balanceAsOf, input.minimumBufferCents, input.color, input.isPrimary ? 1 : 0, id);
      });
      return this.getAccount(id);
    },
    listCategories() {
      return db.prepare(`
        SELECT c.*, p.name AS parent_name FROM categories c LEFT JOIN categories p ON p.id = c.parent_id
        ORDER BY COALESCE(p.name, c.name), c.parent_id IS NOT NULL, c.name
      `).all().map(categoryFromRow);
    },
    createCategory(input) {
      const id = randomUUID();
      db.prepare("INSERT INTO categories (id, name, kind, parent_id) VALUES (?, ?, ?, ?)").run(id, input.name, input.kind, input.parentId ?? null);
      return this.listCategories().find((item) => item.id === id);
    },
    listTransactions(filters = {}) {
      const clauses = [];
      const values = [];
      if (filters.from) { clauses.push("t.planned_date >= ?"); values.push(filters.from); }
      if (filters.to) { clauses.push("t.planned_date <= ?"); values.push(filters.to); }
      if (filters.accountId) { clauses.push("(t.account_id = ? OR t.transfer_account_id = ?)"); values.push(filters.accountId, filters.accountId); }
      if (filters.status) { clauses.push("t.status = ?"); values.push(filters.status); }
      if (filters.type) { clauses.push("t.type = ?"); values.push(filters.type); }
      const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
      return db.prepare(`
        SELECT t.*, a.name AS account_name, ta.name AS transfer_account_name, c.name AS category_name
        FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        LEFT JOIN accounts ta ON ta.id = t.transfer_account_id
        LEFT JOIN categories c ON c.id = t.category_id
        ${where}
        ORDER BY t.planned_date, t.created_at
      `).all(...values).map(transactionFromRow);
    },
    getTransaction(id) {
      return this.listTransactions().find((item) => item.id === id) ?? null;
    },
    createTransaction(input) {
      const id = randomUUID();
      const item = { ...input, id };
      inTransaction(() => {
        db.prepare(`
          INSERT INTO transactions
            (id, title, amount_cents, type, account_id, transfer_account_id, category_id, planned_date, actual_date, status, note, source, recurrence_id, is_reliable, balance_effect_applied)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(id, input.title, input.amountCents, input.type, input.accountId, input.transferAccountId ?? null, input.categoryId ?? null,
          input.plannedDate, input.actualDate ?? null, input.status, input.note ?? null, input.source ?? "USER", input.recurrenceId ?? null, input.isReliable ? 1 : 0,
          input.status === "BOOKED" && input.applyToBalance !== false ? 1 : 0);
        if (input.status === "BOOKED" && input.applyToBalance !== false) applyBookedEffect(item);
      });
      return this.getTransaction(id);
    },
    updateTransaction(id, input) {
      const previous = this.getTransaction(id);
      if (!previous) return null;
      inTransaction(() => {
        if (previous.balanceEffectApplied) applyBookedEffect(previous, -1);
        const applyToBalance = input.status === "BOOKED" && (input.applyToBalance ?? previous.balanceEffectApplied ?? true);
        db.prepare(`
          UPDATE transactions SET title = ?, amount_cents = ?, type = ?, account_id = ?, transfer_account_id = ?, category_id = ?,
            planned_date = ?, actual_date = ?, status = ?, note = ?, is_reliable = ?, balance_effect_applied = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
        `).run(input.title, input.amountCents, input.type, input.accountId, input.transferAccountId ?? null, input.categoryId ?? null,
          input.plannedDate, input.actualDate ?? null, input.status, input.note ?? null, input.isReliable ? 1 : 0, applyToBalance ? 1 : 0, id);
        if (applyToBalance) applyBookedEffect({ ...input, id });
      });
      return this.getTransaction(id);
    },
    deleteTransaction(id) {
      const previous = this.getTransaction(id);
      if (!previous) return false;
      inTransaction(() => {
        if (previous.balanceEffectApplied) applyBookedEffect(previous, -1);
        db.prepare("DELETE FROM transactions WHERE id = ?").run(id);
      });
      return true;
    },
    listRecurrences() {
      return db.prepare(`
        SELECT r.*, a.name AS account_name, ta.name AS transfer_account_name, c.name AS category_name
        FROM recurrences r
        JOIN accounts a ON a.id = r.account_id
        LEFT JOIN accounts ta ON ta.id = r.transfer_account_id
        LEFT JOIN categories c ON c.id = r.category_id
        ORDER BY r.active DESC, r.start_date, r.title
      `).all().map(recurrenceFromRow);
    },
    getRecurrence(id) {
      return this.listRecurrences().find((item) => item.id === id) ?? null;
    },
    createRecurrence(input) {
      const id = randomUUID();
      db.prepare(`
        INSERT INTO recurrences
          (id, title, amount_cents, type, account_id, transfer_account_id, category_id, frequency, interval_count, interval_unit,
           start_date, end_date, due_day, is_reliable, active, needs_review, note, source, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 'USER', CURRENT_TIMESTAMP)
      `).run(id, input.title, input.amountCents, input.type, input.accountId, input.transferAccountId ?? null, input.categoryId ?? null,
        input.frequency, input.intervalCount, input.intervalUnit, input.startDate, input.endDate ?? null, input.dueDay ?? null,
        input.isReliable ? 1 : 0, input.active ? 1 : 0, input.note ?? null);
      return this.getRecurrence(id);
    },
    updateRecurrence(id, input) {
      db.prepare(`
        UPDATE recurrences SET title = ?, amount_cents = ?, type = ?, account_id = ?, transfer_account_id = ?, category_id = ?,
          frequency = ?, interval_count = ?, interval_unit = ?, start_date = ?, end_date = ?, due_day = ?, is_reliable = ?, active = ?,
          needs_review = 0, note = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
      `).run(input.title, input.amountCents, input.type, input.accountId, input.transferAccountId ?? null, input.categoryId ?? null,
        input.frequency, input.intervalCount, input.intervalUnit, input.startDate, input.endDate ?? null, input.dueDay ?? null,
        input.isReliable ? 1 : 0, input.active ? 1 : 0, input.note ?? null, id);
      return this.getRecurrence(id);
    },
    deleteRecurrence(id) {
      return db.prepare("DELETE FROM recurrences WHERE id = ?").run(id).changes > 0;
    },
    listBudgets(month) {
      const rows = db.prepare(`
        SELECT b.*, c.name AS category_name, p.name AS parent_name,
          COALESCE(SUM(CASE WHEN t.type = 'EXPENSE' AND t.status = 'BOOKED' THEN t.amount_cents ELSE 0 END), 0) AS actual_cents
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        LEFT JOIN categories p ON p.id = c.parent_id
        LEFT JOIN transactions t ON t.category_id = b.category_id AND substr(COALESCE(t.actual_date, t.planned_date), 1, 7) = b.month
        WHERE b.month = ?
        GROUP BY b.id
        ORDER BY COALESCE(p.name, c.name), c.name
      `).all(month);
      return rows.map((row) => ({
        id: row.id,
        month: row.month,
        categoryId: row.category_id,
        categoryName: row.category_name,
        parentName: row.parent_name,
        plannedCents: Number(row.planned_cents),
        actualCents: Number(row.actual_cents),
      }));
    },
    upsertBudget(input) {
      db.prepare(`
        INSERT INTO budgets (id, month, category_id, planned_cents) VALUES (?, ?, ?, ?)
        ON CONFLICT(month, category_id) DO UPDATE SET planned_cents = excluded.planned_cents, updated_at = CURRENT_TIMESTAMP
      `).run(randomUUID(), input.month, input.categoryId, input.plannedCents);
      return this.listBudgets(input.month).find((item) => item.categoryId === input.categoryId);
    },
    inTransaction,
  };
  return api;
}
