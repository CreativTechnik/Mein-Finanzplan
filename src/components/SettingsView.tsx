import { useMemo, useState, type ChangeEvent, type FormEvent } from "react";
import { DatabaseIcon } from "@phosphor-icons/react/Database";
import { DownloadSimpleIcon } from "@phosphor-icons/react/DownloadSimple";
import { FolderOpenIcon } from "@phosphor-icons/react/FolderOpen";
import { PlusIcon } from "@phosphor-icons/react/Plus";
import { UploadSimpleIcon } from "@phosphor-icons/react/UploadSimple";
import type { Account, Category } from "../types";
import { formatCurrency } from "../lib/format";

function parseDelimited(text: string) {
  const firstLine = text.split(/\r?\n/, 1)[0] ?? "";
  const delimiter = (firstLine.match(/;/g) ?? []).length >= (firstLine.match(/,/g) ?? []).length ? ";" : ",";
  const rows: string[][] = [];
  let row: string[] = []; let field = ""; let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === '"' && quoted && text[index + 1] === '"') { field += '"'; index += 1; }
    else if (char === '"') quoted = !quoted;
    else if (char === delimiter && !quoted) { row.push(field.trim()); field = ""; }
    else if ((char === "\n" || char === "\r") && !quoted) {
      if (char === "\r" && text[index + 1] === "\n") index += 1;
      row.push(field.trim()); field = "";
      if (row.some(Boolean)) rows.push(row);
      row = [];
    } else field += char;
  }
  row.push(field.trim()); if (row.some(Boolean)) rows.push(row);
  return rows;
}

function parseDate(value: string) {
  const iso = value.match(/^(\d{4})-(\d{2})-(\d{2})/); if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;
  const german = value.match(/^(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})$/); if (german) return `${german[3]}-${german[2].padStart(2, "0")}-${german[1].padStart(2, "0")}`;
  return "";
}

function parseAmount(value: string) {
  const cleaned = value.replace(/\s|€|EUR/gi, "");
  const normalized = cleaned.includes(",") ? cleaned.replace(/\./g, "").replace(",", ".") : cleaned;
  const number = Number(normalized);
  return Number.isFinite(number) ? Math.round(number * 100) : 0;
}

export function SettingsView({ accounts, categories, onImport, onCreateCategory }: {
  accounts: Account[]; categories: Category[]; onImport: (rows: unknown[]) => Promise<void>; onCreateCategory: (payload: Record<string, unknown>) => Promise<void>;
}) {
  const [csvRows, setCsvRows] = useState<string[][]>([]); const [fileName, setFileName] = useState("");
  const headers = csvRows[0] ?? [];
  const [mapping, setMapping] = useState({ title: 1, date: 0, amount: 2, type: -1 });
  const [accountId, setAccountId] = useState(accounts.find((account) => account.isPrimary)?.id ?? accounts[0]?.id ?? "");
  const [categoryId, setCategoryId] = useState(""); const [importing, setImporting] = useState(false); const [message, setMessage] = useState<string | null>(null);
  const preview = useMemo(() => csvRows.slice(1, 9).map((row) => ({ title: row[mapping.title] ?? "", date: parseDate(row[mapping.date] ?? ""), amount: parseAmount(row[mapping.amount] ?? "") })), [csvRows, mapping]);

  async function chooseFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]; if (!file) return;
    if (file.size > 1_000_000) { setMessage("Die CSV-Datei darf höchstens 1 MB groß sein."); event.target.value = ""; return; }
    const rows = parseDelimited(await file.text());
    if (rows.length > 1_001) { setMessage("Es können höchstens 1.000 Buchungen auf einmal importiert werden."); event.target.value = ""; return; }
    setCsvRows(rows); setFileName(file.name); setMessage(null);
    const nextHeaders = rows[0] ?? [];
    const find = (terms: string[]) => Math.max(0, nextHeaders.findIndex((header) => terms.some((term) => header.toLowerCase().includes(term))));
    setMapping({ title: find(["bezeichnung", "text", "name", "verwendungszweck"]), date: find(["datum", "date"]), amount: find(["betrag", "amount", "umsatz"]), type: nextHeaders.findIndex((header) => /art|typ|type/.test(header.toLowerCase())) });
  }

  async function importRows() {
    const rows = csvRows.slice(1).map((row) => {
      const signed = parseAmount(row[mapping.amount] ?? ""); const typeText = mapping.type >= 0 ? (row[mapping.type] ?? "").toLowerCase() : "";
      const type = /einnahme|haben|credit/.test(typeText) ? "INCOME" : /ausgabe|soll|debit/.test(typeText) ? "EXPENSE" : signed >= 0 ? "INCOME" : "EXPENSE";
      const date = parseDate(row[mapping.date] ?? "");
      return { title: row[mapping.title] || "CSV-Buchung", amountCents: Math.abs(signed), type, accountId, transferAccountId: null, categoryId: categoryId || null, plannedDate: date, actualDate: date, status: "BOOKED", note: `Importiert aus ${fileName}`, isReliable: false };
    }).filter((row) => row.amountCents > 0 && row.plannedDate);
    if (!rows.length) { setMessage("Keine gültigen Zeilen mit Datum und Betrag gefunden."); return; }
    setImporting(true);
    try { await onImport(rows); setMessage(`${rows.length} Buchungen wurden importiert. Der bestätigte Kontosaldo blieb unverändert.`); setCsvRows([]); }
    catch (error) { setMessage(error instanceof Error ? error.message : "Import fehlgeschlagen."); }
    finally { setImporting(false); }
  }

  async function addCategory(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const data = new FormData(event.currentTarget);
    await onCreateCategory({ name: data.get("name"), kind: data.get("kind"), parentId: data.get("parentId") || null }); event.currentTarget.reset();
  }

  return <div className="page-stack">
    <header className="page-heading"><div><p className="context-line">Einstellungen</p><h1>Daten und Kategorien</h1><p>Keine Anmeldung, keine Bankverbindung und keine Cloud-Synchronisierung.</p></div></header>
    <div className="settings-grid">
      <section className="content-panel"><div className="section-heading"><div><h2>CSV importieren</h2><p>Spalten werden vor dem Import zugeordnet und geprüft.</p></div><UploadSimpleIcon size={24} /></div>
        {!csvRows.length ? <label className="file-drop"><FolderOpenIcon size={28} /><strong>CSV-Datei auswählen</strong><span>Semikolon und Komma werden erkannt.</span><input type="file" accept=".csv,text/csv" onChange={chooseFile} /></label> : <div className="csv-preview">
          <p><strong>{fileName}</strong><span>{csvRows.length - 1} Datenzeilen erkannt</span></p>
          <div className="field-grid two"><MappingSelect label="Bezeichnung" headers={headers} value={mapping.title} onChange={(value) => setMapping({ ...mapping, title: value })} /><MappingSelect label="Datum" headers={headers} value={mapping.date} onChange={(value) => setMapping({ ...mapping, date: value })} /><MappingSelect label="Betrag" headers={headers} value={mapping.amount} onChange={(value) => setMapping({ ...mapping, amount: value })} /><MappingSelect label="Art, optional" headers={headers} value={mapping.type} optional onChange={(value) => setMapping({ ...mapping, type: value })} /></div>
          <div className="field-grid two"><label>Konto<select value={accountId} onChange={(event) => setAccountId(event.target.value)}>{accounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label><label>Kategorie<select value={categoryId} onChange={(event) => setCategoryId(event.target.value)}><option value="">Ohne feste Kategorie</option>{categories.filter((category) => category.kind !== "TRANSFER").map((category) => <option key={category.id} value={category.id}>{category.parentName ? `${category.parentName} / ` : ""}{category.name}</option>)}</select></label></div>
          <div className="mini-table"><div><strong>Bezeichnung</strong><strong>Datum</strong><strong>Betrag</strong></div>{preview.map((row, index) => <div key={index}><span>{row.title || "Fehlt"}</span><span>{row.date || "Ungültig"}</span><span>{formatCurrency(row.amount)}</span></div>)}</div>
          <p className="helper-copy">Importierte Ist-Buchungen verändern den bestätigten Kontosaldo nicht. So wird ein bereits im Saldo enthaltener Umsatz nicht doppelt gezählt.</p>
          <div className="form-actions"><button className="button secondary" onClick={() => setCsvRows([])}>Verwerfen</button><button className="button primary" disabled={importing} onClick={importRows}>{importing ? "Import läuft..." : "Importieren"}</button></div>
        </div>}
        {message && <p className="inline-message">{message}</p>}
      </section>
      <section className="content-panel"><div className="section-heading"><div><h2>Kategorie hinzufügen</h2><p>Unterkategorien erleichtern Budget und Statistik.</p></div><PlusIcon size={24} /></div>
        <form className="form-stack" onSubmit={addCategory}><label>Name<input name="name" required /></label><div className="field-grid two"><label>Art<select name="kind"><option value="EXPENSE">Ausgabe</option><option value="INCOME">Einnahme</option><option value="TRANSFER">Umbuchung</option><option value="BOTH">Beides</option></select></label><label>Oberkategorie<select name="parentId"><option value="">Keine</option>{categories.filter((category) => !category.parentId).map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label></div><button className="button secondary">Kategorie speichern</button></form>
        <div className="category-cloud">{categories.map((category) => <span key={category.id}>{category.parentName ? `${category.parentName} / ` : ""}{category.name}</span>)}</div>
      </section>
      <section className="content-panel storage-panel"><span className="account-symbol"><DatabaseIcon size={25} /></span><div><h2>Lokale Datensicherung</h2><p>Exportiere Konten, Regeln, Buchungen und Vorschau als JSON-Datei.</p></div><a className="button secondary" href="/api/export" download><DownloadSimpleIcon /> Exportieren</a></section>
    </div>
  </div>;
}

function MappingSelect({ label, headers, value, optional, onChange }: { label: string; headers: string[]; value: number; optional?: boolean; onChange: (value: number) => void }) {
  return <label>{label}<select value={value} onChange={(event) => onChange(Number(event.target.value))}>{optional && <option value={-1}>Nicht zuordnen</option>}{headers.map((header, index) => <option key={`${header}-${index}`} value={index}>{header || `Spalte ${index + 1}`}</option>)}</select></label>;
}
