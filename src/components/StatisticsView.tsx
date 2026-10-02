import { ChartLineUpIcon } from "@phosphor-icons/react/ChartLineUp";
import type { Snapshot } from "../types";
import { formatCurrency, monthLabel } from "../lib/format";

export function StatisticsView({ data }: { data: Snapshot }) {
  const booked = data.transactions.filter((item) => item.status === "BOOKED");
  const byCategory = new Map<string, number>();
  for (const item of booked.filter((entry) => entry.type === "EXPENSE")) byCategory.set(item.categoryName ?? "Ohne Kategorie", (byCategory.get(item.categoryName ?? "Ohne Kategorie") ?? 0) + item.amountCents);
  const categories = [...byCategory.entries()].sort((a, b) => b[1] - a[1]); const max = Math.max(1, ...categories.map((item) => item[1]));
  const totalAssets = data.accounts.reduce((sum, account) => sum + account.currentBalanceCents, 0);
  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Statistik</p><h1>Entwicklung verstehen</h1><p>Die Statistik nutzt ausschließlich tatsächlich gebuchte Werte.</p></div></header>
    <section className="summary-band split"><div><span>Einnahmen {monthLabel(data.dashboard.month)}</span><strong>{formatCurrency(data.dashboard.actualIncomeCents)}</strong></div><div><span>Ausgaben {monthLabel(data.dashboard.month)}</span><strong>{formatCurrency(data.dashboard.actualExpenseCents)}</strong></div><div><span>Aktuelles Gesamtvermögen</span><strong>{formatCurrency(totalAssets)}</strong></div></section>
    <section className="content-panel"><div className="section-heading"><div><h2>Ausgaben nach Kategorie</h2><p>Alle gebuchten Ausgaben im vorhandenen Verlauf.</p></div></div>
      {categories.length ? <div className="category-bars">{categories.map(([name, amount]) => <div key={name}><span>{name}</span><i><b style={{ width: `${(amount / max) * 100}%` }} /></i><strong>{formatCurrency(amount)}</strong></div>)}</div> : <div className="empty-state compact"><ChartLineUpIcon size={32} /><h2>Noch keine Ist-Werte</h2><p>Markiere Buchungen als gebucht, damit hier echte Ausgaben sichtbar werden.</p></div>}
    </section>
  </div>;
}
