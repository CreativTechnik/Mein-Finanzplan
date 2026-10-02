import { addDays, monthKey, todayInBerlin } from "./date.js";
import { buildAction, buildForecast, calculateLiquidity, toMovements } from "./liquidity.js";
import { materializeOccurrences } from "./recurrence.js";

export function buildSnapshot(database, options = {}) {
  const today = options.today ?? todayInBerlin();
  const days = Math.min(365, Math.max(30, Number(options.days) || 90));
  const fromHistory = addDays(today, -370);
  const toDate = addDays(today, days);
  const accounts = database.listAccounts();
  const categories = database.listCategories();
  const transactions = database.listTransactions({ from: fromHistory, to: toDate });
  const recurrences = database.listRecurrences();
  const occurrences = materializeOccurrences(recurrences, today, toDate, transactions);
  const futureTransactions = transactions.filter(
    (item) => item.status !== "CANCELLED" && (item.actualDate ?? item.plannedDate) >= today,
  );
  const events = [...futureTransactions, ...occurrences].sort((a, b) => a.plannedDate.localeCompare(b.plannedDate));
  const movements = toMovements(events);
  const forecast = buildForecast(accounts, movements, today, days);
  const primaryAccount = accounts.find((account) => account.isPrimary) ?? accounts[0] ?? null;
  const liquidity = primaryAccount ? calculateLiquidity(primaryAccount, movements, today, days) : null;
  const action = primaryAccount && liquidity ? buildAction(liquidity, primaryAccount, accounts, today) : null;
  const upcoming = events
    .filter((event) => event.plannedDate >= today)
    .slice(0, 12)
    .map((event) => ({
      ...event,
      accountName: accounts.find((account) => account.id === event.accountId)?.name ?? "Unbekanntes Konto",
      transferAccountName: accounts.find((account) => account.id === event.transferAccountId)?.name ?? null,
      categoryName: categories.find((category) => category.id === event.categoryId)?.name ?? null,
    }));
  const currentMonth = monthKey(today);
  const budgets = database.listBudgets(currentMonth);
  const bookedThisMonth = transactions.filter(
    (item) => item.status === "BOOKED" && (item.actualDate ?? item.plannedDate).startsWith(currentMonth),
  );
  const incomeCents = bookedThisMonth
    .filter((item) => item.type === "INCOME")
    .reduce((sum, item) => sum + item.amountCents, 0);
  const expenseCents = bookedThisMonth
    .filter((item) => item.type === "EXPENSE")
    .reduce((sum, item) => sum + item.amountCents, 0);

  return {
    today,
    days,
    accounts: accounts.map((account) => ({
      ...account,
      plannedBalanceCents: forecast.plannedByAccount[account.id] ?? account.currentBalanceCents,
    })),
    categories,
    transactions,
    recurrences,
    occurrences,
    budgets,
    dashboard: {
      primaryAccountId: primaryAccount?.id ?? null,
      liquidity,
      action,
      upcoming,
      warnings: forecast.warnings,
      forecast: {
        endDate: forecast.endDate,
        daily: forecast.daily,
        timeline: forecast.timeline.slice(0, 80),
      },
      month: currentMonth,
      actualIncomeCents: incomeCents,
      actualExpenseCents: expenseCents,
    },
  };
}
