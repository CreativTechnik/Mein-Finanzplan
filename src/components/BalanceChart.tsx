import type { Account, ForecastPoint } from "../types";
import { formatCurrency, formatShortDate } from "../lib/format";

export function BalanceChart({ accounts, points }: { accounts: Account[]; points: ForecastPoint[] }) {
  if (!accounts.length || !points.length) return <div className="empty-chart">Noch keine Vorschau verfügbar.</div>;
  const width = 900;
  const height = 280;
  const padding = { top: 22, right: 24, bottom: 38, left: 74 };
  const visible = points.filter((_, index) => index % 2 === 0 || index === points.length - 1);
  const all = visible.flatMap((point) => accounts.map((account) => point.balances[account.id] ?? 0));
  const min = Math.min(0, ...all);
  const max = Math.max(10_000, ...all);
  const span = Math.max(1, max - min);
  const x = (index: number) => padding.left + (index / Math.max(1, visible.length - 1)) * (width - padding.left - padding.right);
  const y = (value: number) => padding.top + ((max - value) / span) * (height - padding.top - padding.bottom);
  const ticks = [max, min + span * 0.5, min];

  return (
    <div className="chart-wrap">
      <svg className="balance-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Erwartete Kontosalden für 90 Tage">
        {ticks.map((tick) => (
          <g key={tick}>
            <line x1={padding.left} x2={width - padding.right} y1={y(tick)} y2={y(tick)} className="chart-grid" />
            <text x={padding.left - 10} y={y(tick) + 4} textAnchor="end" className="chart-label">{formatCurrency(tick)}</text>
          </g>
        ))}
        {accounts.map((account) => {
          const path = visible.map((point, index) => `${index === 0 ? "M" : "L"}${x(index)},${y(point.balances[account.id] ?? 0)}`).join(" ");
          return <path key={account.id} d={path} fill="none" stroke={account.color} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />;
        })}
        {[0, Math.floor((visible.length - 1) / 2), visible.length - 1].map((index) => (
          <text key={index} x={x(index)} y={height - 10} textAnchor={index === 0 ? "start" : index === visible.length - 1 ? "end" : "middle"} className="chart-label">
            {formatShortDate(visible[index].date)}
          </text>
        ))}
      </svg>
      <div className="chart-legend">
        {accounts.map((account) => <span key={account.id}><i style={{ background: account.color }} />{account.name}</span>)}
      </div>
    </div>
  );
}
