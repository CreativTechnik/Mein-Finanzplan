import { useCallback, useEffect, useMemo, useState } from "react";
import { CheckCircleIcon } from "@phosphor-icons/react/CheckCircle";
import { WifiSlashIcon } from "@phosphor-icons/react/WifiSlash";
import { api } from "./lib/api";
import type { Account, Recurrence, Snapshot, Transaction, ViewId } from "./types";
import { AppShell } from "./components/AppShell";
import { Dashboard } from "./components/Dashboard";
import { AccountsView } from "./components/AccountsView";
import { TransactionsView } from "./components/TransactionsView";
import { PlanningView } from "./components/PlanningView";
import { RecurrencesView } from "./components/RecurrencesView";
import { BudgetsView } from "./components/BudgetsView";
import { StatisticsView } from "./components/StatisticsView";
import { SettingsView } from "./components/SettingsView";
import { Modal } from "./components/Modal";
import { AccountForm, RecurrenceForm, TransactionForm } from "./components/Forms";

type ModalState =
  | { kind: "account"; item?: Account | null }
  | { kind: "transaction"; item?: Transaction | null }
  | { kind: "recurrence"; item?: Recurrence | null }
  | null;

export default function App() {
  const [view, setView] = useState<ViewId>("dashboard");
  const [data, setData] = useState<Snapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modal, setModal] = useState<ModalState>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    try { setError(null); setData(await api.snapshot()); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "Daten konnten nicht geladen werden."); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    if (!notice) return;
    const timeout = window.setTimeout(() => setNotice(null), 3_000);
    return () => window.clearTimeout(timeout);
  }, [notice]);

  const topActions = useMemo(() => <span className="local-status"><CheckCircleIcon size={17} weight="fill" /> Lokal gespeichert</span>, []);

  async function save(resource: "accounts" | "transactions" | "recurrences", item: Account | Transaction | Recurrence | null | undefined, payload: Record<string, unknown>) {
    if (item) await api.update(resource, item.id, payload); else await api.create(resource, payload);
    setModal(null); setNotice("Änderung gespeichert"); await load();
  }

  async function remove(resource: "transactions" | "recurrences", item: Transaction | Recurrence) {
    if (!window.confirm(`„${item.title}“ wirklich löschen?`)) return;
    await api.remove(resource, item.id); setNotice("Eintrag gelöscht"); await load();
  }

  if (loading) return <LoadingScreen />;
  if (error || !data) return <ErrorScreen message={error ?? "Unbekannter Fehler"} onRetry={load} />;

  const content = {
    dashboard: <Dashboard data={data} onEditAccount={(id) => setModal({ kind: "account", item: data.accounts.find((account) => account.id === id) })} onAddTransaction={() => setModal({ kind: "transaction" })} />,
    planning: <PlanningView data={data} />,
    accounts: <AccountsView accounts={data.accounts} onAdd={() => setModal({ kind: "account" })} onEdit={(item) => setModal({ kind: "account", item })} />,
    transactions: <TransactionsView transactions={data.transactions} occurrences={data.occurrences} accounts={data.accounts} onAdd={() => setModal({ kind: "transaction" })} onEdit={(item) => setModal({ kind: "transaction", item })} onDelete={(item) => void remove("transactions", item)} />,
    recurrences: <RecurrencesView items={data.recurrences} onAdd={() => setModal({ kind: "recurrence" })} onEdit={(item) => setModal({ kind: "recurrence", item })} onDelete={(item) => void remove("recurrences", item)} />,
    budgets: <BudgetsView month={data.dashboard.month} budgets={data.budgets} categories={data.categories} onSave={async (payload) => { await api.upsertBudget(payload); setNotice("Budget gespeichert"); await load(); }} />,
    statistics: <StatisticsView data={data} />,
    settings: <SettingsView accounts={data.accounts} categories={data.categories} onImport={async (rows) => { await api.importCsv(rows); setNotice("CSV importiert"); await load(); }} onCreateCategory={async (payload) => { await api.create("categories", payload); setNotice("Kategorie gespeichert"); await load(); }} />,
  }[view];

  return <>
    <AppShell active={view} onNavigate={setView} actions={topActions}>{content}</AppShell>
    {notice && <div className="toast" role="status"><CheckCircleIcon weight="fill" />{notice}</div>}
    {modal?.kind === "transaction" && <Modal title={modal.item ? "Buchung bearbeiten" : "Neue Buchung"} description="Plan und Ist bleiben getrennt nachvollziehbar." onClose={() => setModal(null)}><TransactionForm accounts={data.accounts} categories={data.categories} initial={modal.item} today={data.today} onCancel={() => setModal(null)} onSubmit={(payload) => save("transactions", modal.item, payload)} /></Modal>}
    {modal?.kind === "account" && <Modal title={modal.item ? "Konto bearbeiten" : "Neues Konto"} description="Der bestätigte Saldo ist die Basis der Vorschau." onClose={() => setModal(null)}><AccountForm initial={modal.item} today={data.today} onCancel={() => setModal(null)} onSubmit={(payload) => save("accounts", modal.item, payload)} /></Modal>}
    {modal?.kind === "recurrence" && <Modal title={modal.item ? "Regel bearbeiten" : "Neue Wiederholung"} description="Termine werden bei Bedarf berechnet und nicht im Hintergrund erzeugt." onClose={() => setModal(null)}><RecurrenceForm accounts={data.accounts} categories={data.categories} initial={modal.item} today={data.today} onCancel={() => setModal(null)} onSubmit={(payload) => save("recurrences", modal.item, payload)} /></Modal>}
  </>;
}

function LoadingScreen() {
  return <div className="loading-screen" aria-label="Finanzdaten werden geladen"><aside className="loading-sidebar" /><main><div className="skeleton title" /><div className="skeleton hero" /><div className="skeleton panel" /></main></div>;
}

function ErrorScreen({ message, onRetry }: { message: string; onRetry: () => Promise<void> }) {
  return <main className="fatal-error"><WifiSlashIcon size={42} weight="duotone" /><h1>Lokaler Server nicht erreichbar</h1><p>{message} Starte den Server und versuche es erneut.</p><button className="button primary" onClick={() => void onRetry()}>Erneut versuchen</button></main>;
}
