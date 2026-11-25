import { createHash } from 'node:crypto';
import { parseCalendarDay, validMoney } from './snapshot.mjs';

const advanceDays = 3;
const epsilon = 0.005;
const dayMilliseconds = 86_400_000;

function parseDay(value) {
  const prefix = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}(?=T|$)/.exec(value)?.[0];
  return parseCalendarDay(prefix);
}

const dayKey = (date) => date.toISOString().slice(0, 10);
const offsetDays = (date, days) => new Date(date.valueOf() + days * dayMilliseconds);
const monthNumber = (date) => date.getUTCFullYear() * 12 + date.getUTCMonth();
const validMonthDay = (day) => Number.isInteger(day) && day >= 1 && day <= 31;
const money = (value) => Math.round(value * 100) / 100;
const cents = (value) => Math.sign(value) * Math.round(Math.abs(value) * 100);

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

function indexTransactions(transactions, accounts, legacy) {
  const byAccount = new Map();
  const oldParts = new Map();
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
    if (entry.legacy_loan_id && entry.type === 'expense') add(entry.legacy_loan_id, entry);
    if (!legacy || entry.loan_installment_number != null || entry.legacy_loan_part_number != null ||
        !validMoney(entry.amount)) continue;
    const matched = /^贷款(本金|利息) #([1-9]\d*)$/.exec(entry.description ?? '');
    if (!matched) continue;
    const principal = matched[1] === '本金';
    const source = accounts.get(entry.account_id);
    const target = accounts.get(entry.to_account_id);
    const currency = currencyUnit(entry.currency);
    if (!legacyCashPayer(source, currency)) continue;
    if (principal ? (entry.type !== 'transfer' || target?.account_type !== 'loan' ||
        currency !== currencyUnit(target.currency) || entry.account_id === entry.to_account_id ||
        currencyUnit(entry.to_currency ?? entry.currency) !== currency ||
        (entry.to_amount != null && entry.to_amount !== entry.amount))
      : (entry.type !== 'expense' || entry.to_account_id != null)) continue;
    const key = JSON.stringify([entry.account_id, dayKey(date), entry.status ?? 'actual', currency, matched[2]]);
    const parts = oldParts.get(key) ?? { principal: [], interest: [], number: Number(matched[2]) };
    parts[principal ? 'principal' : 'interest'].push(entry);
    oldParts.set(key, parts);
  }
  for (const parts of oldParts.values()) {
    if (parts.principal.length !== 1 || parts.interest.length !== 1) continue;
    const [principal] = parts.principal;
    const [interest] = parts.interest;
    if (principal.amount !== 0 && interest.amount !== 0 && Math.sign(principal.amount) !== Math.sign(interest.amount)) continue;
    const loanId = principal.to_account_id;
    for (const entry of [principal, interest]) {
      entry.legacy_loan_id = loanId;
      entry.legacy_loan_part_number = parts.number;
    }
    add(loanId, interest);
  }
  return byAccount;
}

const currencyUnit = (value) => (value ?? 'MYR').trim().toUpperCase();

function legacyCashPayer(source, currency) {
  if (!source || currencyUnit(source.currency) !== currency) return false;
  return ['cash', 'bankSaving', 'eWallet'].includes(source.account_type) ||
    (['moneyMarketFund', 'other'].includes(source.account_type) && source.report_group === 'cash');
}

function transferIn(transaction) {
  return transaction.to_amount ?? transaction.amount;
}

// Mirror the old-snapshot importer's ordinary zero-receipt reconciliation.
// Work on copies: a reminder must never change a user's stored snapshot.
function prepareLegacyReceipts(snapshot, accounts, transactions) {
  const candidates = transactions.filter((tx) => tx?.type === 'transfer' && Number.isFinite(tx.amount) && tx.amount !== 0 &&
    tx.to_amount === 0 && tx.status !== 'planned' && tx.account_id !== tx.to_account_id &&
    tx.loan_installment_number == null && tx.legacy_loan_part_number == null &&
    accounts.has(tx.to_account_id) && accounts.get(tx.to_account_id).account_type !== 'loan' &&
    currencyUnit(tx.currency) === currencyUnit(tx.to_currency ?? tx.currency));
  if (!candidates.length) return transactions;
  const normalize = new Set();
  if (snapshot.meta?.investment_snapshot_semantics === 'immutable_v1') {
    // Phase 2 posted both legs when receiving these ordinary transfers.
    for (const tx of candidates) normalize.add(tx);
  } else {
    const observed = new Set((snapshot.asset_snapshots ?? []).map((s) => s.account_id));
    const expected = new Map([...accounts].map(([id, a]) => [id, a.initial_balance ?? 0]));
    const omitted = new Map();
    const payers = new Map();
    for (const tx of transactions) {
      if (!tx || !Number.isFinite(tx.amount) || tx.status === 'planned') continue;
      for (const id of new Set([tx.account_id, tx.to_account_id])) {
        if (expected.has(id)) expected.set(id, expected.get(id) + balanceDelta(id, tx));
      }
    }
    for (const tx of candidates) {
      const id = tx.to_account_id;
      expected.set(id, expected.get(id) + tx.amount);
      omitted.set(id, (omitted.get(id) ?? 0) + tx.amount);
      if (!payers.has(id)) payers.set(id, new Set());
      payers.get(id).add(tx.account_id);
    }
    const reconciles = (id, adjustment) => accounts.has(id) && !observed.has(id) &&
      Math.abs(expected.get(id) - adjustment - accounts.get(id).current_balance) <= 1e-7;
    const accepted = new Set();
    const credits = new Map();
    for (const [id, amount] of omitted) {
      if (![...payers.get(id)].every((payer) => reconciles(payer, 0) || reconciles(payer, omitted.get(payer) ?? 0))) continue;
      if (reconciles(id, 0)) accepted.add(id);
      else if (amount !== 0 && reconciles(id, amount)) {
        accepted.add(id);
        credits.set(id, amount);
      }
    }
    for (const [id, amount] of credits) {
      const a = accounts.get(id);
      accounts.set(id, { ...a, current_balance: a.current_balance + amount });
    }
    for (const tx of candidates) if (accepted.has(tx.to_account_id)) normalize.add(tx);
  }
  return transactions.map((tx) => normalize.has(tx) ? { ...tx, to_amount: null } : tx);
}

function balanceDelta(accountId, transaction) {
  const source = transaction.account_id === accountId;
  if (transaction.type === 'transfer') {
    const incoming = transaction.to_account_id === accountId ? transferIn(transaction) : 0;
    return incoming - (source ? transaction.amount : 0);
  }
  return source ? (transaction.type === 'expense' ? -transaction.amount : transaction.amount) : 0;
}

function balanceAsOf(account, transactions, today) {
  const delta = (item) => balanceDelta(account.id, item);
  if (!Number.isFinite(account.current_balance)) {
    return transactions.reduce(
      (balance, item) => item.date <= today ? balance + delta(item) : balance,
      account.initial_balance ?? 0,
    );
  }
  // Like FinanceRepository.accountBalanceAt, undo future actual or settled
  // transactions that are already reflected in the exported current balance.
  return transactions.reduce(
    (balance, item) => item.date > today ? balance - delta(item) : balance,
    account.current_balance,
  );
}

function creditBilledBalance(account, transactions, statement, today) {
  const lastClosed = (day) => {
    const month = monthNumber(day);
    const cut = monthDay(month, account.statement_day);
    return cut > day ? monthDay(month - 1, account.statement_day) : cut;
  };
  const charges = new Map();
  const payments = [];
  const addCharge = (cut, amount) => charges.set(+cut, (charges.get(+cut) ?? 0) + amount);
  let pendingForStatement = 0;
  let openingDebt = -balanceAsOf(account, transactions, today);
  let firstDay = today;
  for (const item of transactions) {
    if (item.date > today) continue;
    const source = item.account_id === account.id;
    const charge = source ? -balanceDelta(account.id, item) : 0;
    const payment = !source && item.type === 'transfer' && item.to_account_id === account.id ? transferIn(item) : 0;
    if (charge === 0 && payment === 0) continue;
    if (item.date < firstDay) firstDay = item.date;
    openingDebt += payment - charge;
    if (charge !== 0) {
      const billingDate = parseCalendarDay(item.card_posting_date) ?? item.date;
      const month = monthNumber(billingDate);
      const close = monthDay(month, account.statement_day);
      const cut = billingDate <= close ? close : monthDay(month + 1, account.statement_day);
      // Only posted credits can cover other statements. A pending posting may
      // affect the requested upcoming statement's estimated notice.
      addCharge(cut, billingDate <= today ? charge : 0);
      if (billingDate > today && +cut === +statement) pendingForStatement += charge;
    }
    if (payment !== 0) payments.push(item);
  }
  // With no dated statement evidence, retain the existing estimate for a
  // notification sent shortly before the card closes.
  if (!charges.size && !payments.length) return Math.max(0, openingDebt);
  if (openingDebt > 0) addCharge(lastClosed(firstDay), openingDebt);
  let credit = Math.max(0, -openingDebt);
  payments.sort((a, b) => Date.parse(a.transaction_date) - Date.parse(b.transaction_date) ||
    (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  for (const payment of payments) {
    credit += transferIn(payment);
    if (credit < 0) {
      addCharge(lastClosed(payment.date), -credit);
      credit = 0;
    }
  }
  for (const charge of charges.values()) if (charge < 0) credit -= charge;
  for (const [closed, charge] of [...charges].sort(([a], [b]) => a - b)) {
    const debit = Math.max(0, charge);
    if (closed === +statement) return Math.max(0, debit + pendingForStatement - credit);
    credit = Math.max(0, credit - debit);
  }
  return 0;
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

export function activeLoanInstallment(account, number) {
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
  if (method === 'flatRate') return flatInstallment(principal, opening, annualRate, quoted, term, number);
  const regularPrincipal = money(principal / term);
  const annuity = rate === 0 ? principal / term : principal * rate / (-Math.expm1(-term * Math.log1p(rate)));
  const regularPayment = money(quoted ?? annuity);
  if (method === 'equalInstallment' && regularPayment <= money(balance * rate)) return null;

  let requested = null;
  // Reproduce the date bounds and amounts from calculateLoanAmortization, so
  // a midstream loan with a reduced opening principal can end before its term.
  for (let index = 1; index <= term && balance > 0; index++) {
    const interest = money(balance * rate);
    let principalPart;
    if (method === 'equalInstallment') {
      if (!midstream && quoted != null && index < term && regularPayment >= money(balance + interest)) return null;
      principalPart = index === term ? balance : money(Math.min(balance, regularPayment - interest));
    } else {
      principalPart = index === term ? balance : Math.min(balance, regularPrincipal);
    }
    balance = money(Math.max(0, balance - principalPart));
    if (index === number) requested = { payment: money(principalPart + interest), principal: principalPart };
  }
  return requested;
}

// Allocate contract cents by the differences between successive cumulative
// shares. Multiplying only the remainder avoids overflow for long contracts.
function flatPortion(total, term, index) {
  const remainder = total % term;
  return Math.floor(total / term) + Math.floor(index * remainder / term) -
    Math.floor((index - 1) * remainder / term);
}

function flatInstallment(principal, opening, annualRate, quoted, term, number) {
  const contract = cents(principal);
  const interestTotal = cents(principal * annualRate / 100 * term / 12);
  const quote = quoted == null ? null : cents(quoted);
  let balance = cents(opening);
  if (![contract, interestTotal, balance].every(Number.isSafeInteger) ||
      (quote != null && (!Number.isSafeInteger(quote) || quote <= Math.floor(interestTotal / term)))) return null;
  const midstream = balance < contract;
  let requested = null;
  for (let index = 1; index <= term && balance > 0; index++) {
    const interest = flatPortion(interestTotal, term, index);
    const regular = quote == null ? flatPortion(contract, term, index) : quote - interest;
    if (quote != null && !midstream && index < term && regular >= balance) return null;
    const payPrincipal = index === term ? balance : Math.min(balance, regular);
    if (index === number) requested = { payment: (payPrincipal + interest) / 100, principal: payPrincipal / 100 };
    balance -= payPrincipal;
  }
  return requested;
}

function loanInstallmentPaid({ account, accounts, transactions, today, installment, number, legacy }) {
  const monthlyLabel = `贷款月供 #${number}`;
  let paidPrincipal = 0;
  let paidInterest = 0;
  for (const item of transactions) {
    if (item.date > today || item.account_id === account.id) continue;
    if (item.legacy_loan_id === account.id && item.legacy_loan_part_number === number) {
      if (item.type === 'transfer' && item.to_account_id === account.id) paidPrincipal += cents(transferIn(item));
      if (item.type === 'expense') paidInterest += cents(item.amount);
      continue;
    }
    if (item.type !== 'transfer' || item.to_account_id !== account.id) continue;
    const targetCurrency = (item.to_currency ?? item.currency ?? 'MYR').trim().toUpperCase();
    const sourceCurrency = (item.currency ?? 'MYR').trim().toUpperCase();
    if (targetCurrency !== (account.currency ?? 'MYR').trim().toUpperCase()) continue;
    const tagged = item.loan_installment_number != null;
    const oldMonthly = legacy && !tagged && item.description === monthlyLabel &&
      validMoney(item.to_amount) && validMoney(item.amount) && sourceCurrency === targetCurrency &&
      legacyCashPayer(accounts.get(item.account_id), sourceCurrency);
    if ((tagged && item.loan_installment_number === number) || oldMonthly) {
      const payment = item.loan_payment_amount ?? item.amount;
      const principal = item.to_amount;
      if (!Number.isFinite(payment) || !Number.isFinite(principal) || payment === 0 ||
          (principal !== 0 && Math.sign(payment) !== Math.sign(principal)) ||
          Math.abs(principal) > Math.abs(payment)) continue;
      paidPrincipal += cents(principal);
      paidInterest += cents(payment) - cents(principal);
      continue;
    }
  }
  const duePrincipal = cents(installment.principal);
  const dueInterest = cents(installment.payment) - duePrincipal;
  return Math.max(0, paidPrincipal) >= duePrincipal && Math.max(0, paidInterest) >= dueInterest;
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
  const legacy = snapshot.meta?.loan_installment_semantics == null;
  const accounts = new Map(snapshot.accounts.filter((a) => a && typeof a.id === 'string').map((a) => [a.id, a]));
  const rawTransactions = Array.isArray(snapshot.transactions) ? snapshot.transactions : [];
  const transactionsForRead = legacy ? prepareLegacyReceipts(snapshot, accounts, rawTransactions) : rawTransactions;
  const byAccount = indexTransactions(transactionsForRead, accounts, legacy);
  const paymentDates = prefs.dueToday ? [today, offsetDays(today, advanceDays)] : [offsetDays(today, advanceDays)];
  const events = [];

  for (const account of accounts.values()) {
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
        const statement = creditDueStatements(account, target).find(
          (candidate) => creditBilledBalance(account, transactions, candidate, today) >= epsilon,
        );
        if (!statement) continue;
        const isDueToday = target === today;
        const dueLabel = statement > today ? '预计于' : '将在';
        events.push(event(isDueToday ? 'credit-due' : 'credit-upcoming', account, target,
          isDueToday ? '信用卡今天到期' : '近期信用卡还款提醒',
          isDueToday ? `「${name}」今天到期，请尽快还款。` : `「${name}」${dueLabel} ${dayKey(target)} 到期，请安排还款。`));
      }
    } else if (account.account_type === 'loan' && prefs.loan) {
      const contractStart = parseDay(account.loan_start_date);
      const start = parseDay(account.loan_tracking_start_date) ?? contractStart;
      if (!contractStart || !start || start < contractStart || !validMonthDay(account.loan_payment_day)) continue;
      // Old imported ledgers can contain just an already-paid loan balance
      // with no installment records. In a modern ledger principal alone never
      // closes the outstanding interest on a period.
      if (legacy && transactions.length === 0 && balanceAsOf(account, transactions, today) >= -epsilon) continue;
      for (const target of paymentDates) {
        if (+monthDay(monthNumber(target), account.loan_payment_day) !== +target) continue;
        const number = monthNumber(target) - monthNumber(start);
        const installment = activeLoanInstallment(account, number);
        if (!installment || loanInstallmentPaid({ account, accounts, transactions, today, installment, number, legacy })) continue;
        const isDueToday = target === today;
        events.push(event(isDueToday ? 'loan-due' : 'loan-upcoming', account, target,
          isDueToday ? '贷款今天到期' : '近期贷款还款提醒',
          isDueToday ? `请马上缴交「${name}」本期还款。` : `「${name}」将在 ${dayKey(target)} 到期，请安排还款。`));
      }
    }
  }
  return events;
}
