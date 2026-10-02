# atlas: Mein Finanzplan (4675 LOC, 41 files) | budget 2048 | rendered 1567 tok | private symbols + parameter names omitted to fit budget — raise --budget

## src/types.ts (#1 — imported by 13 file(s))
export type AccountType = "CHECKING" | "SAVINGS" | "CASH" | "OTHER"
export type TransactionType = "INCOME" | "EXPENSE" | "TRANSFER"
export type TransactionStatus = "PLANNED" | "BOOKED" | "CANCELLED"
export interface Account
    id: string
    name: string
    type: AccountType
    currentBalanceCents: number
    plannedBalanceCents: number
    balanceAsOf: string
    minimumBufferCents: number
    color: string
    isPrimary: boolean
    needsReview: boolean
export interface Category
    id: string
    name: string
    kind: "INCOME" | "EXPENSE" | "TRANSFER" | "BOTH"
    parentId: string | null
    parentName: string | null
export interface Transaction
    id: string
    title: string
    amountCents: number
    type: TransactionType
    accountId: string
    accountName?: string | null
    transferAccountId: string | null
    transferAccountName?: string | null
    categoryId: string | null
    categoryName?: string | null
    plannedDate: string
    actualDate: string | null
    status: TransactionStatus
    note: string | null
    source: string
    recurrenceId: string | null
    isReliable: boolean
    balanceEffectApplied?: boolean
export interface Recurrence extends Omit<Transaction, "id" | "plannedDate" | "actualDate" | "status" | "recurrenceId">
    id: string
    frequency: "MONTHLY" | "WEEKLY" | "YEARLY" | "CUSTOM"
    intervalCount: number
    intervalUnit: "DAYS" | "WEEKS" | "MONTHS" | "YEARS"
    startDate: string
    endDate: string | null
    dueDay: number | null
    active: boolean
    needsReview: boolean
export interface Budget
    id: string
    month: string
    categoryId: string
    categoryName: string
    parentName: string | null
    plannedCents: number
    actualCents: number
export interface ForecastPoint
    date: string
    balances: Record<string, number>
export interface Snapshot
    today: string
    days: number
    accounts: Account[]
    categories: Category[]
    transactions: Transaction[]
    recurrences: Recurrence[]
    occurrences: Transaction[]
    budgets: Budget[]
    dashboard:
export type ViewId = "dashboard" | "planning" | "accounts" | "transactions" | "recurrences" | "budgets" | "statistics" | "settings"
used by: src/App.tsx, src/components/AccountsView.tsx, src/components/AppShell.tsx, src/components/BalanceChart.tsx, src/components/BudgetsView.tsx, src/components/Dashboard.tsx, src/components/Forms.tsx, src/components/PlanningView.tsx

## src/lib/format.ts (#2 — imported by 10 file(s))
export function formatCurrency(number)
export function formatDate(string)
export function formatShortDate(string)
export function euroToCents(FormDataEntryValue | null)
export function centsToInput(number)
export function accountTypeLabel(string)
export function transactionTypeLabel(string)
export function statusLabel(string)
export function monthLabel(string)
used by: src/components/AccountsView.tsx, src/components/BalanceChart.tsx, src/components/BudgetsView.tsx, src/components/Dashboard.tsx, src/components/Forms.tsx, src/components/PlanningView.tsx, src/components/RecurrencesView.tsx, src/components/SettingsView.tsx

## src/components/SettingsView.tsx (#3 — imported by 1 file(s))
function parseDelimited(string)
function parseDate(string)
function parseAmount(string)
async function chooseFile(ChangeEvent<HTMLInputElement>)
const find = (string[]) => Math.max(0, nextHeaders.findIndex((header) => terms.some((term) => header.toLowerCase().includes(term))))
async function importRows()
async function addCategory(FormEvent<HTMLFormElement>)
imports: src/lib/format.ts, src/types.ts
used by: src/App.tsx

## server/date.js (#4)
export function assertDate(value, label = "Datum")
export function toDateString(date)
export function parseDate(value)
export function addDays(value, days)
export function addMonths(value, months, preferredDay)
export function addYears(value, years, preferredDay)
export function daysBetween(from, to)
export function endOfWeek(value)
export function monthKey(value)
export function todayInBerlin()

## tools/agent-bridge/test/core.test.mjs (#5)
function fixture()
    close()

## tools/agent-bridge/src/core.mjs (#6, 36 symbol(s) — collapsed to fit)

## tools/agent-bridge/bin/agent-bridge.mjs (#7)
function option(args, name, fallback)
function flag(args, name)
function execute(command, args, cwd = process.cwd())
function configurationState(command)
function configureClaudePermissions()
function configureClients(options = {})
function printHelp()
async function main()
const stop = async () =>

---
symbol index (other defined symbols — names only; read the listed file for full signatures):
src/App.tsx: ModalState
native/BankSync/feasibility_check.py: ProbeResult
src/components/Forms.tsx: SubmitHandler
tools/agent-bridge/src/core.mjs: openStore, postMessage
src/App.tsx: save, remove
tools/agent-bridge/src/dashboard.mjs: json, append
server/liquidity.js: toMovements, calculateLiquidity
server/recurrence.js: generateOccurrences, materializeOccurrences
server/db.js: boolean, createDatabase
server/app.js: buildApp
src/components/BalanceChart.tsx: x, y
native/BankSync/feasibility_check.py: required_input, main
src/components/RecurrencesView.tsx: frequencyLabel, RecurrencesView
server/validation.js: badRequest, text
src/components/AccountsView.tsx: AccountsView
src/components/Forms.tsx: submit, submit
src/components/Modal.tsx: Modal
src/components/PlanningView.tsx: PlanningView
src/components/StatisticsView.tsx: StatisticsView
src/components/TransactionsView.tsx: TransactionsView
src/lib/api.ts: request
scripts/xlsx_audit.py: NS, main
server/routes.js: requireEntity, registerRoutes
scripts/dev.mjs: stop
server/index.js: shutdown
server/service.js: buildSnapshot
test/database.test.js: account, transaction
test/recurrence.test.js: rule
tools/agent-bridge/src/server.mjs: textResult, errorResult
tools/agent-bridge/test/mcp.test.mjs: parseToolResult

[34 low-rank file(s) collapsed: ./* (1), native/BankSync/* (1), scripts/* (3), server/* (8), src/* (2), src/components/* (11), src/lib/* (1), test/* (4), tools/agent-bridge/src/* (2), tools/agent-bridge/test/* (1)]
