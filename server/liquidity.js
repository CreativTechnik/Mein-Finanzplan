import { addDays, endOfWeek } from "./date.js";

function movementPriority(movement) {
  return movement.deltaCents < 0 ? 0 : 1;
}

export function toMovements(events) {
  const movements = [];
  for (const event of events) {
    if (event.status === "CANCELLED") continue;
    const base = {
      eventId: event.id,
      recurrenceId: event.recurrenceId ?? null,
      title: event.title,
      date: event.actualDate ?? event.plannedDate,
      plannedDate: event.plannedDate,
      type: event.type,
      amountCents: event.amountCents,
      categoryId: event.categoryId ?? null,
      source: event.source,
      isReliable: Boolean(event.isReliable),
      status: event.status,
    };
    if (event.type === "INCOME") {
      movements.push({ ...base, accountId: event.accountId, deltaCents: event.amountCents });
    } else if (event.type === "EXPENSE") {
      movements.push({ ...base, accountId: event.accountId, deltaCents: -event.amountCents });
    } else if (event.type === "TRANSFER") {
      movements.push({ ...base, accountId: event.accountId, deltaCents: -event.amountCents, transferSide: "FROM" });
      movements.push({ ...base, accountId: event.transferAccountId, deltaCents: event.amountCents, transferSide: "TO" });
    }
  }
  return movements.sort(
    (a, b) => a.date.localeCompare(b.date) || movementPriority(a) - movementPriority(b) || a.title.localeCompare(b.title),
  );
}

function requirementForHorizon(account, movements, today, horizon, excludedEventId = null) {
  let projected = account.currentBalanceCents;
  let minimum = projected;
  let firstRiskDate = projected < account.minimumBufferCents ? today : null;
  for (const movement of movements) {
    if (movement.accountId !== account.id || movement.date < today || movement.date > horizon) continue;
    if (excludedEventId && movement.eventId === excludedEventId && movement.deltaCents > 0) continue;
    projected += movement.deltaCents;
    if (projected < minimum) minimum = projected;
    if (!firstRiskDate && projected < account.minimumBufferCents) firstRiskDate = movement.date;
  }
  const largestDrawdown = Math.max(0, account.currentBalanceCents - minimum);
  const requiredStartingBalanceCents = account.minimumBufferCents + largestDrawdown;
  return {
    minimumProjectedCents: minimum,
    requiredStartingBalanceCents,
    availableCents: Math.max(0, account.currentBalanceCents - requiredStartingBalanceCents),
    shortfallCents: Math.max(0, requiredStartingBalanceCents - account.currentBalanceCents),
    firstRiskDate,
  };
}

export function calculateLiquidity(account, movements, today, fallbackDays = 90) {
  const nextIncome = movements.find(
    (movement) =>
      movement.accountId === account.id &&
      movement.date >= today &&
      movement.deltaCents > 0 &&
      movement.isReliable,
  );
  const horizon = nextIncome?.date ?? addDays(today, fallbackDays);
  const untilIncome = requirementForHorizon(account, movements, today, horizon, nextIncome?.eventId ?? null);
  const weekEnd = endOfWeek(today);
  const untilWeekEnd = requirementForHorizon(account, movements, today, weekEnd);
  return {
    ...untilIncome,
    horizon,
    nextIncome: nextIncome
      ? { date: nextIncome.date, title: nextIncome.title, amountCents: nextIncome.deltaCents }
      : null,
    weekEnd,
    weekRequiredStartingBalanceCents: untilWeekEnd.requiredStartingBalanceCents,
    weekShortfallCents: untilWeekEnd.shortfallCents,
  };
}

export function buildForecast(accounts, movements, today, days = 90) {
  const endDate = addDays(today, days);
  const balances = new Map(accounts.map((account) => [account.id, account.currentBalanceCents]));
  const daily = [];
  const timeline = [];
  let movementIndex = 0;

  for (let offset = 0; offset <= days; offset += 1) {
    const date = addDays(today, offset);
    while (movementIndex < movements.length && movements[movementIndex].date < date) movementIndex += 1;
    let cursor = movementIndex;
    while (cursor < movements.length && movements[cursor].date === date) {
      const movement = movements[cursor];
      balances.set(movement.accountId, (balances.get(movement.accountId) ?? 0) + movement.deltaCents);
      timeline.push({
        ...movement,
        balanceAfterCents: balances.get(movement.accountId),
      });
      cursor += 1;
    }
    movementIndex = cursor;
    daily.push({
      date,
      balances: Object.fromEntries(accounts.map((account) => [account.id, balances.get(account.id) ?? 0])),
    });
  }

  const plannedByAccount = Object.fromEntries(accounts.map((account) => [account.id, balances.get(account.id) ?? 0]));
  const warnings = [];
  for (const account of accounts) {
    const firstBelow = daily.find((point) => point.balances[account.id] < account.minimumBufferCents);
    if (firstBelow) {
      warnings.push({
        accountId: account.id,
        accountName: account.name,
        date: firstBelow.date,
        balanceCents: firstBelow.balances[account.id],
        bufferCents: account.minimumBufferCents,
      });
    }
  }
  return { endDate, daily, timeline, plannedByAccount, warnings };
}

export function buildAction(liquidity, primaryAccount, accounts, today) {
  if (liquidity.shortfallCents <= 0) {
    return {
      tone: "positive",
      title: "Dein Puffer bleibt geschützt",
      text: `Bis ${liquidity.horizon} ist keine zusätzliche Umbuchung nötig.`,
    };
  }
  const source = accounts
    .filter((account) => account.id !== primaryAccount.id)
    .map((account) => ({ ...account, freeCents: Math.max(0, account.currentBalanceCents - account.minimumBufferCents) }))
    .sort((a, b) => b.freeCents - a.freeCents)[0];
  const transferCents = Math.min(liquidity.shortfallCents, source?.freeCents ?? 0);
  const deadline = !liquidity.firstRiskDate || liquidity.firstRiskDate <= today
    ? today
    : addDays(liquidity.firstRiskDate, -1);
  if (source && transferCents > 0) {
    return {
      tone: "warning",
      title: "Umbuchung empfohlen",
      text: `${source.name} kann die erwartete Lücke auf ${primaryAccount.name} ausgleichen.`,
      transferCents,
      sourceAccountId: source.id,
      targetAccountId: primaryAccount.id,
      deadline,
    };
  }
  return {
    tone: "danger",
    title: "Deckung reicht voraussichtlich nicht aus",
    text: `Für den Zeitraum bis ${liquidity.firstRiskDate ?? liquidity.horizon} ist keine ausreichende Reserve auf einem anderen Konto erkennbar.`,
  };
}

export const __test = { requirementForHorizon };
