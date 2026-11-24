const string = (value) => typeof value === 'string';
const number = Number.isFinite;
const integer = Number.isSafeInteger;
const boolean = (value) => typeof value === 'boolean';
const date = (value) => string(value) &&
  /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?$/.test(value) &&
  Number.isFinite(Date.parse(value));
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
  status: optional(enumOf('planned', 'actual', 'settled')),
  description: optional(string),
  merchant: optional(string),
};

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
    month_key: string,
    amount: number,
    currency: optional(string),
    alert_threshold: optional(number),
    rollover_enabled: optional(boolean),
  },
  transactions: {
    ...transactionFields,
    record_date: optional(date),
    transaction_date: date,
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
    interval_months: optional(integer),
    generated_month_keys: optional((value) => Array.isArray(value) && value.every(string)),
    is_active: optional(boolean),
  },
};

export function validSnapshot(snapshot) {
  if (!object(snapshot) || snapshot.format_version !== 3 || snapshot.schema_version !== 9 ||
      !object(snapshot.meta) || !Object.values(snapshot.meta).every(string)) return false;
  const ids = {};
  for (const [section, spec] of Object.entries(schema)) {
    const rows = snapshot[section];
    if (!Array.isArray(rows)) return false;
    const sectionIds = new Set();
    const fields = Object.entries(spec);
    for (const row of rows) {
      if (!object(row) || !string(row.id) || !row.id.trim() || sectionIds.has(row.id) ||
          !fields.every(([name, check]) => check(row[name]))) return false;
      sectionIds.add(row.id);
    }
    ids[section] = sectionIds;
  }
  const optionalRef = (set, id) => id == null || set.has(id);
  const categoryRef = (id) => optionalRef(ids.categories, id);
  const moneyRefs = (row) => ids.accounts.has(row.account_id) &&
    optionalRef(ids.accounts, row.to_account_id) && categoryRef(row.category_id);
  return snapshot.categories.every((row) => categoryRef(row.parent_id)) &&
    snapshot.budgets.every((row) => ids.categories.has(row.category_id)) &&
    snapshot.transactions.every(moneyRefs) &&
    snapshot.asset_snapshots.every((row) => ids.accounts.has(row.account_id)) &&
    snapshot.transaction_templates.every(moneyRefs) &&
    snapshot.recurring_transaction_rules.every(moneyRefs);
}
