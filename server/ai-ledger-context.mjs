import { createAiLedgerTools, sanitizeLedgerText } from './ai-ledger-tools.mjs';
import { createAiDebtView } from './ai-ledger-debt.mjs';
import { debtLedgerIndex } from './reminder-events.mjs';
import { parseCalendarDay, validCategoryHierarchy } from './snapshot.mjs';

const dayOf = (value) => value?.slice(0, 10);
const monthOf = (value) => value?.slice(0, 7);
const unit = (value) => String(value ?? 'MYR').trim().toUpperCase();
const money = (value) => value == null || !Number.isFinite(value) ? null : Number(value.toFixed(2));
const monthIndex = (key) => Number(key.slice(0, 4)) * 12 + Number(key.slice(5, 7)) - 1;
const monthKey = (index) => String(Math.floor(index / 12)).padStart(4, '0') + '-' + String(index % 12 + 1).padStart(2, '0');
const shown = (rows, limit) => ({ total_count: rows.length, items: rows.slice(0, limit) });
function pushGroup(map, key, value) {
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(value);
}
function parsed(raw, fallback) {
  try { return JSON.parse(raw); } catch { return fallback; }
}

// Matches normalizedExchangeRatesToBase / readCurrencyQuotes. Stored rates
// already quote the selected base. Only the built-in bridge is MYR-relative.
function exchangeBook(meta) {
  const order = parsed(meta.currency_priority_json, []);
  const base = unit(Array.isArray(order) ? order.find((s) => typeof s === 'string' && s.trim()) : null);
  const defaults = { MYR: 1, USD: 4.7, CNY: 0.65, TWD: 0.14 };
  const explicit = meta.exchange_rates_to_base_json?.trim() ? parsed(meta.exchange_rates_to_base_json, null) : {};
  const quotes = new Map([[base, 1]]);
  const invalid = new Set();
  if (explicit && typeof explicit === 'object' && !Array.isArray(explicit)) {
    const seen = new Set();
    for (const [key, value] of Object.entries(explicit)) {
      const code = unit(key);
      const rate = Number(value);
      if (!code || seen.has(code) || !Number.isFinite(rate) || rate <= 0) invalid.add(code);
      else quotes.set(code, rate);
      seen.add(code);
    }
    for (const code of invalid) quotes.delete(code);
    quotes.set(base, 1);
    const bridgeCode = Object.keys(defaults).find((code) => quotes.has(code));
    const bridge = quotes.get('MYR') ?? (Object.hasOwn(defaults, base) ? 1 / defaults[base] :
      (bridgeCode ? quotes.get(bridgeCode) / defaults[bridgeCode] : null));
    for (const [code, value] of Object.entries(defaults)) {
      if (bridge && !invalid.has(code) && !quotes.has(code)) quotes.set(code, value * bridge);
    }
  }
  return { base, convert(amount, currency) {
    const result = amount * (quotes.get(unit(currency)) ?? NaN);
    return Number.isFinite(result) ? result : null;
  } };
}

function accountGroup(account) {
  switch (account?.account_type) {
    case 'cash': case 'bankSaving': case 'eWallet': return 'cash';
    case 'loan': case 'creditCard': return 'credit';
    case 'pension': return 'retirement';
    case 'moneyMarketFund': case 'other':
      if (account.report_group === 'cash') return 'cash';
      break;
  }
  return account?.report_group === 'retirement' ? 'retirement' : 'investment';
}

// Occurrence and posting use their ledger calendar day (same as reminder-events).
// Within a day an observation supersedes all movements through its microsecond.
function clockKey(timestamp) {
  const time = /T(\d\d:\d\d:\d\d)(?:\.(\d+))?/.exec(timestamp);
  return dayOf(timestamp) + 'T' + (time?.[1] ?? '00:00:00') + '.' + (time?.[2] ?? '').padEnd(6, '0').slice(0, 6);
}
function upperBound(rows, key, at) {
  let low = 0, high = rows.length;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    if (rows[mid][key] <= at) low = mid + 1;
    else high = mid;
  }
  return low;
}
function valuationBook(snapshot, accounts) {
  const movements = new Map(), observations = new Map();
  for (const tx of snapshot.transactions) {
    if (tx.status === 'planned') continue;
    const time = clockKey(tx.transaction_date);
    const debit = tx.type === 'transfer' || tx.type === 'expense';
    pushGroup(movements, tx.account_id, {time, delta: debit ? -tx.amount : tx.amount});
    if (tx.type === 'transfer') pushGroup(movements, tx.to_account_id, {time, delta: tx.to_amount ?? tx.amount});
  }
  for (const rows of movements.values()) {
    rows.sort((a,b) => a.time.localeCompare(b.time));
  }
  for (const row of snapshot.asset_snapshots ?? []) {
    pushGroup(observations, row.account_id, {time: clockKey(row.snapshot_date), id: row.id, value: row.market_value});
  }
  for (const rows of observations.values()) {
    rows.sort((a,b) => a.time.localeCompare(b.time) || Buffer.compare(Buffer.from(a.id),Buffer.from(b.id)));
  }
  return (id, date) => {
    const account = accounts.get(id);
    if (!account || (account.account_type === 'loan' && date < dayOf(account.loan_start_date))) return 0;
    const cutoff = date + 'T23:59:59.999999';
    const moves = movements.get(id) ?? [], anchors = observations.get(id) ?? [];
    const end = upperBound(moves, 'time', cutoff);
    const anchor = anchors[upperBound(anchors, 'time', cutoff) - 1];
    if (anchors.length || ['investment','retirement'].includes(accountGroup(account))) {
      let balance = anchor?.value ?? account.initial_balance ?? 0;
      const start = anchor ? upperBound(moves, 'time', anchor.time) : 0;
      for (let i = start; i < end; i++) balance += moves[i].delta;
      return balance;
    }
    let balance = account.current_balance ?? 0;
    for (let i = moves.length - 1; i >= end; i--) balance -= moves[i].delta;
    return balance;
  };
}

function createBudgetQuery(snapshot, categories, asOf, convert, categoryPath) {
  const rules = new Map(), use = new Map(), history = new Map();
  for (const row of snapshot.budgets ?? []) {
    pushGroup(rules, row.category_id, {month: monthIndex(row.month_key), amount: convert(row.amount, row.currency),
      native: row.amount, currency: unit(row.currency), rollover: row.rollover_enabled === true});
  }
  for (const list of rules.values()) list.sort((a,b) => a.month - b.month);
  const ownership = new Map();
  function budgetOwner(id, month) {
    if (!ownership.has(month)) ownership.set(month, new Map());
    const cache = ownership.get(month);
    const path = [];
    while (id && !cache.has(id) && (rules.get(id)?.[0]?.month ?? Infinity) > month) {
      path.push(id);
      id = categories.get(id)?.parent_id;
    }
    const owner = cache.has(id) ? cache.get(id) : id;
    for (const node of path) cache.set(node, owner);
    return owner;
  }
  for (const tx of snapshot.transactions) {
    if (tx.type !== 'expense') continue;
    const month = monthIndex(tx.transaction_date);
    const id = budgetOwner(tx.category_id, month);
    if (!id) continue;
    if (!use.has(id)) use.set(id, new Map());
    const months = use.get(id);
    if (!months.has(month)) months.set(month, {actual: 0, planned: 0, future: 0, missing: new Set()});
    const row = months.get(month);
    const bucket = tx.status === 'planned' ? 'planned' : dayOf(tx.transaction_date) > asOf ? 'future' : 'actual';
    const value = convert(tx.amount, tx.currency);
    if (value == null) row.missing.add(bucket);
    else row[bucket] += value;
  }
  // Sparse sums allow inherited budgets to span empty years without replaying
  // every intervening month. Only confirmed spend affects incoming rollover.
  for (const [id, months] of use) {
    let sum = 0, unknown = 0;
    for (const [month, row] of [...months].sort((a,b) => a[0] - b[0])) {
      sum += row.actual + row.future;
      unknown += Number(row.missing.has('actual') || row.missing.has('future'));
      pushGroup(history, id, {month, sum, unknown});
    }
  }
  return (month) => {
    const rows = [];
    let totalLimit = 0, totalActual = 0, complete = true;
    for (const [id,list] of rules) {
      let i = upperBound(list, 'month', month) - 1;
      if (i < 0) continue;
      const rule = list[i];
      let end = month, limit = rule.amount;
      // Walk price/switch changes, not calendar months.
      i = upperBound(list, 'month', month - 1) - 1;
      while (i >= 0 && list[i].rollover) {
        const span = list[i--];
        limit = limit == null || span.amount == null ? null : limit + (end - span.month) * span.amount;
        end = span.month;
      }
      const past = history.get(id) ?? [];
      const prev = past[upperBound(past, 'month', month - 1) - 1];
      const before = past[upperBound(past, 'month', end - 1) - 1];
      if ((prev?.unknown ?? 0) !== (before?.unknown ?? 0)) limit = null;
      if (limit != null) limit -= (prev?.sum ?? 0) - (before?.sum ?? 0);
      const row = use.get(id)?.get(month);
      const actual = row?.missing.has('actual') ? null : row?.actual ?? 0;
      const future = row?.missing.has('future') ? null : row?.future ?? 0;
      const planned = row?.missing.has('planned') ? null : row?.planned ?? 0;
      const all = limit != null && actual != null && future != null && planned != null;
      const remaining = actual != null && limit != null ? limit - actual : null;
      totalLimit += limit ?? 0;
      totalActual += row?.actual ?? 0;
      complete &&= all;
      rows.push({category: categoryPath(id), original_amount:rule.native, currency:sanitizeLedgerText(rule.currency),
        effective_budget: money(limit), actual_spent: money(actual), confirmed_future: money(future),
        planned: money(planned), remaining: money(remaining), remaining_after_commitments: all ? money(remaining - future - planned) : null});
    }
    rows.sort((a,b) => (a.remaining ?? Infinity) - (b.remaining ?? Infinity));
    return {...shown(rows, 12), over_budget_count: rows.filter(r => r.remaining != null && r.remaining < 0).length,
      valuation_complete: complete, priced_effective_budget: money(totalLimit), priced_actual_spent: money(totalActual)};
  };
}

function recentActual(transactions, asOf, project) {
  const latest = [];
  let count = 0;
  for (const tx of transactions) {
    if (tx.status === 'planned' || dayOf(tx.transaction_date) > asOf) continue;
    count++;
    const time = clockKey(tx.transaction_date);
    const last = latest.at(-1);
    if (latest.length === 30 && time < last.time) continue;
    const slot = latest.findIndex(item => time > item.time || (time === item.time && tx.id > item.tx.id));
    latest.splice(slot === -1 ? latest.length : slot, 0, {time, tx});
    if (latest.length > 30) latest.pop();
  }
  return {total_count: count, items: latest.map(item => project(item.tx))};
}

export function createAiLedgerContext(snapshot, {asOf} = {}) {
  // An authenticated account at revision zero has no saved snapshot yet.
  const emptyLedger = snapshot == null;
  snapshot ??= {meta:{}, accounts:[], categories:[], transactions:[]};
  // Stored revisions can predate the upload-time hierarchy check.
  if (!validCategoryHierarchy(snapshot.categories)) throw new TypeError('Invalid saved category hierarchy');
  if (!asOf) {
    const now = new Date();
    asOf = new Date(now.valueOf() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  }
  if (asOf instanceof Date) asOf = asOf.toISOString().slice(0, 10);
  if (!parseCalendarDay(asOf)) throw new TypeError('Invalid ledger as-of day');
  const {base: baseCurrency, convert} = exchangeBook(snapshot.meta ?? {});
  const index = debtLedgerIndex(snapshot);
  const accounts = index.accounts;
  // Legacy backups can contain a provable missing receipt. Balances, cash flow,
  // the statement lens and transaction search must all see the same correction.
  if (index.legacy) snapshot = {...snapshot, accounts: [...accounts.values()], transactions: index.rows};
  const categories = new Map(snapshot.categories.map(c => [c.id,c]));
  const balanceAt = valuationBook(snapshot, accounts);
  const debt = createAiDebtView(snapshot, {asOf, convert, balanceAt, index});
  const paths = new Map();
  for (const category of categories.values()) {
    const branch = [];
    let node = category;
    while (node && !paths.has(node.id)) {
      branch.push(node);
      node = categories.get(node.parent_id);
    }
    let parent = paths.get(node?.id);
    for (const child of branch.reverse()) {
      const name = sanitizeLedgerText(child.name);
      const depth = (parent?.depth ?? 0) + 1;
      const root = parent?.root ?? name;
      const path = depth > 4 ? [root, '…', parent.name, name].join(' / ') :
        parent ? parent.path + ' / ' + name : name;
      parent = {root, name, depth, path};
      paths.set(child.id, parent);
    }
  }
  const categoryPath = (id) => paths.get(id)?.path ?? '未分类';
  const childrenFirst = [...categories.keys()].sort((a,b) => paths.get(b).depth - paths.get(a).depth);
  const budget = createBudgetQuery(snapshot, categories, asOf, convert, categoryPath);
  const prices = (list) => [...new Set(list.filter(code => convert(1,code) == null).map(code => sanitizeLedgerText(unit(code))))].sort();
  const goalsData = parsed(snapshot.meta?.asset_goals_json, null);
  const legacyTarget = Number(snapshot.meta?.asset_goal_amount);
  const targets = Array.isArray(goalsData) ? goalsData : legacyTarget > 0 ?
    [{name:'资产目标',target_amount:legacyTarget,currency:baseCurrency}] : [];
  const units = new Set([...snapshot.accounts, ...(snapshot.budgets ?? []), ...targets].filter(Boolean).map(row => unit(row.currency)));
  for (const list of [snapshot.transactions,snapshot.transaction_templates,snapshot.recurring_transaction_rules]) {
    for (const row of list ?? []) {
      units.add(unit(row.currency));
      if (row.type === 'transfer' && row.to_currency) units.add(unit(row.to_currency));
    }
  }
  const unpriced = prices([...units]);
  function balanceSheet(date) {
    const assets = {cash:0, investment:0, retirement:0};
    const overdrafts = {cash:0, investment:0, retirement:0};
    let cardDebt = 0, cardCredit = 0, loanDebt = 0, loanCredit = 0;
    const missing = [];
    for (const account of accounts.values()) {
      const value = convert(balanceAt(account.id,date), account.currency);
      if (value == null) { missing.push(account.currency); continue; }
      if (account.account_type === 'creditCard') {
        cardDebt += Math.max(0, -value); cardCredit += Math.max(0, value);
      } else if (account.account_type === 'loan') {
        loanDebt += Math.max(0, -value); loanCredit += Math.max(0, value);
      } else {
        const group = accountGroup(account);
        assets[group] += Math.max(0, value); overdrafts[group] += Math.max(0, -value);
      }
    }
    const total = Object.values(assets).reduce((a,b) => a+b, 0) + cardCredit + loanCredit;
    const liabilities = Object.values(overdrafts).reduce((a,b) => a+b, 0) + cardDebt + loanDebt;
    return {as_of:date, valuation_complete: !missing.length, unpriced_currencies: prices(missing).slice(0,24),
      cash:money(assets.cash), investment:money(assets.investment), retirement:money(assets.retirement),
      overdrafts:Object.fromEntries(Object.entries(overdrafts).map(([k,v])=>[k,money(v)])),
      card_debt:money(cardDebt), loan_debt:money(loanDebt), card_overpayment:money(cardCredit), loan_overpayment:money(loanCredit),
      assets:money(total), liabilities:money(liabilities), net_worth:money(total - liabilities)};
  }
  function goals() {
    let value = 0, valued = true;
    for (const account of accounts.values()) {
      if (accountGroup(account) === 'credit') continue;
      const converted = convert(balanceAt(account.id,asOf), account.currency);
      value += converted ?? 0;
      valued &&= converted != null;
    }
    const rows = [];
    for (const goal of targets) {
      if (!goal || !(goal.target_amount > 0) || !Number.isFinite(goal.target_amount)) continue;
      const currency = unit(goal.currency ?? baseCurrency);
      const target = convert(goal.target_amount, currency);
      rows.push({name:sanitizeLedgerText(goal.name ?? '资产目标'), currency:sanitizeLedgerText(currency),
        target_amount:goal.target_amount, target_base:money(target), current_noncredit_assets:valued ? money(value) : null,
        progress_percent:valued && target > 0 ? money(100 * value / target) : null,
        reached:valued && target != null ? value >= target - target * 1e-14 : null});
    }
    return shown(rows,20);
  }
  const byMonth = new Map(), creditByMonth = new Map();
  const actual = (tx) => tx.status !== 'planned' && dayOf(tx.transaction_date) <= asOf;
  function recordCredit(accountId, date, amount, currency, side) {
    if (accounts.get(accountId)?.account_type !== 'creditCard' || dayOf(date) > asOf) return;
    const key = monthOf(date);
    if (!creditByMonth.has(key)) creditByMonth.set(key, {charges:0, credits:0, missing:new Set()});
    const totals = creditByMonth.get(key);
    const value = convert(amount,currency);
    if (value == null) totals.missing.add(currency);
    else totals[side] += value;
  }
  for (const tx of snapshot.transactions) {
    pushGroup(byMonth, monthOf(tx.transaction_date), tx);
    if (!actual(tx)) continue;
    const posting = tx.card_posting_date ?? tx.transaction_date;
    if (tx.type === 'transfer' || tx.type === 'expense') {
      const self = tx.type === 'transfer' && tx.to_account_id === tx.account_id;
      recordCredit(tx.account_id,posting,tx.amount,tx.currency,'charges');
      if (self) recordCredit(tx.account_id,posting,-(tx.to_amount ?? tx.amount),tx.to_currency ?? tx.currency,'charges');
    } else {
      recordCredit(tx.account_id,posting,tx.amount,tx.currency,'credits');
    }
    if (tx.type === 'transfer' && tx.to_account_id !== tx.account_id) {
      recordCredit(tx.to_account_id,tx.transaction_date,tx.to_amount ?? tx.amount,tx.to_currency ?? tx.currency,'credits');
    }
  }
  function monthFlows(key) {
    let income = 0, expense = 0, cashIn = 0, cashOut = 0;
    const missing = [];
    for (const tx of byMonth.get(key) ?? []) {
      if (!actual(tx)) continue;
      const amount = convert(tx.amount, tx.currency);
      const srcCash = accountGroup(accounts.get(tx.account_id)) === 'cash';
      if (amount == null && (srcCash || tx.type === 'income' || tx.type === 'expense')) missing.push(tx.currency);
      if (tx.type === 'income') income += amount ?? 0;
      if (tx.type === 'expense') expense += amount ?? 0;
      let delta = srcCash ? (amount ?? 0) * (['transfer','expense'].includes(tx.type) ? -1 : 1) : 0;
      if (tx.type === 'transfer' && accountGroup(accounts.get(tx.to_account_id)) === 'cash') {
        const currency = tx.to_currency ?? tx.currency;
        const incoming = convert(tx.to_amount ?? tx.amount, currency);
        if (incoming == null) missing.push(currency);
        delta += incoming ?? 0;
      }
      cashIn += Math.max(0, delta); cashOut += Math.max(0, -delta);
    }
    return {month:key, income:money(income), consumption:money(expense), net_savings:money(income-expense),
      cash_in:money(cashIn), cash_out:money(cashOut), cash_net:money(cashIn-cashOut),
      valuation_complete: !missing.length, unpriced_currencies:prices(missing).slice(0,24)};
  }
  function monthlyOverview(key) {
    const card = creditByMonth.get(key);
    return {...monthFlows(key), base_currency:sanitizeLedgerText(baseCurrency), as_of:asOf,
      posted_card_charges:money(card?.charges ?? 0), posted_card_credits:money(card?.credits ?? 0),
      credit_unpriced_currencies:prices([...(card?.missing ?? [])]).slice(0,24),
      budgets:budget(monthIndex(key))};
  }
  function categoryBreakdown(startMonth,endMonth,type,limit) {
    const buckets = new Map();
    function bucket(id) {
      if (!buckets.has(id)) buckets.set(id, {direct_amount:0, subtree_amount:0, subtree_count:0, unpriced:new Set()});
      return buckets.get(id);
    }
    let total = 0, count = 0;
    const missing = new Set();
    for (const [month,items] of byMonth) {
      if (month < startMonth || month > endMonth) continue;
      for (const tx of items) {
        if (tx.type !== type || !actual(tx)) continue;
        count++;
        const value = convert(tx.amount,tx.currency);
        if (value == null) missing.add(tx.currency);
        total += value ?? 0;
        const row = bucket(categories.has(tx.category_id) ? tx.category_id : null);
        row.direct_amount += value ?? 0;
        row.subtree_amount += value ?? 0;
        row.subtree_count++;
        if (value == null) row.unpriced.add(tx.currency);
      }
    }
    for (const id of childrenFirst) {
      const row = buckets.get(id), parentId = categories.get(id).parent_id;
      if (!row || !parentId) continue;
      const parent = bucket(parentId);
      parent.subtree_amount += row.subtree_amount;
      parent.subtree_count += row.subtree_count;
      for (const code of row.unpriced) parent.unpriced.add(code);
    }
    const ranked = [...buckets].sort((a,b) => b[1].subtree_amount - a[1].subtree_amount);
    return {type, start_month:startMonth, end_month:endMonth, as_of:asOf, base_currency:sanitizeLedgerText(baseCurrency),
      count, total_amount:money(total), unpriced_currencies:prices([...missing]).slice(0,24), total_categories:ranked.length,
      items: ranked.slice(0,limit).map(([id,row])=>({category:categoryPath(id), direct_amount:money(row.direct_amount),
        subtree_amount:money(row.subtree_amount), count:row.subtree_count, unpriced_currencies:prices([...row.unpriced]).slice(0,24)}))};
  }
  function transactionRow(tx) {
    const row = {date:dayOf(tx.transaction_date), type:tx.type, status:tx.status ?? 'actual',
      account:sanitizeLedgerText(accounts.get(tx.account_id)?.name), category:categoryPath(tx.category_id),
      currency:sanitizeLedgerText(unit(tx.currency)), amount:tx.amount, base_amount:money(convert(tx.amount,tx.currency))};
    if (tx.type === 'transfer') {
      row.to_account = sanitizeLedgerText(accounts.get(tx.to_account_id)?.name);
      row.to_amount = tx.to_amount ?? tx.amount; row.to_currency = sanitizeLedgerText(unit(tx.to_currency ?? tx.currency));
    }
    if (tx.card_posting_date) row.card_posting_date = tx.card_posting_date;
    if (tx.merchant) row.merchant = sanitizeLedgerText(tx.merchant);
    if (tx.description) row.description = sanitizeLedgerText(tx.description);
    return row;
  }
  const current = monthIndex(asOf);
  const currentKey = monthKey(current);
  const today = parseCalendarDay(asOf);
  const nextMonth = new Date(today);
  nextMonth.setUTCDate(1);
  nextMonth.setUTCMonth(nextMonth.getUTCMonth()+1);
  nextMonth.setUTCDate(0);
  const cards = debt.cards();
  const compactCards = cards.slice(0,20).map(card => ({
    name:card.name, currency:card.currency, statement_day:card.statement_day, payment_due_day:card.payment_due_day,
    billed_balance:card.billed_balance, due_date:card.due_date, unbilled_balance:card.unbilled_balance,
    estimated:card.estimated, is_active:card.is_active, outstanding:card.outstanding,
    all_open_statement_total:card.open_total ?? card.billed_balance, committed_outstanding:card.committed_outstanding}));
  const sheet = balanceSheet(asOf);
  const pressure = debt.pressure30();
  const cashValued = [...accounts.values()].every(a => accountGroup(a) !== 'cash' || convert(1,a.currency) != null);
  const cashAvailable = cashValued ? money(sheet.cash - sheet.overdrafts.cash) : null;
  const summary = {
    as_of:asOf, has_saved_ledger:!emptyLedger, month_elapsed_ratio:Number((today.getUTCDate()/nextMonth.getUTCDate()).toFixed(4)),
    base_currency:sanitizeLedgerText(baseCurrency), unpriced_currencies:unpriced.slice(0,24), unpriced_currency_count:unpriced.length,
    valuation_scope:'金额合计仅含已估值项目。流水按交易日截至今日日终，已确认未来与预计另列。分类排名含子项，小计不可相加。',
    balance_sheet:sheet, credit_cards:{total_count:cards.length,items:compactCards},
    current_month:monthlyOverview(currentKey), previous_month:monthFlows(monthKey(current-1)),
    six_month_trend:Array.from({length:6},(_,i) => monthFlows(monthKey(current-5+i))),
    expense_categories:categoryBreakdown(currentKey,currentKey,'expense',10),
    repayment_pressure_30d:{...pressure, available_cash_base:cashAvailable,
      cash_after_repayments_only: cashAvailable == null || pressure.total_base == null ? null : money(cashAvailable - pressure.total_base)},
    goals:goals(),
    recent_actual:recentActual(snapshot.transactions, asOf, transactionRow)
  };
  const tools = createAiLedgerTools({snapshot,asOf,baseCurrency,monthlyOverview,categoryBreakdown,categoryPath,transactionRow,convert,debt,goals});
  return {summary,...tools};
}
