import { useState, type FormEvent } from "react";
import type { Account, Category, Recurrence, Transaction, TransactionStatus, TransactionType } from "../types";
import { centsToInput, euroToCents } from "../lib/format";

type SubmitHandler = (payload: Record<string, unknown>) => Promise<void>;

export function TransactionForm({ accounts, categories, initial, today, onSubmit, onCancel }: {
  accounts: Account[];
  categories: Category[];
  initial?: Transaction | null;
  today: string;
  onSubmit: SubmitHandler;
  onCancel: () => void;
}) {
  const [type, setType] = useState<TransactionType>(initial?.type ?? "EXPENSE");
  const [status, setStatus] = useState<TransactionStatus>(initial?.status ?? "PLANNED");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const relevantCategories = categories.filter((category) => category.kind === type || category.kind === "BOTH" || (type === "TRANSFER" && category.kind === "TRANSFER"));

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    const data = new FormData(event.currentTarget);
    try {
      await onSubmit({
        title: data.get("title"),
        amountCents: euroToCents(data.get("amount")),
        type,
        accountId: data.get("accountId"),
        transferAccountId: type === "TRANSFER" ? data.get("transferAccountId") : null,
        categoryId: data.get("categoryId") || null,
        plannedDate: data.get("plannedDate"),
        actualDate: status === "BOOKED" ? data.get("actualDate") || today : null,
        status,
        note: data.get("note"),
        isReliable: type === "INCOME" && data.get("isReliable") === "on",
        applyToBalance: initial?.balanceEffectApplied ?? true,
      });
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Speichern fehlgeschlagen.");
      setSaving(false);
    }
  }

  return (
    <form onSubmit={submit} className="form-stack">
      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="segmented" aria-label="Buchungsart">
        {(["EXPENSE", "INCOME", "TRANSFER"] as TransactionType[]).map((value) => (
          <button key={value} type="button" className={type === value ? "selected" : ""} onClick={() => setType(value)}>
            {{ EXPENSE: "Ausgabe", INCOME: "Einnahme", TRANSFER: "Umbuchung" }[value]}
          </button>
        ))}
      </div>
      <div className="field-grid two">
        <label>Bezeichnung<input name="title" required defaultValue={initial?.title ?? ""} autoFocus /></label>
        <label>Betrag in Euro<input name="amount" required inputMode="decimal" defaultValue={initial ? centsToInput(initial.amountCents) : ""} /></label>
      </div>
      <div className="field-grid two">
        <label>{type === "TRANSFER" ? "Von Konto" : "Konto"}
          <select name="accountId" required defaultValue={initial?.accountId ?? accounts.find((account) => account.isPrimary)?.id ?? accounts[0]?.id}>
            {accounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
          </select>
        </label>
        {type === "TRANSFER" ? (
          <label>Auf Konto<select name="transferAccountId" required defaultValue={initial?.transferAccountId ?? accounts.find((account) => !account.isPrimary)?.id}>
            {accounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
          </select></label>
        ) : (
          <label>Kategorie<select name="categoryId" defaultValue={initial?.categoryId ?? ""}>
            <option value="">Ohne Kategorie</option>
            {relevantCategories.map((category) => <option key={category.id} value={category.id}>{category.parentName ? `${category.parentName} / ` : ""}{category.name}</option>)}
          </select></label>
        )}
      </div>
      <div className="field-grid two">
        <label>Planungsdatum<input type="date" name="plannedDate" required defaultValue={initial?.plannedDate ?? today} /></label>
        <label>Status<select value={status} onChange={(event) => setStatus(event.target.value as TransactionStatus)}>
          <option value="PLANNED">Geplant</option><option value="BOOKED">Gebucht</option><option value="CANCELLED">Storniert</option>
        </select></label>
      </div>
      {status === "BOOKED" && <label>Tatsächliches Buchungsdatum<input type="date" name="actualDate" defaultValue={initial?.actualDate ?? today} /></label>}
      {type === "INCOME" && <label className="check-field"><input type="checkbox" name="isReliable" defaultChecked={initial?.isReliable} /> Diese Einnahme ist verlässlich</label>}
      <label>Notiz<textarea name="note" rows={3} defaultValue={initial?.note ?? ""} /></label>
      <div className="form-actions"><button type="button" className="button secondary" onClick={onCancel}>Abbrechen</button><button className="button primary" disabled={saving}>{saving ? "Speichert..." : "Speichern"}</button></div>
    </form>
  );
}

export function AccountForm({ initial, today, onSubmit, onCancel }: { initial?: Account | null; today: string; onSubmit: SubmitHandler; onCancel: () => void }) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setSaving(true); setError(null);
    const data = new FormData(event.currentTarget);
    try {
      await onSubmit({
        name: data.get("name"), type: data.get("type"), currentBalanceCents: euroToCents(data.get("balance")),
        balanceAsOf: data.get("balanceAsOf"), minimumBufferCents: euroToCents(data.get("buffer")),
        color: data.get("color"), isPrimary: data.get("isPrimary") === "on",
      });
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Speichern fehlgeschlagen."); setSaving(false); }
  }
  return (
    <form onSubmit={submit} className="form-stack">
      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="field-grid two">
        <label>Kontoname<input name="name" required defaultValue={initial?.name ?? ""} autoFocus /></label>
        <label>Kontoart<select name="type" defaultValue={initial?.type ?? "CHECKING"}><option value="CHECKING">Girokonto</option><option value="SAVINGS">Sparen</option><option value="CASH">Bargeld</option><option value="OTHER">Weiteres Konto</option></select></label>
      </div>
      <div className="field-grid two">
        <label>Aktueller Saldo<input name="balance" required inputMode="decimal" defaultValue={initial ? centsToInput(initial.currentBalanceCents) : "0,00"} /></label>
        <label>Saldo vom<input type="date" name="balanceAsOf" required defaultValue={initial?.balanceAsOf ?? today} /></label>
      </div>
      <div className="field-grid two">
        <label>Mindest-Puffer<input name="buffer" required inputMode="decimal" defaultValue={initial ? centsToInput(initial.minimumBufferCents) : "0,00"} /></label>
        <label>Kontofarbe<input type="color" name="color" defaultValue={initial?.color ?? "#197663"} /></label>
      </div>
      <label className="check-field"><input type="checkbox" name="isPrimary" defaultChecked={initial?.isPrimary} /> Als primäres Liquiditätskonto verwenden</label>
      <div className="form-actions"><button type="button" className="button secondary" onClick={onCancel}>Abbrechen</button><button className="button primary" disabled={saving}>{saving ? "Speichert..." : "Speichern"}</button></div>
    </form>
  );
}

export function RecurrenceForm({ accounts, categories, initial, today, onSubmit, onCancel }: {
  accounts: Account[]; categories: Category[]; initial?: Recurrence | null; today: string; onSubmit: SubmitHandler; onCancel: () => void;
}) {
  const [type, setType] = useState<TransactionType>(initial?.type ?? "EXPENSE");
  const [frequency, setFrequency] = useState(initial?.frequency ?? "MONTHLY");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const relevantCategories = categories.filter((category) => category.kind === type || category.kind === "BOTH" || (type === "TRANSFER" && category.kind === "TRANSFER"));
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setSaving(true); setError(null);
    const data = new FormData(event.currentTarget);
    try {
      await onSubmit({
        title: data.get("title"), amountCents: euroToCents(data.get("amount")), type,
        accountId: data.get("accountId"), transferAccountId: type === "TRANSFER" ? data.get("transferAccountId") : null,
        categoryId: data.get("categoryId") || null, plannedDate: data.get("startDate"), startDate: data.get("startDate"),
        endDate: data.get("endDate") || null, frequency, intervalCount: Number(data.get("intervalCount") || 1),
        intervalUnit: data.get("intervalUnit"), dueDay: data.get("dueDay") ? Number(data.get("dueDay")) : null,
        isReliable: type === "INCOME" && data.get("isReliable") === "on", active: data.get("active") === "on", note: data.get("note"),
      });
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Speichern fehlgeschlagen."); setSaving(false); }
  }
  return (
    <form onSubmit={submit} className="form-stack">
      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="segmented">{(["EXPENSE", "INCOME", "TRANSFER"] as TransactionType[]).map((value) => <button key={value} type="button" className={type === value ? "selected" : ""} onClick={() => setType(value)}>{{ EXPENSE: "Ausgabe", INCOME: "Einnahme", TRANSFER: "Umbuchung" }[value]}</button>)}</div>
      <div className="field-grid two"><label>Bezeichnung<input name="title" required defaultValue={initial?.title ?? ""} autoFocus /></label><label>Betrag in Euro<input name="amount" required inputMode="decimal" defaultValue={initial ? centsToInput(initial.amountCents) : ""} /></label></div>
      <div className="field-grid two">
        <label>{type === "TRANSFER" ? "Von Konto" : "Konto"}<select name="accountId" defaultValue={initial?.accountId ?? accounts.find((a) => a.isPrimary)?.id}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
        {type === "TRANSFER" ? <label>Auf Konto<select name="transferAccountId" defaultValue={initial?.transferAccountId ?? accounts.find((a) => !a.isPrimary)?.id}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label> : <label>Kategorie<select name="categoryId" defaultValue={initial?.categoryId ?? ""}><option value="">Ohne Kategorie</option>{relevantCategories.map((c) => <option key={c.id} value={c.id}>{c.parentName ? `${c.parentName} / ` : ""}{c.name}</option>)}</select></label>}
      </div>
      <div className="field-grid two"><label>Häufigkeit<select value={frequency} onChange={(e) => setFrequency(e.target.value as Recurrence["frequency"])}><option value="MONTHLY">Monatlich</option><option value="WEEKLY">Wöchentlich</option><option value="YEARLY">Jährlich</option><option value="CUSTOM">Freies Intervall</option></select></label><label>Alle<input type="number" min="1" max="120" name="intervalCount" defaultValue={initial?.intervalCount ?? 1} /></label></div>
      {frequency === "CUSTOM" && <label>Intervalleinheit<select name="intervalUnit" defaultValue={initial?.intervalUnit ?? "MONTHS"}><option value="DAYS">Tage</option><option value="WEEKS">Wochen</option><option value="MONTHS">Monate</option><option value="YEARS">Jahre</option></select></label>}
      {frequency !== "CUSTOM" && <input type="hidden" name="intervalUnit" value={frequency === "WEEKLY" ? "WEEKS" : frequency === "YEARLY" ? "YEARS" : "MONTHS"} />}
      <div className="field-grid three"><label>Startdatum<input type="date" name="startDate" required defaultValue={initial?.startDate ?? today} /></label><label>Enddatum, optional<input type="date" name="endDate" defaultValue={initial?.endDate ?? ""} /></label><label>Fälligkeitstag<input type="number" min="1" max="31" name="dueDay" defaultValue={initial?.dueDay ?? ""} /></label></div>
      <div className="field-grid two"><label className="check-field"><input type="checkbox" name="active" defaultChecked={initial?.active ?? true} /> Regel aktiv</label>{type === "INCOME" && <label className="check-field"><input type="checkbox" name="isReliable" defaultChecked={initial?.isReliable} /> Verlässliche Einnahme</label>}</div>
      <label>Notiz<textarea name="note" rows={3} defaultValue={initial?.note ?? ""} /></label>
      <div className="form-actions"><button type="button" className="button secondary" onClick={onCancel}>Abbrechen</button><button className="button primary" disabled={saving}>{saving ? "Speichert..." : "Speichern"}</button></div>
    </form>
  );
}
