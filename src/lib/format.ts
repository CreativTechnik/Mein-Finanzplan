const currency = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" });
const date = new Intl.DateTimeFormat("de-DE", { day: "2-digit", month: "short", year: "numeric" });
const shortDate = new Intl.DateTimeFormat("de-DE", { day: "2-digit", month: "short" });

export function formatCurrency(cents: number) {
  return currency.format(cents / 100);
}

export function formatDate(value: string) {
  return date.format(new Date(`${value}T12:00:00`));
}

export function formatShortDate(value: string) {
  return shortDate.format(new Date(`${value}T12:00:00`));
}

export function euroToCents(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim().replace(/\./g, "").replace(",", ".");
  const amount = Number(normalized);
  return Number.isFinite(amount) ? Math.round(amount * 100) : 0;
}

export function centsToInput(cents: number) {
  return (cents / 100).toFixed(2).replace(".", ",");
}

export function accountTypeLabel(type: string) {
  return ({ CHECKING: "Girokonto", SAVINGS: "Sparen", CASH: "Bargeld", OTHER: "Weiteres Konto" } as Record<string, string>)[type] ?? type;
}

export function transactionTypeLabel(type: string) {
  return ({ INCOME: "Einnahme", EXPENSE: "Ausgabe", TRANSFER: "Umbuchung" } as Record<string, string>)[type] ?? type;
}

export function statusLabel(status: string) {
  return ({ PLANNED: "Geplant", BOOKED: "Gebucht", CANCELLED: "Storniert" } as Record<string, string>)[status] ?? status;
}

export function monthLabel(month: string) {
  return new Intl.DateTimeFormat("de-DE", { month: "long", year: "numeric" }).format(new Date(`${month}-01T12:00:00`));
}
