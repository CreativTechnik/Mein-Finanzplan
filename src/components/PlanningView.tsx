import { ArrowDownRightIcon } from "@phosphor-icons/react/ArrowDownRight";
import { ArrowUpRightIcon } from "@phosphor-icons/react/ArrowUpRight";
import { CalendarBlankIcon } from "@phosphor-icons/react/CalendarBlank";
import type { Snapshot } from "../types";
import { formatCurrency, formatDate } from "../lib/format";
import { BalanceChart } from "./BalanceChart";

export function PlanningView({ data }: { data: Snapshot }) {
  const timeline = data.dashboard.forecast.timeline;
  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Planung</p><h1>Was wann auf dem Konto passiert</h1><p>Die Vorschau verarbeitet Ausgaben vor Einnahmen am selben Tag, damit mögliche Engpässe sichtbar bleiben.</p></div></header>
    <section className="content-panel chart-panel"><div className="section-heading"><div><h2>90-Tage-Verlauf</h2><p>Ist-Salden plus alle geplanten Bewegungen.</p></div></div><BalanceChart accounts={data.accounts} points={data.dashboard.forecast.daily} /></section>
    <section className="content-panel">
      <div className="section-heading"><div><h2>Zeitachse</h2><p>Saldo direkt nach jeder geplanten Kontobewegung.</p></div></div>
      <div className="timeline-list">{timeline.map((item, index) => {
        const account = data.accounts.find((entry) => entry.id === item.accountId);
        return <div className="timeline-entry" key={`${item.eventId}-${item.accountId}-${index}`}>
          <time>{formatDate(item.date)}</time><span className={`timeline-dot ${item.deltaCents >= 0 ? "positive" : "negative"}`}>{item.deltaCents >= 0 ? <ArrowDownRightIcon /> : <ArrowUpRightIcon />}</span>
          <div><strong>{item.title}</strong><small>{account?.name ?? "Konto"} · danach {formatCurrency(item.balanceAfterCents)}</small></div>
          <strong className={item.deltaCents >= 0 ? "amount income" : "amount expense"}>{item.deltaCents >= 0 ? "+" : "-"}{formatCurrency(Math.abs(item.deltaCents))}</strong>
        </div>;
      })}{!timeline.length && <div className="empty-state compact"><CalendarBlankIcon size={32} /><h2>Keine Termine geplant</h2><p>Lege eine Buchung oder Wiederholung an.</p></div>}</div>
    </section>
  </div>;
}
