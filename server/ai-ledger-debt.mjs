import { sanitizeLedgerText } from './ai-ledger-tools.mjs';
import {
  balanceAsOf, balanceDelta, creditLedgerAt, dayKey, debtLedgerIndex, loanCreditsAt,
  loanInstallments, monthDay, monthNumber, offsetDays, parseDay, unpaidInstallment,
  validMonthDay,
} from './reminder-events.mjs';

const money = (n) => Math.round((n + Number.EPSILON) * 100) / 100 || 0;
const unit = (value) => sanitizeLedgerText(value || 'MYR', 12).toUpperCase();
const complete = (a) => a.credit_limit != null && validMonthDay(a.statement_day) && validMonthDay(a.payment_due_day);
const incoming = (id, tx) => tx.type === 'transfer' && tx.account_id !== id && tx.to_account_id === id;
const isCash = (a) => a && (['bankSaving', 'cash', 'eWallet'].includes(a.account_type) ||
  (['other', 'moneyMarketFund'].includes(a.account_type) && a.report_group === 'cash'));

function closeFor(day, cutDay) {
  const month = monthNumber(day);
  const cut = monthDay(month, cutDay);
  return day <= cut ? cut : monthDay(month + 1, cutDay);
}

function period(account, close) {
  const m = monthNumber(close);
  const due = monthDay(m, account.payment_due_day);
  return {
    starts: dayKey(offsetDays(monthDay(m - 1, account.statement_day), 1)),
    statement_date: dayKey(close),
    due_date: dayKey(due <= close ? monthDay(m + 1, account.payment_due_day) : due),
  };
}

function originalStatements(account, entries, periods, meta) {
  let overrides;
  try { overrides = JSON.parse(meta?.[`credit_card_statement_amounts_${account.id}_json`] ?? '{}'); }
  catch { overrides = {}; }
  const statements = new Map(periods.map((p) => [p.statement_date, { ...p, charge: 0, receipt: 0, evidence: false }]));
  for (const tx of entries) {
    if (tx.account_id === account.id) {
      const billingDay = parseDay(tx.card_posting_date) ?? tx.date;
      const row = statements.get(dayKey(closeFor(billingDay, account.statement_day)));
      if (row) {
        row.charge -= balanceDelta(account.id, tx);
        row.evidence = true;
      }
      // A deferred charge is positive evidence for a genuine zero printed
      // bill. A bank payment after this cut cannot invent an original amount.
      if (tx.card_posting_date) {
        const economic = statements.get(dayKey(closeFor(tx.date, account.statement_day)));
        if (economic) economic.evidence = true;
      }
    } else if (incoming(account.id, tx)) {
      const date = dayKey(tx.date);
      for (const row of statements.values()) {
        if (date >= row.statement_date && date <= row.due_date) row.receipt += tx.to_amount ?? tx.amount;
      }
    }
  }
  return [...statements.values()].map(({ charge, receipt, evidence, ...p }) => {
    const manual = overrides?.[p.statement_date];
    return { ...p, original_amount: money(Number.isFinite(manual) && manual >= 0 ? manual : Math.max(0, evidence ? charge : receipt)) };
  });
}

function recentCardEntries(card, entries, today) {
  return entries.filter((tx) => tx.date <= today)
    .sort((a, b) => b.date - a.date || String(b.transaction_date).localeCompare(String(a.transaction_date)))
    .slice(0, 6).map((tx) => {
      const received = incoming(card.id, tx);
      const billingDay = received ? tx.date : parseDay(tx.card_posting_date) ?? tx.date;
      return {
        date: dayKey(tx.date), billing_day: dayKey(billingDay),
        role: received ? 'repayment_received' : 'source_charge',
        amount: money((received ? 1 : -1) * balanceDelta(card.id, tx)),
        ...(received || !complete(card) ? {} : { statement_date: dayKey(closeFor(billingDay, card.statement_day)) }),
        ...(tx.merchant ? { merchant: sanitizeLedgerText(tx.merchant) } : {}),
      };
    });
}

export function createAiDebtView(snapshot, { asOf, convert, balanceAt, index = debtLedgerIndex(snapshot) }) {
  const today = parseDay(asOf);
  if (!today) throw new TypeError('Invalid ledger cutoff day');
  const end = offsetDays(today, 30);
  const endKey = dayKey(end);
  const { accounts, legacy, byAccount } = index;
  const accountList = [...accounts.values()];
  const rows = (id) => byAccount.get(id) ?? [];
  const base = (amount, currency) => {
    const value = convert(amount, currency);
    return Number.isFinite(value) ? money(value) : null;
  };
  const actualBalance = (a) => a.account_type === 'loan' && parseDay(a.loan_start_date) > today ? 0
    : legacy ? balanceAsOf(a, rows(a.id), today) : balanceAt(a.id, asOf);
  const common = (a) => ({ name: sanitizeLedgerText(a.name), currency: unit(a.currency), is_active: a.is_active !== false });

  function cardView(card, months) {
    const entries = rows(card.id);
    const balance = actualBalance(card);
    const current = card.current_balance ?? balance;
    const view = {
      ...common(card), statement_day: card.statement_day ?? null, payment_due_day: card.payment_due_day ?? null,
      estimated: !complete(card), outstanding: money(Math.max(0, -balance)), committed_outstanding: money(Math.max(0, -current)),
      recent_entries: recentCardEntries(card, entries, today),
    };
    if (!complete(card)) {
      return { ...view, due_date: dayKey(monthDay(monthNumber(today) + 1, 25)), billed_balance: view.outstanding,
        billed_balance_base: base(view.outstanding, view.currency), unbilled_balance: 0, open_statements: [], statements: [], next_statement: null };
    }
    const ledger = creditLedgerAt(card, entries, today, { signedBalance: balance });
    const due = [...ledger.remaining].filter(([cut, amount]) => cut <= +ledger.closed && amount >= .005)
      .map(([cut, amount]) => ({ ...period(card, new Date(cut)), amount: money(amount) }));
    const periods = Array.from({ length: months }, (_, i) => period(card, monthDay(monthNumber(ledger.closed) - i, card.statement_day)));
    const [next, ...history] = originalStatements(card, entries, [period(card, ledger.nextCut), ...periods], snapshot.meta);
    const billed = due[0]?.amount ?? 0;
    return {
      ...view, due_date: due[0]?.due_date ?? history[0].due_date, billed_balance: billed,
      billed_balance_base: base(billed, view.currency), unbilled_balance: money(ledger.unbilled),
      open_statement_count: due.length, open_total: money(due.reduce((s, row) => s + row.amount, 0)),
      open_statements: due.slice(0, 12), statements: history.map((p) => ({ ...p,
        unpaid: money(ledger.remaining.get(+parseDay(p.statement_date)) ?? 0) })),
      next_statement: { ...next, unbilled: money(ledger.unbilled) },
    };
  }

  function loanView(a) {
    const contract = parseDay(a.loan_start_date);
    const start = parseDay(a.loan_tracking_start_date) ?? contract;
    const schedule = contract && start >= contract && validMonthDay(a.loan_payment_day) && loanInstallments(a);
    const principal = money(Math.max(0, -actualBalance(a)));
    const result = { ...common(a), remaining_principal: principal, remaining_principal_base: base(principal, unit(a.currency)),
      remaining_periods: null, remaining_interest: null, next_installment: null };
    if (!schedule) return { result, due: null };
    const entries = rows(a.id);
    const credits = loanCreditsAt({ account: a, accounts, transactions: entries, today, legacy });
    // Gross contractual need, like monthlyFundingNeedForMonth: a future
    // bank debit covers its own installment but does not erase the need for
    // cash. A future reversal can reopen principal or interest for that term.
    const beforeCash = loanCreditsAt({ account: a, accounts, transactions: entries.filter((tx) =>
      tx.date <= today || !isCash(accounts.get(tx.account_id))), today: end, legacy });
    const afterCash = loanCreditsAt({ account: a, accounts, transactions: entries, today: end, legacy });
    let first;
    let count = 0, interest = 0, due = 0;
    if (!(legacy && !entries.length && principal === 0)) {
      schedule.forEach((installment, i) => {
        const n = i + 1;
        const unpaid = unpaidInstallment(installment, credits.get(n));
        const date = dayKey(monthDay(monthNumber(start) + n, a.loan_payment_day));
        if (date <= endKey) {
          due += Math.max(unpaidInstallment(installment, beforeCash.get(n)).payment,
            unpaidInstallment(installment, afterCash.get(n)).payment);
        }
        if (!unpaid.payment) return;
        first ??= { number: n, due_date: date, ...unpaid };
        count++;
        interest += unpaid.interest;
      });
    }
    return { result: { ...result, remaining_periods: count, remaining_interest: money(interest), next_installment: first ?? null }, due: money(due) };
  }

  const cardAccounts = accountList.filter((a) => a.account_type === 'creditCard');
  const loans = accountList.filter((a) => a.account_type === 'loan');
  let loanResults;
  const loanViews = () => loanResults ??= loans.map(loanView);
  let pressure;
  return {
    cards(accountName, monthCount = 1) {
      const query = accountName == null ? null : sanitizeLedgerText(accountName).toLocaleLowerCase();
      return cardAccounts.filter((a) => query == null || sanitizeLedgerText(a.name).toLocaleLowerCase() === query)
        .map((a) => cardView(a, Math.min(12, Math.max(1, Math.trunc(monthCount) || 1))));
    },
    loans: () => loanViews().map(({ result }) => result),
    pressure30() {
      if (pressure) return pressure;
      const items = [], totals = new Map(), missing = new Set(), unknownLoans = [];
      function add(account, kind, amount, currency) {
        const value = money(amount);
        if (!value) return;
        currency = unit(currency);
        const converted = base(value, currency);
        if (converted == null) missing.add(currency);
        items.push({ name: sanitizeLedgerText(account.name), kind, currency, amount: value, amount_base: converted });
        totals.set(currency, (totals.get(currency) ?? 0) + value);
      }
      const plans = plannedCardTransfers(snapshot.transactions ?? [], accounts, today, end);
      for (const card of cardAccounts) {
        const funding = cardFunding(card, rows(card.id), plans.get(card.id) ?? [], accounts, today, end, actualBalance(card));
        add(card, 'uncovered_credit_due', funding.reserve, card.currency);
        for (const [currency, amount] of funding.cash) add(card, 'scheduled_bank_payment', amount, currency);
      }
      loanViews().forEach(({ due, result }, i) => {
        if (due != null) add(loans[i], 'loan_installments_due', due, loans[i].currency);
        else if (result.remaining_principal) unknownLoans.push(result.name);
      });
      const byCurrency = [...totals].map(([currency, n]) => ({ currency, amount: money(n), amount_base: base(n, currency) }));
      pressure = { from: asOf, through: endKey, includes_overdue: true, by_currency: byCurrency,
        total_base: missing.size || unknownLoans.length ? null : money(byCurrency.reduce((sum, x) => sum + x.amount_base, 0)),
        unpriced_currencies: [...missing], unscheduled_loans: unknownLoans, items };
      return pressure;
    },
  };
}

// Only bank/card repayments are promoted from planned to effective in the
// forecast. An outgoing card transfer affects both cards but no bank account.
function plannedCardTransfers(transactions, accounts, today, end) {
  const result = new Map();
  for (const tx of transactions) {
    if (tx.type !== 'transfer' || tx.status !== 'planned' || tx.account_id === tx.to_account_id) continue;
    const source = accounts.get(tx.account_id), target = accounts.get(tx.to_account_id);
    if (target?.account_type !== 'creditCard' || !(isCash(source) || source?.account_type === 'creditCard')) continue;
    const date = parseDay(tx.transaction_date);
    if (!date || date <= today || date > end) continue;
    const entry = { ...tx, date };
    for (const a of [source, target]) {
      if (a.account_type !== 'creditCard') continue;
      if (!result.has(a.id)) result.set(a.id, []);
      result.get(a.id).push(entry);
    }
  }
  return result;
}

function cardFunding(card, entries, planned, accounts, today, end, openingBalance) {
  const history = entries.filter((tx) => tx.date <= today);
  const upcoming = [...entries.filter((tx) => tx.date > today && tx.date <= end), ...planned];
  upcoming.sort((a, b) => a.date - b.date || String(a.transaction_date).localeCompare(String(b.transaction_date)) ||
    String(a.id).localeCompare(String(b.id)));
  let balance = openingBalance;
  const configured = complete(card);
  const cash = new Map();
  const estimatedDate = (date) => monthDay(monthNumber(date) + 1, 25);
  const estimates = new Map([[+estimatedDate(today), Math.max(0, -balance)]]);
  let estimateCredit = Math.max(0, balance);
  function dueAt(day) {
    if (!configured) {
      let credit = estimateCredit, debt = Math.max(0, -balance);
      const amounts = new Map();
      for (const [maturity, amount] of estimates) {
        if (maturity > +day) continue;
        const need = Math.min(debt, Math.max(0, amount - credit));
        credit = Math.max(0, credit - amount);
        debt -= need;
        if (need >= .005) amounts.set(maturity, need);
      }
      return amounts;
    }
    const ledger = creditLedgerAt(card, history, day, { signedBalance: balance, openingAsOf: today });
    const amounts = new Map();
    for (const [cut, value] of ledger.remaining) {
      if (value < .005 || cut > +ledger.closed) continue;
      if (period(card, new Date(cut)).due_date <= dayKey(day)) amounts.set(cut, value);
    }
    return amounts;
  }
  const days = new Map([[+today, []], [+end, []]]);
  const schedule = (d) => {
    if (d >= today && d <= end && !days.has(+d)) days.set(+d, []);
  };
  for (let m = monthNumber(today); m <= monthNumber(end); m++) {
    schedule(monthDay(m, configured ? card.payment_due_day : 25));
  }
  for (const tx of upcoming) {
    schedule(tx.date);
    days.get(+tx.date).push(tx);
  }
  // A reserved debit can be replaced only once and only for the same bill.
  // A later merchant credit releases its replacement right but cannot refund
  // a bank payment which the forecast already required at maturity.
  const replaceable = new Map();
  let reserve = 0;
  for (const [stamp, daily] of [...days].sort(([a], [b]) => a - b)) {
    const day = new Date(stamp);
    // At most two ledger replays per date, including high-volume ledgers.
    // Net credits by instrument, preserving the ordering of credit sources
    // within the day when attributing reductions to reserved statements.
    const before = replaceable.size && daily.length ? dueAt(day) : null;
    const credits = [];
    for (const tx of daily) {
      const delta = balanceDelta(card.id, tx);
      const source = accounts.get(tx.account_id);
      const fromBank = incoming(card.id, tx) && isCash(source);
      const refinance = tx.type === 'transfer' && tx.account_id !== tx.to_account_id &&
        source?.account_type === 'creditCard' && accounts.get(tx.to_account_id)?.account_type === 'creditCard';
      if (fromBank) {
        const currency = unit(tx.currency ?? source.currency);
        cash.set(currency, (cash.get(currency) ?? 0) + tx.amount);
      }
      const posted = tx.account_id !== card.id || (parseDay(tx.card_posting_date) ?? tx.date) <= day;
      if (before && delta > 0 && posted) credits.push({ amount: delta, replace: fromBank || refinance });
      if (!configured) {
        if (delta < 0 && refinance) {
          const maturity = +estimatedDate(tx.date);
          estimates.set(maturity, (estimates.get(maturity) ?? 0) - delta);
        } else if (delta > 0 || incoming(card.id, tx)) estimateCredit += delta;
      }
      balance += delta;
      history.push(tx);
    }
    const after = dueAt(day);
    if (before && credits.length) {
      let idx = 0;
      for (const [cut, reserved] of replaceable) {
        const matched = Math.min(reserved, Math.max(0, (before.get(cut) ?? 0) - (after.get(cut) ?? 0)));
        let toMatch = matched;
        while (idx < credits.length && toMatch > .00001) {
          const credit = credits[idx], used = Math.min(toMatch, credit.amount);
          if (credit.replace) reserve -= used;
          toMatch -= used;
          credit.amount -= used;
          if (credit.amount < .00001) idx++;
        }
        if (reserved - matched < .005) replaceable.delete(cut);
        else replaceable.set(cut, reserved - matched);
      }
    }
    let funded = reserve;
    for (const [cut, due] of after) {
      const covered = Math.min(due, Math.max(0, funded));
      funded -= covered;
      if (due - covered < .005) continue;
      reserve += due - covered;
      replaceable.set(cut, (replaceable.get(cut) ?? 0) + due - covered);
    }
  }
  return { reserve: money(reserve), cash };
}
