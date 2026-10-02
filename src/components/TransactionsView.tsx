import { useMemo, useState } from "react";
import { ArrowDownRightIcon } from "@phosphor-icons/react/ArrowDownRight";
import { ArrowRightIcon } from "@phosphor-icons/react/ArrowRight";
import { ArrowUpRightIcon } from "@phosphor-icons/react/ArrowUpRight";
import { PencilSimpleIcon } from "@phosphor-icons/react/PencilSimple";
import { TrashIcon } from "@phosphor-icons/react/Trash";
import type { Account, Transaction } from "../types";
import { formatCurrency, formatDate, statusLabel, transactionTypeLabel } from "../lib/format";

export function TransactionsView({ transactions, occurrences, accounts, onAdd, onEdit, onDelete }: {
  transactions: Transaction[]; occurrences: Transaction[]; accounts: Account[]; onAdd: () => void; onEdit: (transaction: Transaction) => void; onDelete: (transaction: Transaction) => void;
}) {
  const [type, setType] = useState("ALL"); const [status, setStatus] = useState("ALL"); const [account, setAccount] = useState("ALL");
  const items = useMemo(() => [...transactions, ...occurrences].filter((item) =>
    (type === "ALL" || item.type === type) && (status === "ALL" || item.status === status) && (account === "ALL" || item.accountId === account || item.transferAccountId === account),
  ).sort((a, b) => b.plannedDate.localeCompare(a.plannedDate)), [transactions, occurrences, type, status, account]);
  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Buchungen</p><h1>Geplant und tatsächlich</h1><p>Wiederkehrende Termine erscheinen automatisch in der Liste.</p></div><button className="button primary" onClick={onAdd}>Buchung hinzufügen</button></header>
    <section className="filter-bar"><label>Art<select value={type} onChange={(e) => setType(e.target.value)}><option value="ALL">Alle</option><option value="INCOME">Einnahmen</option><option value="EXPENSE">Ausgaben</option><option value="TRANSFER">Umbuchungen</option></select></label><label>Status<select value={status} onChange={(e) => setStatus(e.target.value)}><option value="ALL">Alle</option><option value="PLANNED">Geplant</option><option value="BOOKED">Gebucht</option><option value="CANCELLED">Storniert</option></select></label><label>Konto<select value={account} onChange={(e) => setAccount(e.target.value)}><option value="ALL">Alle Konten</option>{accounts.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label></section>
    <section className="content-panel table-panel">
      <div className="data-table transaction-table"><div className="table-head"><span>Buchung</span><span>Datum</span><span>Konto</span><span>Status</span><span>Betrag</span><span /></div>
        {items.slice(0, 120).map((item) => <div className="table-row" key={item.id}>
          <span className="table-title"><i className={`transaction-icon ${item.type.toLowerCase()}`}>{item.type === "INCOME" ? <ArrowDownRightIcon /> : item.type === "EXPENSE" ? <ArrowUpRightIcon /> : <ArrowRightIcon />}</i><span><strong>{item.title}</strong><small>{item.categoryName ?? transactionTypeLabel(item.type)}{item.source === "RECURRENCE" ? " · Wiederholung" : ""}</small></span></span>
          <span data-label="Datum">{formatDate(item.actualDate ?? item.plannedDate)}<small>{item.actualDate ? "Gebucht" : "Geplant"}</small></span>
          <span data-label="Konto">{item.accountName ?? accounts.find((a) => a.id === item.accountId)?.name}{item.transferAccountName ? <small>nach {item.transferAccountName}</small> : null}</span>
          <span data-label="Status"><i className={`status-badge ${item.status.toLowerCase()}`}>{item.source === "RECURRENCE" ? "Automatisch" : statusLabel(item.status)}</i></span>
          <strong data-label="Betrag" className={item.type === "INCOME" ? "amount income" : item.type === "EXPENSE" ? "amount expense" : "amount"}>{item.type === "INCOME" ? "+" : item.type === "EXPENSE" ? "-" : ""}{formatCurrency(item.amountCents)}</strong>
          <span className="row-actions">{item.source !== "RECURRENCE" && <><button className="icon-button" onClick={() => onEdit(item)} aria-label="Buchung bearbeiten"><PencilSimpleIcon /></button><button className="icon-button danger" onClick={() => onDelete(item)} aria-label="Buchung löschen"><TrashIcon /></button></>}</span>
        </div>)}
      </div>{!items.length && <p className="empty-copy padded">Für diese Filter gibt es keine Buchungen.</p>}
    </section>
  </div>;
}
