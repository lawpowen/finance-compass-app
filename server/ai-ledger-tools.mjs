import { parseCalendarDay } from './snapshot.mjs';

// Only projected fields belong in model messages. Treat their labels as plain data,
// including labels originating in old backups with arbitrary Unicode content.
export function sanitizeLedgerText(value, maxLen = 48) {
  if (typeof value !== 'string' || !Number.isSafeInteger(maxLen) || maxLen <= 0) return '';
  const text = value.slice(0, 4096).normalize('NFKC')
    .replace(/[\p{Cf}]/gu, '')
    .replace(/[\p{Cc}\s]+/gu, ' ')
    .replace(/<\|[^<>]*?(?:\|>|$)|<[^<>]*>/gu, ' ')
    .replace(/\[\s*\/?\s*(?:system|assistant|user|developer|tool|inst|im_start|im_end)\s*\]/giu, ' ')
    .replace(/[<>]/gu, ' ')
    .replace(/\s+/gu, ' ').trim();
  return [...text].slice(0, Math.min(maxLen, 256)).join('').trimEnd();
}

const dataStart = '<user_ledger_data>';
const dataEnd = '</user_ledger_data>';
const toolByteLimit = 24 * 1024;
const summaryByteLimit = 48 * 1024;

function encodedData(value) {
  return JSON.stringify(value).replace(/[<>&\u2028\u2029]/gu, (ch) =>
    '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
}

function boundedData(value, byteLimit) {
  const pending = [];
  let omitted = 0;
  function project(input, depth, field) {
    if (input == null) return null;
    if (typeof input === 'string') {
      // Category paths consist of individually shortened names. Leave room
      // for their parents and for the server's static valuation explanation.
      return sanitizeLedgerText(input, field === 'category' || field === 'valuation_scope' ? 256 : 48);
    }
    if (typeof input === 'number') return Number.isFinite(input) ? input : null;
    if (typeof input === 'boolean') return input;
    if (depth >= 14) {
      omitted++;
      return null;
    }
    if (Array.isArray(input)) {
      const rows = [];
      if (input.length) pending.push({ input, rows, depth });
      return rows;
    }
    const keys = Object.keys(input);
    omitted += Math.max(0, keys.length - 96);
    return Object.fromEntries(keys.slice(0, 96).map((key) =>
      [sanitizeLedgerText(key), project(input[key], depth + 1, key)]));
  }

  const result = project(value, 0);
  // Fill collections round-robin. Charge escaped UTF-8 bytes before inserting
  // a row so large snapshots never require a second unbounded JSON string.
  let remaining = byteLimit - 128 - Buffer.byteLength(encodedData(result));
  if (remaining < 0) return { truncated: true, detail_unavailable: true };
  for (let i = 0; i < pending.length; i++) {
    const group = pending[i];
    const index = group.rows.length;
    const queueEnd = pending.length;
    const entry = project(group.input[index], group.depth + 1);
    const cost = Buffer.byteLength(encodedData(entry)) + Number(index > 0);
    if (cost > remaining) {
      pending.length = queueEnd;
      omitted += group.input.length - index;
      continue;
    }
    group.rows.push(entry);
    remaining -= cost;
    if (index + 1 < Math.min(group.input.length, 64)) pending.push(group);
    else omitted += group.input.length - group.rows.length;
  }
  if (!omitted) return result;
  return { ...(Array.isArray(result) ? { rows: result } : result), truncated: true, omitted_items: omitted };
}

export function ledgerDataEnvelope(value) {
  const payload = boundedData(value, summaryByteLimit - dataStart.length - dataEnd.length);
  return dataStart + encodedData(payload) + dataEnd;
}

const month = { type: 'string', pattern: '^\\d{4}-(0[1-9]|1[0-2])$' };
const day = { type: 'string', format: 'date' };
const label = { type: 'string', minLength: 1, maxLength: 96 };
const limit = { type: 'integer', minimum: 1, maximum: 30 };
const choice = (...values) => ({ type: 'string', enum: values });

function tool(name, description, properties, required = []) {
  return {
    type: 'function',
    function: { name, description, parameters: { type: 'object', properties, required, additionalProperties: false } },
  };
}

const tools = [
  tool('get_monthly_overview', '按 YYYY-MM 查询消费发生、现金收付、信用负债和预算执行。',
    { month_key: month }, ['month_key']),
  tool('get_category_breakdown', '按起止月份（含两端，最多120个月）查询父子分类收入或支出排行，默认为支出。',
    { start_month: month, end_month: month, type: choice('income', 'expense'), limit }, ['start_month', 'end_month']),
  tool('search_transactions', '按发生日期（含两端）检索流水，最多返回30条，汇总包含全部命中。账户含转入和转出，父分类含子孙，未指定状态时各状态分别汇总。',
    { start_date: day, end_date: day, account_name: label, category_name: { ...label, maxLength: 256 },
      type: choice('income', 'expense', 'transfer', 'adjustment'), status: choice('actual', 'settled', 'planned'),
      keyword: label, limit }),
  tool('get_credit_card_statements', '按卡片名称查询信用卡或 PayLater 最近1至12期账单、未还金额和近期明细。省略名称查询全部。',
    { account_name: label, month_count: { type: 'integer', minimum: 1, maximum: 12 } }),
  tool('get_loan_and_goals_status', '查询贷款剩余本金、期数和下期月供，以及资产目标进度。', {}),
];
const parameters = new Map(tools.map(({ function: fn }) => [fn.name, fn.parameters]));

function checkArgs(name, args) {
  const schema = parameters.get(name);
  if (!schema || !args || typeof args !== 'object' || Array.isArray(args) ||
      ![null, Object.prototype].includes(Object.getPrototypeOf(args))) throw new TypeError('无效的只读查询');
  if (schema.required.some((key) => !Object.hasOwn(args, key))) throw new TypeError('查询参数不完整');
  for (const [key, value] of Object.entries(args)) {
    if (!Object.hasOwn(schema.properties, key)) throw new TypeError('查询参数不受支持');
    const field = schema.properties[key];
    if (field.type === 'integer') {
      if (!Number.isSafeInteger(value) || value < field.minimum || value > field.maximum) {
        throw new RangeError('查询数量超出范围');
      }
    } else if (typeof value !== 'string' || !value.trim() || value.length > 2 * (field.maxLength ?? 96) ||
               (field.maxLength && [...value].length > field.maxLength) || (field.enum && !field.enum.includes(value)) ||
               (field.pattern && !new RegExp(field.pattern, 'u').test(value)) ||
               (field.format === 'date' && !parseCalendarDay(value))) {
      throw new TypeError('查询字段格式无效');
    }
  }
  if (args.start_date > args.end_date) throw new RangeError('起止日期无效');
  if (args.start_month) {
    const ordinal = (key) => Number(key.slice(0, 4)) * 12 + Number(key.slice(5));
    const span = ordinal(args.end_month) - ordinal(args.start_month);
    if (span < 0 || span >= 120) throw new RangeError('查询月份范围无效');
  }
}

const folded = (value) => sanitizeLedgerText(value, 96).toLowerCase();
function nameMatches(name, query) {
  return folded(name) === query || folded(sanitizeLedgerText(name)) === query;
}

function categoryMatches(view, query) {
  const matches = new Set();
  const children = new Map();
  for (const cat of view.snapshot.categories) {
    if (nameMatches(cat.name, query) || (query.includes(' / ') &&
      sanitizeLedgerText(view.categoryPath(cat.id), 256).toLowerCase() === query)) matches.add(cat.id);
    if (!children.has(cat.parent_id)) children.set(cat.parent_id, []);
    children.get(cat.parent_id).push(cat.id);
  }
  // Set iteration visits newly added descendants once, even for archived rows.
  for (const id of matches) for (const child of children.get(id) ?? []) matches.add(child);
  return matches;
}

const rounded = (amount) => Number(amount.toFixed(2));

function searchTransactions(view, args) {
  const { accounts = [], transactions = [] } = view.snapshot;
  const accountQuery = folded(args.account_name);
  const categoryQuery = sanitizeLedgerText(args.category_name, 256).toLowerCase();
  const keyword = folded(args.keyword);
  // If a supplied filter consists only of stripped markup it must not widen to all records.
  if ((args.account_name && !accountQuery) || (args.category_name && !categoryQuery) || (args.keyword && !keyword)) {
    throw new TypeError('查询文字无效');
  }
  const accountIds = accountQuery && new Set(accounts.filter((item) => nameMatches(item.name, accountQuery)).map((item) => item.id));
  const categoryIds = categoryQuery && categoryMatches(view, categoryQuery);
  if (categoryQuery === '未分类') categoryIds.add(null);
  const latest = [];
  const rowLimit = args.limit ?? 30;
  let count = 0;
  const totals = new Map();
  for (const tx of transactions) {
    const date = tx.transaction_date.slice(0, 10);
    const status = tx.status ?? 'actual';
    if ((args.start_date && date < args.start_date) || (args.end_date && date > args.end_date) ||
        (args.type && args.type !== tx.type) || (args.status && args.status !== status) ||
        (accountIds && !accountIds.has(tx.account_id) && !accountIds.has(tx.to_account_id)) ||
        (categoryIds && !categoryIds.has(tx.category_id ?? null))) continue;
    const row = keyword ? view.transactionRow(tx) : null;
    if (row && ![row.merchant, row.description, row.account, row.to_account, row.category]
      .some((text) => folded(text).includes(keyword))) continue;
    count++;
    if (latest.length < rowLimit || latest.at(-1).at < tx.transaction_date) {
      const earlier = latest.findIndex((entry) => entry.at < tx.transaction_date);
      latest.splice(earlier < 0 ? latest.length : earlier, 0, { at: tx.transaction_date, row, tx });
      if (latest.length > rowLimit) latest.pop();
    }
    const key = tx.type + '/' + status;
    if (!totals.has(key)) totals.set(key, { type: tx.type, status, count: 0, priced_count: 0, priced_base_subtotal: 0, missing: new Map() });
    const total = totals.get(key);
    total.count++;
    const converted = view.convert(tx.amount, tx.currency);
    if (Number.isFinite(converted)) {
      total.priced_count++;
      total.priced_base_subtotal += converted;
    } else {
      const unit = (tx.currency ?? 'MYR').trim().toUpperCase();
      total.missing.set(unit, (total.missing.get(unit) ?? 0) + tx.amount);
    }
  }
  return {
    total_count: count,
    base_currency: view.baseCurrency,
    totals_by_type_and_status: [...totals.values()].map((total) => ({
      type: total.type, status: total.status, count: total.count, priced_count: total.priced_count,
      priced_base_subtotal: rounded(total.priced_base_subtotal),
      base_total: total.priced_count === total.count ? rounded(total.priced_base_subtotal) : null,
      unpriced_amounts: [...total.missing].map(([currency, amount]) => ({ currency, amount: rounded(amount) })),
    })),
    rows: latest.map((m) => m.row ?? view.transactionRow(m.tx)),
  };
}

// The view closes over the one authorized snapshot for this request. The model
// can choose filters, never a store, account ID, endpoint or other data source.
export function createAiLedgerTools(view) {
  return { tools, execute(name, args) {
    checkArgs(name, args);
    let result;
    switch (name) {
      case 'get_monthly_overview':
        result = view.monthlyOverview(args.month_key);
        break;
      case 'get_category_breakdown':
        result = view.categoryBreakdown(args.start_month, args.end_month, args.type ?? 'expense', args.limit ?? 10);
        break;
      case 'search_transactions':
        result = searchTransactions(view, args);
        break;
      case 'get_credit_card_statements':
        if (args.account_name && !folded(args.account_name)) throw new TypeError('查询文字无效');
        result = view.debt.cards(args.account_name?.trim(), args.month_count ?? 1);
        break;
      case 'get_loan_and_goals_status':
        result = { loans: view.debt.loans(), goals: view.goals() };
        break;
    }
    return boundedData(result, toolByteLimit);
  } };
}
