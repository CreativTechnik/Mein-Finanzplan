import { BankIcon } from "@phosphor-icons/react/Bank";
import { CheckCircleIcon } from "@phosphor-icons/react/CheckCircle";
import { PencilSimpleIcon } from "@phosphor-icons/react/PencilSimple";
import { WarningCircleIcon } from "@phosphor-icons/react/WarningCircle";
import type { Account } from "../types";
import { accountTypeLabel, formatCurrency, formatDate } from "../lib/format";

export function AccountsView({ accounts, onAdd, onEdit }: { accounts: Account[]; onAdd: () => void; onEdit: (account: Account) => void }) {
  const total = accounts.reduce((sum, account) => sum + account.currentBalanceCents, 0);
  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Konten</p><h1>Salden und Reserven</h1><p>Jeder Ist-Saldo ist der Ausgangspunkt für die Vorschau.</p></div><button className="button primary" onClick={onAdd}>Konto hinzufügen</button></header>
    <section className="summary-band"><div><span>Gesamtvermögen</span><strong>{formatCurrency(total)}</strong></div><p>Der Gesamtwert ist informativ. Für die tägliche Sicherheit zählt das primäre Girokonto.</p></section>
    <div className="account-grid">
      {accounts.map((account) => {
        const safe = account.plannedBalanceCents >= account.minimumBufferCents;
        return <article className="account-card" key={account.id}>
          <div className="account-card-top"><span className="account-symbol" style={{ background: `${account.color}18`, color: account.color }}><BankIcon size={24} weight="duotone" /></span><button className="icon-button" onClick={() => onEdit(account)} aria-label={`${account.name} bearbeiten`}><PencilSimpleIcon size={19} /></button></div>
          <div><span className="account-kind">{accountTypeLabel(account.type)}{account.isPrimary ? " · Primär" : ""}</span><h2>{account.name}</h2></div>
          <strong className="account-balance">{formatCurrency(account.currentBalanceCents)}</strong><small>Ist-Saldo vom {formatDate(account.balanceAsOf)}</small>
          <div className="account-card-details"><div><span>90-Tage-Plan</span><strong>{formatCurrency(account.plannedBalanceCents)}</strong></div><div><span>Mindest-Puffer</span><strong>{formatCurrency(account.minimumBufferCents)}</strong></div></div>
          <p className={safe ? "account-status safe" : "account-status risk"}>{safe ? <CheckCircleIcon weight="fill" /> : <WarningCircleIcon weight="fill" />}{safe ? "Puffer wird eingehalten" : "Plan fällt unter den Puffer"}</p>
          {account.needsReview && <p className="review-note">Saldo aus der Excel-Logik abgeleitet. Bitte bestätigen.</p>}
        </article>;
      })}
    </div>
  </div>;
}
