import { CalendarCheckIcon } from "@phosphor-icons/react/CalendarCheck";
import { PencilSimpleIcon } from "@phosphor-icons/react/PencilSimple";
import { TrashIcon } from "@phosphor-icons/react/Trash";
import { WarningCircleIcon } from "@phosphor-icons/react/WarningCircle";
import type { Recurrence } from "../types";
import { formatCurrency, formatDate, transactionTypeLabel } from "../lib/format";

function frequencyLabel(item: Recurrence) {
  if (item.frequency === "MONTHLY") return item.intervalCount === 1 ? "Monatlich" : `Alle ${item.intervalCount} Monate`;
  if (item.frequency === "WEEKLY") return item.intervalCount === 1 ? "Wöchentlich" : `Alle ${item.intervalCount} Wochen`;
  if (item.frequency === "YEARLY") return item.intervalCount === 1 ? "Jährlich" : `Alle ${item.intervalCount} Jahre`;
  const unit = ({ DAYS: "Tage", WEEKS: "Wochen", MONTHS: "Monate", YEARS: "Jahre" } as const)[item.intervalUnit];
  return `Alle ${item.intervalCount} ${unit}`;
}

export function RecurrencesView({ items, onAdd, onEdit, onDelete }: { items: Recurrence[]; onAdd: () => void; onEdit: (item: Recurrence) => void; onDelete: (item: Recurrence) => void }) {
  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Wiederkehrend</p><h1>Regelmäßige Zahlungen</h1><p>Aus einer Regel entstehen automatisch die Termine in Vorschau und Buchungsliste.</p></div><button className="button primary" onClick={onAdd}>Regel hinzufügen</button></header>
    <section className="content-panel table-panel"><div className="data-table recurrence-table"><div className="table-head"><span>Regel</span><span>Rhythmus</span><span>Start</span><span>Betrag</span><span>Status</span><span /></div>
      {items.map((item) => <div className="table-row" key={item.id}>
        <span className="table-title"><i className="transaction-icon transfer"><CalendarCheckIcon /></i><span><strong>{item.title}</strong><small>{transactionTypeLabel(item.type)} · {item.accountName}{item.transferAccountName ? ` nach ${item.transferAccountName}` : ""}</small></span></span>
        <span data-label="Rhythmus">{frequencyLabel(item)}<small>{item.dueDay ? `am ${item.dueDay}.` : "nach Startdatum"}</small></span>
        <span data-label="Start">{formatDate(item.startDate)}{item.endDate && <small>bis {formatDate(item.endDate)}</small>}</span>
        <strong data-label="Betrag">{formatCurrency(item.amountCents)}</strong>
        <span data-label="Status"><i className={`status-badge ${item.active ? "booked" : "cancelled"}`}>{item.active ? "Aktiv" : "Pausiert"}</i>{item.needsReview && <small className="needs-review"><WarningCircleIcon /> Annahme prüfen</small>}</span>
        <span className="row-actions"><button className="icon-button" onClick={() => onEdit(item)} aria-label="Regel bearbeiten"><PencilSimpleIcon /></button><button className="icon-button danger" onClick={() => onDelete(item)} aria-label="Regel löschen"><TrashIcon /></button></span>
      </div>)}</div></section>
  </div>;
}
