import { ArrowDownRightIcon } from "@phosphor-icons/react/ArrowDownRight";
import { ArrowRightIcon } from "@phosphor-icons/react/ArrowRight";
import { ArrowUpRightIcon } from "@phosphor-icons/react/ArrowUpRight";
import { CheckCircleIcon } from "@phosphor-icons/react/CheckCircle";
import { InfoIcon } from "@phosphor-icons/react/Info";
import { WarningCircleIcon } from "@phosphor-icons/react/WarningCircle";
import type { Snapshot } from "../types";
import { formatCurrency, formatDate, formatShortDate, transactionTypeLabel } from "../lib/format";
import { BalanceChart } from "./BalanceChart";

export function Dashboard({ data, onEditAccount, onAddTransaction }: { data: Snapshot; onEditAccount: (id: string) => void; onAddTransaction: () => void }) {
  const primary = data.accounts.find((account) => account.id === data.dashboard.primaryAccountId);
  const liquidity = data.dashboard.liquidity;
  const action = data.dashboard.action;
  if (!primary || !liquidity) return <EmptyDashboard onAddTransaction={onAddTransaction} />;
  const actionSource = data.accounts.find((account) => account.id === action?.sourceAccountId);
  const actionTarget = data.accounts.find((account) => account.id === action?.targetAccountId);
  const actionText = action?.transferCents && action.deadline
    ? `Überweise spätestens am ${formatDate(action.deadline)} ${formatCurrency(action.transferCents)} von ${actionSource?.name ?? "der Reserve"} auf ${actionTarget?.name ?? primary.name}.`
    : action?.tone === "positive"
      ? `Bis ${formatDate(liquidity.horizon)} ist keine zusätzliche Umbuchung nötig.`
      : `Bis ${formatDate(liquidity.firstRiskDate ?? liquidity.horizon)} ist keine ausreichende Reserve auf einem anderen Konto erkennbar.`;

  return (
    <div className="page-stack">
      <header className="page-heading dashboard-heading">
        <div><p className="context-line">Stand {formatDate(data.today)}</p><h1>Was ist heute möglich?</h1></div>
        <button className="button primary" onClick={onAddTransaction}>Buchung hinzufügen</button>
      </header>

      {primary.needsReview && (
        <button className="review-banner" type="button" onClick={() => onEditAccount(primary.id)}>
          <InfoIcon size={22} weight="fill" />
          <span><strong>Giro-Saldo noch bestätigen</strong><small>Der Excel-Plan enthält keinen aktuellen Kontostand. Trage ihn ein, damit die Aussage belastbar wird.</small></span>
          <ArrowRightIcon size={19} />
        </button>
      )}

      <section className="decision-grid">
        <article className="available-panel">
          <div className="available-copy">
            <p>Heute frei verfügbar</p>
            <strong>{formatCurrency(liquidity.availableCents)}</strong>
            <span>ohne kommende Zahlungen und deinen Puffer zu gefährden</span>
          </div>
          <div className="calculation-strip">
            <div><span>Ist-Saldo</span><strong>{formatCurrency(primary.currentBalanceCents)}</strong></div>
            <span className="operator">-</span>
            <div><span>Bis {formatShortDate(liquidity.horizon)} benötigt</span><strong>{formatCurrency(liquidity.requiredStartingBalanceCents)}</strong></div>
            <span className="operator">=</span>
            <div><span>Frei</span><strong>{formatCurrency(liquidity.availableCents)}</strong></div>
          </div>
        </article>
        <div className="decision-side">
          <article className="metric-block"><span>Bis Sonntag benötigt</span><strong>{formatCurrency(liquidity.weekRequiredStartingBalanceCents)}</strong><small>Puffer eingeschlossen</small></article>
          <article className="metric-block"><span>Nächste verlässliche Einnahme</span><strong>{liquidity.nextIncome ? formatCurrency(liquidity.nextIncome.amountCents) : "Nicht geplant"}</strong><small>{liquidity.nextIncome ? `${liquidity.nextIncome.title}, ${formatDate(liquidity.nextIncome.date)}` : "90 Tage werden betrachtet"}</small></article>
        </div>
      </section>

      {action && (
        <section className={`action-callout ${action.tone}`}>
          {action.tone === "positive" ? <CheckCircleIcon size={26} weight="fill" /> : <WarningCircleIcon size={26} weight="fill" />}
          <div><strong>{action.title}</strong><p>{actionText}</p></div>
        </section>
      )}

      <section className="content-panel chart-panel">
        <div className="section-heading"><div><h2>Liquidität der nächsten 90 Tage</h2><p>Erwarteter Saldo nach geplanten Buchungen und Wiederholungen.</p></div><span className="range-label">bis {formatDate(data.dashboard.forecast.endDate)}</span></div>
        <BalanceChart accounts={data.accounts.filter((account) => account.type !== "CASH" || account.currentBalanceCents !== 0)} points={data.dashboard.forecast.daily} />
      </section>

      <div className="dashboard-lower">
        <section className="content-panel">
          <div className="section-heading"><div><h2>Nächste Zahlungen</h2><p>Geplant und noch nicht gebucht.</p></div></div>
          <div className="transaction-list compact">
            {data.dashboard.upcoming.slice(0, 7).map((item) => (
              <div className="transaction-row" key={item.id}>
                <span className={`transaction-icon ${item.type.toLowerCase()}`}>{item.type === "INCOME" ? <ArrowDownRightIcon /> : item.type === "EXPENSE" ? <ArrowUpRightIcon /> : <ArrowRightIcon />}</span>
                <span className="transaction-main"><strong>{item.title}</strong><small>{formatDate(item.plannedDate)} · {item.accountName}</small></span>
                <strong className={item.type === "INCOME" ? "amount income" : item.type === "EXPENSE" ? "amount expense" : "amount"}>{item.type === "INCOME" ? "+" : item.type === "EXPENSE" ? "-" : ""}{formatCurrency(item.amountCents)}</strong>
              </div>
            ))}
            {!data.dashboard.upcoming.length && <p className="empty-copy">Keine kommenden Buchungen vorhanden.</p>}
          </div>
        </section>
        <section className="content-panel">
          <div className="section-heading"><div><h2>Konten im Blick</h2><p>Ist-Saldo, Plan und Puffer.</p></div></div>
          <div className="account-summary-list">
            {data.accounts.map((account) => {
              const risk = data.dashboard.warnings.find((warning) => warning.accountId === account.id);
              return <button type="button" key={account.id} onClick={() => onEditAccount(account.id)}>
                <i style={{ background: account.color }} /><span><strong>{account.name}</strong><small>{risk ? `Unter Puffer ab ${formatShortDate(risk.date)}` : "Puffer im Plan eingehalten"}</small></span><span className="account-values"><strong>{formatCurrency(account.currentBalanceCents)}</strong><small>Plan {formatCurrency(account.plannedBalanceCents)}</small></span>
              </button>;
            })}
          </div>
        </section>
      </div>
      <span className="sr-only">Buchungsarten: {transactionTypeLabel("INCOME")}, {transactionTypeLabel("EXPENSE")}, {transactionTypeLabel("TRANSFER")}</span>
    </div>
  );
}

function EmptyDashboard({ onAddTransaction }: { onAddTransaction: () => void }) {
  return <section className="empty-state"><h1>Noch kein Liquiditätskonto</h1><p>Lege zuerst ein Girokonto an, damit die App deinen frei verfügbaren Betrag berechnen kann.</p><button className="button primary" onClick={onAddTransaction}>Erste Buchung anlegen</button></section>;
}
