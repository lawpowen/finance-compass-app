const string = (value) => typeof value === 'string';
const number = Number.isFinite;
const integer = Number.isSafeInteger;
const positiveInteger = (value) => Number.isSafeInteger(value) && value > 0;
const currencyUnit = (value) => (value ?? 'MYR').trim().toUpperCase();
export function validMoney(value) {
  if (!Number.isFinite(value)) return false;
  const cents = Math.round(Math.abs(value) * 100);
  return Number.isSafeInteger(cents) && cents / 100 === Math.abs(value);
}
const monthKey = (value) => string(value) && /^\d{4}-(0[1-9]|1[0-2])$/.test(value);
const boolean = (value) => typeof value === 'boolean';
const date = (value) => string(value) &&
  /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?$/.test(value) &&
  Number.isFinite(Date.parse(value));
export function parseCalendarDay(value) {
  if (!string(value) || value.length !== 10 || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value ? parsed : null;
}
const calendarDay = (value) => parseCalendarDay(value) !== null;
const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const enumOf = (...values) => (value) => values.includes(value);
const optional = (check) => (value) => value == null || check(value);
const transactionType = enumOf('income', 'expense', 'transfer', 'adjustment');
const transactionFields = {
  type: transactionType,
  account_id: string,
  amount: number,
  to_account_id: optional(string),
  category_id: optional(string),
  currency: optional(string),
  to_currency: optional(string),
  to_amount: optional(number),
  loan_installment_number: optional(positiveInteger),
  loan_payment_amount: optional(number),
  status: optional(enumOf('planned', 'actual', 'settled')),
  description: optional(string),
  merchant: optional(string),
};

function validInstallment(row, accounts) {
  if (row.loan_installment_number == null) return row.loan_payment_amount == null;
  const source = accounts.get(row.account_id);
  const target = accounts.get(row.to_account_id);
  if (!source || target?.account_type !== 'loan' || source.id === target.id || row.type !== 'transfer') return false;
  const from = currencyUnit(row.currency);
  const to = currencyUnit(row.to_currency ?? row.currency);
  if (from !== currencyUnit(source.currency) || to !== currencyUnit(target.currency)) return false;
  if (from !== to && row.loan_payment_amount == null) return false;
  const payment = row.loan_payment_amount ?? row.amount;
  const principal = row.to_amount;
  return [payment, row.amount, principal].every(validMoney) && (from !== to || payment === row.amount) &&
    payment !== 0 && row.amount !== 0 && Math.sign(payment) === Math.sign(row.amount) &&
    (principal === 0 || Math.sign(principal) === Math.sign(payment)) && Math.abs(principal) <= Math.abs(payment);
}

const schema = {
  accounts: {
    name: string,
    account_type: enumOf('cash', 'bankSaving', 'eWallet', 'creditCard', 'moneyMarketFund',
      'pension', 'stock', 'crypto', 'trading', 'fund', 'loan', 'other'),
    report_group: enumOf('cash', 'credit', 'investment', 'retirement'),
    currency: optional(string),
    initial_balance: optional(number),
    current_balance: optional(number),
    institution: optional(string),
    note: optional(string),
    is_active: optional(boolean),
    credit_limit: optional(number),
    statement_day: optional(integer),
    payment_due_day: optional(integer),
    loan_principal: optional(number),
    loan_annual_interest_rate: optional(number),
    loan_term_months: optional(integer),
    loan_start_date: optional(date),
    loan_tracking_start_date: optional(date),
    loan_payment_day: optional(integer),
    loan_repayment_method: optional(enumOf('equalInstallment', 'equalPrincipal', 'flatRate')),
    loan_quoted_monthly_payment: optional(number),
  },
  categories: {
    name: string,
    type: enumOf('income', 'expense', 'investment', 'transfer'),
    parent_id: optional(string),
    icon_key: optional(string),
    color_value: optional(integer),
    sort_order: optional(integer),
    is_archived: optional(boolean),
  },
  budgets: {
    category_id: string,
    month_key: monthKey,
    amount: number,
    currency: optional(string),
    alert_threshold: optional(number),
    rollover_enabled: optional(boolean),
  },
  transactions: {
    ...transactionFields,
    legacy_loan_part_number: optional(positiveInteger),
    legacy_loan_id: optional(string),
    record_date: optional(date),
    transaction_date: date,
    card_posting_date: optional(calendarDay),
    recurring_rule_id: optional(string),
  },
  asset_snapshots: {
    account_id: string,
    snapshot_date: date,
    market_value: number,
    cost_basis: optional(number),
    cash_balance: optional(number),
    unrealized_pnl: optional(number),
  },
  transaction_templates: {
    ...transactionFields,
    name: optional(string),
    sort_order: optional(integer),
  },
  recurring_transaction_rules: {
    ...transactionFields,
    name: optional(string),
    start_date: date,
    end_date: optional(date),
    interval_months: optional(positiveInteger),
    generated_month_keys: optional((value) => Array.isArray(value) && value.every(monthKey)),
    is_active: optional(boolean),
  },
};

export function validCategoryHierarchy(categories) {
  const byId = new Map(categories.map((row) => [row.id, row]));
  const checked = new Set();
  for (const category of categories) {
    const chain = new Set();
    let current = category;
    while (current && !checked.has(current.id)) {
      if (chain.has(current.id)) return false;
      chain.add(current.id);
      if (current.parent_id == null) break;
      const parent = byId.get(current.parent_id);
      if (!parent || parent.type !== current.type) return false;
      current = parent;
    }
    for (const id of chain) checked.add(id);
  }
  return true;
}

function validCurrencyMeta(meta) {
  try {
    if (meta.currency_priority_json?.trim()) {
      const order = JSON.parse(meta.currency_priority_json);
      if (!Array.isArray(order) || order.some((code) => typeof code !== 'string' || !code.trim())) return false;
    }
    if (!meta.exchange_rates_to_base_json?.trim()) return true;
    const quotes = JSON.parse(meta.exchange_rates_to_base_json);
    if (!object(quotes)) return false;
    const codes = new Set();
    return Object.entries(quotes).every(([key, value]) => {
      const code = key.trim().toUpperCase();
      if (!code || codes.has(code)) return false;
      codes.add(code);
      if (typeof value !== 'number' && (typeof value !== 'string' ||
          !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value.trim()))) return false;
      const quote = Number(value);
      return Number.isFinite(quote) && quote > 0;
    });
  } catch {
    return false;
  }
}

function validRetiredRuleHistory(meta) {
  for (const [key, raw] of Object.entries(meta)) {
    if (key.startsWith('recurring-occurrence/') && !monthKey(raw)) return false;
    if (!key.startsWith('retired-recurring-rule/')) continue;
    try {
      const rule = JSON.parse(raw);
      if (!object(rule) || !string(rule.id) || !rule.id ||
          !Array.isArray(rule.months) || !rule.months.every(monthKey)) return false;
    } catch {
      return false;
    }
  }
  return true;
}

export function validSnapshot(snapshot) {
  if (!object(snapshot) || snapshot.format_version !== 3 || snapshot.schema_version !== 9 ||
      !object(snapshot.meta) || !Object.values(snapshot.meta).every(string) || !validCurrencyMeta(snapshot.meta) ||
      (snapshot.meta.loan_installment_semantics != null && snapshot.meta.loan_installment_semantics !== 'explicit_v1')) return false;
  if (!validRetiredRuleHistory(snapshot.meta)) return false;
  if (Object.keys(snapshot.meta).some((key) => key.startsWith('credit_card_posting_dates/'))) return false;
  const ids = {};
  for (const [section, spec] of Object.entries(schema)) {
    const rows = snapshot[section];
    if (!Array.isArray(rows)) return false;
    const sectionIds = new Set();
    const fields = Object.entries(spec);
    for (const row of rows) {
      if (!object(row) || !string(row.id) || !row.id.trim() || sectionIds.has(row.id) ||
          !fields.every(([name, check]) => check(row[name])) ||
          (section !== 'transactions' && row.card_posting_date != null)) return false;
      sectionIds.add(row.id);
    }
    ids[section] = sectionIds;
  }
  const optionalRef = (set, id) => id == null || set.has(id);
  const categoryRef = (id) => optionalRef(ids.categories, id);
  const accounts = new Map(snapshot.accounts.map((account) => [account.id, account]));
  const moneyRefs = (row) => ids.accounts.has(row.account_id) &&
    optionalRef(ids.accounts, row.to_account_id) && categoryRef(row.category_id) && validInstallment(row, accounts);
  const hasLegacyPart = (row) => row.legacy_loan_part_number != null || row.legacy_loan_id != null;
  const validLegacyPart = (row) => {
    if (!hasLegacyPart(row)) return true;
    const loan = accounts.get(row.legacy_loan_id);
    const source = accounts.get(row.account_id);
    const currency = currencyUnit(row.currency);
    if (row.legacy_loan_part_number == null || row.loan_installment_number != null || loan?.account_type !== 'loan' ||
        row.account_id === loan.id || !validMoney(row.amount) || currency !== currencyUnit(loan.currency) || !source ||
        currency !== currencyUnit(source.currency)) return false;
    return row.type === 'transfer' ? row.to_account_id === loan.id && currencyUnit(row.to_currency ?? row.currency) === currency &&
      (row.to_amount == null || row.to_amount === row.amount)
      : row.type === 'expense' && row.to_account_id == null;
  };
  const budgetKeys = new Set();
  for (const row of snapshot.budgets) {
    const key = `${row.category_id}|${row.month_key}`;
    if (budgetKeys.has(key)) return false;
    budgetKeys.add(key);
  }
  return snapshot.accounts.every((row) => row.account_type !== 'loan' || !row.loan_start_date ||
      !row.loan_tracking_start_date || row.loan_tracking_start_date.slice(0, 10) >= row.loan_start_date.slice(0, 10)) &&
    validCategoryHierarchy(snapshot.categories) &&
    snapshot.budgets.every((row) => ids.categories.has(row.category_id)) &&
    snapshot.transactions.every((row) => moneyRefs(row) && validLegacyPart(row) &&
      (row.card_posting_date == null || (accounts.get(row.account_id).account_type === 'creditCard' &&
        row.card_posting_date >= row.transaction_date.slice(0, 10)))) &&
    snapshot.asset_snapshots.every((row) => ids.accounts.has(row.account_id)) &&
    snapshot.transaction_templates.every((row) => moneyRefs(row) && !hasLegacyPart(row)) &&
    snapshot.recurring_transaction_rules.every((row) => moneyRefs(row) && !hasLegacyPart(row));
}
