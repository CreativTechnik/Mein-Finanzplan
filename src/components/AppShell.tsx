import type { ReactNode } from "react";
import { BankIcon } from "@phosphor-icons/react/Bank";
import { CalendarBlankIcon } from "@phosphor-icons/react/CalendarBlank";
import { ChartLineUpIcon } from "@phosphor-icons/react/ChartLineUp";
import { ClockCounterClockwiseIcon } from "@phosphor-icons/react/ClockCounterClockwise";
import { GearSixIcon } from "@phosphor-icons/react/GearSix";
import { HouseIcon } from "@phosphor-icons/react/House";
import { PiggyBankIcon } from "@phosphor-icons/react/PiggyBank";
import { ReceiptIcon } from "@phosphor-icons/react/Receipt";
import type { ViewId } from "../types";

const items: Array<{ id: ViewId; label: string; icon: typeof HouseIcon }> = [
  { id: "dashboard", label: "Übersicht", icon: HouseIcon },
  { id: "planning", label: "Planung", icon: CalendarBlankIcon },
  { id: "accounts", label: "Konten", icon: BankIcon },
  { id: "transactions", label: "Buchungen", icon: ReceiptIcon },
  { id: "recurrences", label: "Wiederkehrend", icon: ClockCounterClockwiseIcon },
  { id: "budgets", label: "Budgets", icon: PiggyBankIcon },
  { id: "statistics", label: "Statistik", icon: ChartLineUpIcon },
  { id: "settings", label: "Einstellungen", icon: GearSixIcon },
];

export function AppShell({ active, onNavigate, children, actions }: { active: ViewId; onNavigate: (view: ViewId) => void; children: ReactNode; actions?: ReactNode }) {
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark"><PiggyBankIcon size={23} weight="duotone" /></span>
          <span><strong>Mein Finanzplan</strong><small>Lokal auf diesem Mac</small></span>
        </div>
        <nav aria-label="Hauptnavigation">
          {items.map(({ id, label, icon: Icon }) => (
            <button key={id} className={active === id ? "nav-item active" : "nav-item"} onClick={() => onNavigate(id)} type="button">
              <Icon size={20} weight={active === id ? "fill" : "regular"} />
              <span>{label}</span>
            </button>
          ))}
        </nav>
        <p className="privacy-note">Daten bleiben in deiner lokalen SQLite-Datei.</p>
      </aside>
      <div className="main-column">
        <header className="topbar">
          <div><span className="mobile-brand">Mein Finanzplan</span></div>
          <div className="topbar-actions">{actions}</div>
        </header>
        <main className="main-content">{children}</main>
      </div>
      <nav className="bottom-nav" aria-label="Mobile Navigation">
        {items.map(({ id, label, icon: Icon }) => (
          <button key={id} className={active === id ? "active" : ""} onClick={() => onNavigate(id)} type="button">
            <Icon size={20} weight={active === id ? "fill" : "regular"} /><span>{label}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}
