import { createHash } from 'node:crypto';

const advanceDays = 3;
const epsilon = 0.005;
const dayMilliseconds = 86_400_000;

function parseDay(value) {
  const prefix = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}(?=T|$)/.exec(value)?.[0];
  if (!prefix) return null;
  const date = new Date(`${prefix}T00:00:00.000Z`);
  return Number.isFinite(date.valueOf()) && dayKey(date) === prefix ? date : null;
}

const dayKey = (date) => date.toISOString().slice(0, 10);
const offsetDays = (date, days) => new Date(date.valueOf() + days * dayMilliseconds);
const monthNumber = (date) => date.getUTCFullYear() * 12 + date.getUTCMonth();
const validMonthDay = (day) => Number.isInteger(day) && day >= 1 && day <= 31;
const money = (value) => Math.round(value * 100) / 100;

function monthDay(month, day) {
  const date = new Date(0);
  date.setUTCFullYear(Math.floor(month / 12), month % 12 + 1, 0);
  date.setUTCDate(Math.min(day, date.getUTCDate()));
  return date;
}

function readPreferences(meta = {}) {
  let switches;
  try {
    switches = JSON.parse(meta?.notification_preferences_json);
  } catch {
    // Older ledgers may have no stored preferences.
  }
  const enabled = (index) => !Array.isArray(switches) || switches[index] !== false;
  return {
    repayment: enabled(0),
    statement: enabled(1),
    dueToday: enabled(6),
    loan: meta?.loan_payment_push_enabled !== 'false',
  };
}

function indexTransactions(transactions) {
  const byAccount = new Map();
  const add = (id, entry) => {
    if (!byAccount.has(id)) byAccount.set(id, []);
    byAccount.get(id).push(entry);
  };
  for (const transaction of transactions) {
    const date = parseDay(transaction?.transaction_date);
    if (!date || transaction.status === 'planned' || !Number.isFinite(transaction.amount)) {
      continue;
    }
    const entry = { ...transaction, date };
    add(entry.account_id, entry);
    if (entry.type === 'transfer' && entry.to_account_id && entry.to_account_id !== entry.account_id) {
      add(entry.to_account_id, entry);
    }
  }
  return byAccount;
}

function transferIn(transaction) {
  const from = (transaction.currency ?? '').trim().toUpperCase();
  const to = (transaction.to_currency ?? transaction.currency ?? '').trim().toUpperCase();
  // Match FinanceTransaction.transferInAmount for legacy same-currency rows.
  if (transaction.amount !== 0 && transaction.to_amount === 0 && from === to) return transaction.amount;
  return transaction.to_amount ?? transaction.amount;
}

function balanceDelta(accountId, transaction) {
  if (transaction.account_id === accountId) {
    return transaction.type === 'expense' || transaction.type === 'transfer'
      ? -transaction.amount
      : transaction.amount;
  }
  return transferIn(transaction);
}

function balanceAsOf(account, transactions, today) {
  if (!Number.isFinite(account.current_balance)) {
    return transactions.reduce(
      (balance, item) => item.date <= today ? balance + balanceDelta(account.id, item) : balance,
      account.initial_balance ?? 0,
    );
  }
  // Like FinanceRepository.accountBalanceAt, undo future actual or settled
  // transactions that are already reflected in the exported current balance.
  return transactions.reduce(
    (balance, item) => item.date > today ? balance - balanceDelta(account.id, item) : balance,
    account.current_balance,
  );
}

function creditBilledBalance(account, transactions, statement, today) {
  // calculateCreditCardBilling allocates current debt to net new spending
  // first. Payments enter through current balance and must not count as spend.
  const newerSpending = transactions.reduce((sum, item) =>
    item.account_id === account.id && item.date > statement && item.date <= today
      ? sum - balanceDelta(account.id, item)
      : sum, 0);
  return -balanceAsOf(account, transactions, today) - Math.max(0, newerSpending);
}

function creditDueStatements(account, target) {
  const { statement_day: cutDay, payment_due_day: payDay } = account;
  const month = monthNumber(target);
  const matches = [];
  // The payment belongs to a statement from the same or previous calendar
  // month. Resolve dates after clamping, just like the Flutter billing period.
  for (const offset of [0, 1]) {
    const statement = monthDay(month - offset, cutDay);
    let due = monthDay(month - offset, payDay);
    if (due <= statement) due = monthDay(month - offset + 1, payDay);
    if (+due === +target) matches.push(statement);
  }
  return matches;
}

function activeLoanInstallment(account, number) {
  const {
    loan_principal: principal,
    loan_annual_interest_rate: annualRate,
    loan_term_months: term,
    loan_repayment_method: method,
    loan_quoted_monthly_payment: quoted,
    initial_balance: initial,
  } = account;
  const opening = Math.abs(initial ?? principal);
  if (!Number.isInteger(term) || term > 1200 || number < 1 || number > term ||
      !Number.isFinite(principal) || principal <= 0 || !Number.isFinite(annualRate) || annualRate < 0 ||
      !Number.isFinite(opening) || opening <= 0 || opening > principal ||
      !['equalInstallment', 'equalPrincipal', 'flatRate'].includes(method) ||
      (quoted != null && (!Number.isFinite(quoted) || quoted <= 0 || method === 'equalPrincipal'))) {
    return null;
  }
  let balance = money(opening);
  const midstream = balance < money(principal);
  const rate = annualRate / 1200;
  const flatInterest = money(principal * annualRate / 100 * term / 12);
  const monthlyInterest = money(flatInterest / term);
  const regularPrincipal = money(principal / term);
  const annuity = rate === 0 ? principal / term : principal * rate / (-Math.expm1(-term * Math.log1p(rate)));
  const regularPayment = money(quoted ?? (method === 'flatRate' ? regularPrincipal + monthlyInterest : annuity));
  if (method === 'equalInstallment' && regularPayment <= money(balance * rate) ||
      method === 'flatRate' && regularPayment <= monthlyInterest) return null;

  let assignedInterest = 0;
  let requested = null;
  // Reproduce the date bounds and amounts from calculateLoanAmortization, so
  // a midstream loan with a reduced opening principal can end before its term.
  for (let index = 1; index <= term && balance > 0; index++) {
    let interest = money(balance * rate);
    let principalPart;
    if (method === 'equalInstallment') {
      if (!midstream && quoted != null && index < term && regularPayment >= money(balance + interest)) return null;
      principalPart = index === term ? balance : money(Math.min(balance, regularPayment - interest));
    } else if (method === 'equalPrincipal') {
      principalPart = index === term ? balance : Math.min(balance, regularPrincipal);
    } else {
      const nextPrincipal = quoted == null ? regularPrincipal : money(regularPayment - monthlyInterest);
      const final = index === term || (midstream && nextPrincipal >= balance);
      if (!midstream && quoted != null && index < term && nextPrincipal >= balance) return null;
      interest = final && !midstream ? money(flatInterest - assignedInterest) : monthlyInterest;
      principalPart = final ? balance : Math.min(balance, nextPrincipal);
      assignedInterest = money(assignedInterest + interest);
    }
    balance = money(Math.max(0, balance - principalPart));
    if (index === number) requested = { payment: money(principalPart + interest), principal: principalPart };
  }
  return requested;
}

function loanInstallmentPaid({ account, transactions, byAccount, today, installment, number }) {
  const monthlyLabel = `贷款月供 #${number}`;
  const legacyLabel = `贷款本金 #${number}`;
  const interestLabel = `贷款利息 #${number}`;
  const matched = transactions.filter((item) =>
    item.type === 'transfer' && item.to_account_id === account.id && item.date <= today &&
    (item.description === monthlyLabel || item.description === legacyLabel) &&
    item.currency === account.currency && (item.to_currency ?? item.currency) === account.currency);
  const principal = matched.reduce((total, item) => total + transferIn(item), 0);
  if (principal <= epsilon || principal + epsilon < installment.principal) return false;
  let payment = matched.reduce((total, item) => total + item.amount, 0);
  const legacyInterestIds = new Set();
  for (const item of matched) {
    if (item.description !== legacyLabel || item.amount <= 0) continue;
    for (const expense of byAccount.get(item.account_id) ?? []) {
      if (expense.account_id === item.account_id && expense.type === 'expense' &&
          expense.currency === account.currency && expense.description === interestLabel &&
          +expense.date === +item.date && !legacyInterestIds.has(expense.id)) {
        payment += expense.amount;
        legacyInterestIds.add(expense.id);
      }
    }
  }
  return payment > epsilon && payment + epsilon >= installment.payment;
}

function event(kind, account, target, title, body) {
  const key = createHash('sha256').update(JSON.stringify([kind, account.id, dayKey(target)]))
    .digest('base64url');
  return { key, title, body };
}

function accountName(account) {
  // Limit lock-screen text to a single line. Never include amount, merchant,
  // transaction memo, account reference numbers or other ledger fields.
  const normalized = account.name?.replace(/[\p{Cc}\p{Cf}]/gu, ' ').replace(/\s+/gu, ' ').trim() ?? '';
  return [...normalized].slice(0, 48).join('') || (account.account_type === 'loan' ? '贷款' : '信用卡');
}

/**
 * Compute only today's reminder inputs from a synchronized JSON v3 ledger.
 * The caller owns time-zone scheduling, per-device delivery and deduplication.
 */
export function reminderEvents(snapshot, localDay) {
  const today = parseDay(localDay);
  if (!today || dayKey(today) !== localDay || snapshot?.meta?.notifications_enabled === 'false' ||
      !Array.isArray(snapshot?.accounts)) return [];
  const prefs = readPreferences(snapshot.meta);
  const byAccount = indexTransactions(Array.isArray(snapshot.transactions) ? snapshot.transactions : []);
  const paymentDates = prefs.dueToday ? [today, offsetDays(today, advanceDays)] : [offsetDays(today, advanceDays)];
  const events = [];

  for (const account of snapshot.accounts) {
    if (!account || account.is_active === false || typeof account.id !== 'string') continue;
    const name = accountName(account);
    const transactions = byAccount.get(account.id) ?? [];
    if (account.account_type === 'creditCard') {
      if (!validMonthDay(account.statement_day)) continue;
      if (prefs.statement && +monthDay(monthNumber(today), account.statement_day) === +today) {
        events.push(event('credit-statement', account, today, '信用卡账单结算提醒', `今天是「${name}」的账单结算日，请查看账单。`));
      }
      if (!prefs.repayment || !validMonthDay(account.payment_due_day)) continue;
      for (const target of paymentDates) {
        const [statement] = creditDueStatements(account, target);
        if (!statement || creditBilledBalance(account, transactions, statement, today) <= epsilon) continue;
        const isDueToday = target === today;
        const dueLabel = statement > today ? '预计于' : '将在';
        events.push(event(isDueToday ? 'credit-due' : 'credit-upcoming', account, target,
          isDueToday ? '信用卡今天到期' : '近期信用卡还款提醒',
          isDueToday ? `「${name}」今天到期，请尽快还款。` : `「${name}」${dueLabel} ${dayKey(target)} 到期，请安排还款。`));
      }
    } else if (account.account_type === 'loan' && prefs.loan) {
      const contractStart = parseDay(account.loan_start_date);
      const start = parseDay(account.loan_tracking_start_date) ?? contractStart;
      if (!contractStart || !start || !validMonthDay(account.loan_payment_day)) continue;
      if (balanceAsOf(account, transactions, today) >= -epsilon) continue;
      for (const target of paymentDates) {
        if (+monthDay(monthNumber(target), account.loan_payment_day) !== +target) continue;
        const number = monthNumber(target) - monthNumber(start);
        const installment = activeLoanInstallment(account, number);
        if (!installment || loanInstallmentPaid({ account, transactions, byAccount, today, installment, number })) continue;
        const isDueToday = target === today;
        events.push(event(isDueToday ? 'loan-due' : 'loan-upcoming', account, target,
          isDueToday ? '贷款今天到期' : '近期贷款还款提醒',
          isDueToday ? `请马上缴交「${name}」本期还款。` : `「${name}」将在 ${dayKey(target)} 到期，请安排还款。`));
      }
    }
  }
  return events;
}
