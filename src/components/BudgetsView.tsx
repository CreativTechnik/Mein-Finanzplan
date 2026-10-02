import { useState } from "react";
import { CheckIcon } from "@phosphor-icons/react/Check";
import { PencilSimpleIcon } from "@phosphor-icons/react/PencilSimple";
import type { Budget, Category } from "../types";
import { centsToInput, euroToCents, formatCurrency, monthLabel } from "../lib/format";

export function BudgetsView({ month, budgets, categories, onSave }: { month: string; budgets: Budget[]; categories: Category[]; onSave: (payload: Record<string, unknown>) => Promise<void> }) {
  const [editing, setEditing] = useState<string | null>(null);
  const planned = budgets.reduce((sum, item) => sum + item.plannedCents, 0); const actual = budgets.reduce((sum, item) => sum + item.actualCents, 0);
  const [newCategory, setNewCategory] = useState(categories.find((item) => item.kind === "EXPENSE" && item.parentId)?.id ?? "");
  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Budgets</p><h1>{monthLabel(month)}</h1><p>Monatsbudgets sind getrennt von konkreten fälligen Zahlungen.</p></div></header>
    <section className="summary-band split"><div><span>Geplant</span><strong>{formatCurrency(planned)}</strong></div><div><span>Tatsächlich gebucht</span><strong>{formatCurrency(actual)}</strong></div><div><span>Noch offen</span><strong>{formatCurrency(Math.max(0, planned - actual))}</strong></div></section>
    <section className="content-panel"><div className="section-heading"><div><h2>Budget nach Kategorie</h2><p>Gebuchte Ausgaben werden automatisch zugeordnet.</p></div></div>
      <div className="budget-list">{budgets.map((item) => {
        const ratio = item.plannedCents > 0 ? Math.min(1, item.actualCents / item.plannedCents) : 0;
        return <div className="budget-row" key={item.id}><div><strong>{item.categoryName}</strong><small>{item.parentName ?? "Ausgaben"}</small></div><div className="budget-visual"><span style={{ width: `${ratio * 100}%` }} /></div><span>{formatCurrency(item.actualCents)} von {editing === item.id ? <input aria-label="Budgetbetrag" defaultValue={centsToInput(item.plannedCents)} autoFocus onKeyDown={async (event) => { if (event.key === "Enter") { await onSave({ month, categoryId: item.categoryId, plannedCents: euroToCents(event.currentTarget.value) }); setEditing(null); } }} /> : formatCurrency(item.plannedCents)}</span><button className="icon-button" onClick={() => setEditing(editing === item.id ? null : item.id)} aria-label="Budget bearbeiten">{editing === item.id ? <CheckIcon /> : <PencilSimpleIcon />}</button></div>;
      })}</div>
      <form className="inline-add" onSubmit={async (event) => { event.preventDefault(); const data = new FormData(event.currentTarget); await onSave({ month, categoryId: newCategory, plannedCents: euroToCents(data.get("amount")) }); event.currentTarget.reset(); }}><label>Weiteres Budget<select value={newCategory} onChange={(event) => setNewCategory(event.target.value)}>{categories.filter((item) => item.kind === "EXPENSE" && item.parentId && !budgets.some((budget) => budget.categoryId === item.id)).map((item) => <option key={item.id} value={item.id}>{item.parentName} / {item.name}</option>)}</select></label><label>Betrag<input name="amount" inputMode="decimal" required /></label><button className="button secondary">Hinzufügen</button></form>
    </section>
  </div>;
}
