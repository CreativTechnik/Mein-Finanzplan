export type AccountType = "CHECKING" | "SAVINGS" | "CASH" | "OTHER";
export type TransactionType = "INCOME" | "EXPENSE" | "TRANSFER";
export type TransactionStatus = "PLANNED" | "BOOKED" | "CANCELLED";

export interface Account {
  id: string;
  name: string;
  type: AccountType;
  currentBalanceCents: number;
  plannedBalanceCents: number;
  balanceAsOf: string;
  minimumBufferCents: number;
  color: string;
  isPrimary: boolean;
  needsReview: boolean;
}

export interface Category {
  id: string;
  name: string;
  kind: "INCOME" | "EXPENSE" | "TRANSFER" | "BOTH";
  parentId: string | null;
  parentName: string | null;
}

export interface Transaction {
  id: string;
  title: string;
  amountCents: number;
  type: TransactionType;
  accountId: string;
  accountName?: string | null;
  transferAccountId: string | null;
  transferAccountName?: string | null;
  categoryId: string | null;
  categoryName?: string | null;
  plannedDate: string;
  actualDate: string | null;
  status: TransactionStatus;
  note: string | null;
  source: string;
  recurrenceId: string | null;
  isReliable: boolean;
  balanceEffectApplied?: boolean;
}

export interface Recurrence extends Omit<Transaction, "id" | "plannedDate" | "actualDate" | "status" | "recurrenceId"> {
  id: string;
  frequency: "MONTHLY" | "WEEKLY" | "YEARLY" | "CUSTOM";
  intervalCount: number;
  intervalUnit: "DAYS" | "WEEKS" | "MONTHS" | "YEARS";
  startDate: string;
  endDate: string | null;
  dueDay: number | null;
  active: boolean;
  needsReview: boolean;
}

export interface Budget {
  id: string;
  month: string;
  categoryId: string;
  categoryName: string;
  parentName: string | null;
  plannedCents: number;
  actualCents: number;
}

export interface ForecastPoint {
  date: string;
  balances: Record<string, number>;
}

export interface Snapshot {
  today: string;
  days: number;
  accounts: Account[];
  categories: Category[];
  transactions: Transaction[];
  recurrences: Recurrence[];
  occurrences: Transaction[];
  budgets: Budget[];
  dashboard: {
    primaryAccountId: string | null;
    liquidity: null | {
      minimumProjectedCents: number;
      requiredStartingBalanceCents: number;
      availableCents: number;
      shortfallCents: number;
      firstRiskDate: string | null;
      horizon: string;
      nextIncome: null | { date: string; title: string; amountCents: number };
      weekEnd: string;
      weekRequiredStartingBalanceCents: number;
      weekShortfallCents: number;
    };
    action: null | {
      tone: "positive" | "warning" | "danger";
      title: string;
      text: string;
      transferCents?: number;
      sourceAccountId?: string;
      targetAccountId?: string;
      deadline?: string;
    };
    upcoming: Transaction[];
    warnings: Array<{ accountId: string; accountName: string; date: string; balanceCents: number; bufferCents: number }>;
    forecast: {
      endDate: string;
      daily: ForecastPoint[];
      timeline: Array<{
        eventId: string;
        title: string;
        date: string;
        accountId: string;
        deltaCents: number;
        balanceAfterCents: number;
        type: TransactionType;
      }>;
    };
    month: string;
    actualIncomeCents: number;
    actualExpenseCents: number;
  };
}

export type ViewId = "dashboard" | "planning" | "accounts" | "transactions" | "recurrences" | "budgets" | "statistics" | "settings";
