import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { activeLoanInstallment, reminderEvents } from './reminder-events.mjs';
import { validSnapshot } from './snapshot.mjs';

test('Flutter settlement fixture suppresses a paid bill and reopens a reversed payment', () => {
  const ledger = JSON.parse(readFileSync(
    new URL('../test/fixtures/loan_settlement_v3.json', import.meta.url), 'utf8',
  ));
  assert.equal(validSnapshot(ledger), true);
  assert.deepEqual(reminderEvents(ledger, '2026-11-20'), []);
  assert.deepEqual(reminderEvents(ledger, '2026-11-23').map((e) => e.title), ['贷款今天到期']);
});

const car = {
  id: 'loan-car',
  name: '车贷',
  account_type: 'loan',
  is_active: true,
  currency: 'MYR',
  initial_balance: -1200,
  current_balance: -1200,
  loan_principal: 1200,
  loan_annual_interest_rate: 0,
  loan_term_months: 12,
  loan_start_date: '2026-09-05T00:00:00.000',
  loan_tracking_start_date: '2026-10-30T00:00:00.000',
  loan_payment_day: 23,
  loan_repayment_method: 'equalPrincipal',
};
const card = {
  id: 'card',
  name: '信用卡A',
  account_type: 'creditCard',
  is_active: true,
  currency: 'MYR',
  credit_limit: 1000,
  statement_day: 28,
  payment_due_day: 23,
  initial_balance: 0,
  current_balance: -100,
};
const wallet = { id: 'wallet', account_type: 'cash', report_group: 'cash', currency: 'MYR',
  initial_balance: 500, current_balance: 500 };
const snapshot = (accounts, transactions = [], meta = {}) => ({
  format_version: 3, accounts: [...accounts, wallet], transactions, meta,
});
const loanPayment = (overrides = {}) => ({
  id: 'transfer-1',
  type: 'transfer',
  account_id: 'wallet',
  to_account_id: car.id,
  description: '贷款月供 #1',
  amount: 100,
  to_amount: 100,
  currency: 'MYR',
  to_currency: 'MYR',
  status: 'actual',
  transaction_date: '2026-11-19T12:55:00.000',
  ...overrides,
});

test('car loan reminds three days ahead and repeats on the configured 23rd', () => {
  const ledger = snapshot([{ ...car, name: '  车\n贷\u202e　A  ' }]);
  assert.deepEqual(reminderEvents(ledger, '2026-10-23'), []);
  assert.deepEqual(reminderEvents(ledger, '2026-11-19'), []);
  assert.deepEqual(reminderEvents(ledger, '2026-11-21'), []);
  const [early] = reminderEvents(ledger, '2026-11-20');
  const [today] = reminderEvents(ledger, '2026-11-23');
  assert.deepEqual(early, {
    key: early.key,
    title: '近期贷款还款提醒',
    body: '「车 贷 A」将在 2026-11-23 到期，请安排还款。',
  });
  assert.deepEqual(today, {
    key: today.key,
    title: '贷款今天到期',
    body: '请马上缴交「车 贷 A」本期还款。',
  });
  assert.notEqual(early.key, today.key);
  assert.equal(reminderEvents(ledger, '2026-11-23')[0].key, today.key);
  assert.notEqual(reminderEvents(ledger, '2026-12-23')[0].key, today.key);
  assert.deepEqual(reminderEvents(ledger, '2027-11-23'), []);
});

test('loan dates clamp into short months and can cross from three days before into a new year', () => {
  const loan = { ...car, loan_tracking_start_date: null, loan_payment_day: 31 };
  assert.equal(reminderEvents(snapshot([loan]), '2027-02-25')[0].title, '近期贷款还款提醒');
  assert.equal(reminderEvents(snapshot([loan]), '2027-02-28')[0].title, '贷款今天到期');
  assert.deepEqual(reminderEvents(snapshot([loan]), '2027-02-30'), []);
  const newYear = {
    ...car,
    loan_start_date: '2026-12-02',
    loan_tracking_start_date: null,
    loan_payment_day: 2,
  };
  assert.equal(reminderEvents(snapshot([newYear]), '2026-12-30')[0].body,
    '「车贷」将在 2027-01-02 到期，请安排还款。');
});

test('loan reminders stop at the shortened midstream payoff horizon', () => {
  // Mirrors calculateLoanAmortization: 300 opening principal on a 1200
  // equal-principal contract with 12 installments leaves 3 remaining here.
  const loan = { ...car, initial_balance: -300, current_balance: -300 };
  assert.equal(reminderEvents(snapshot([loan]), '2027-01-23')[0].title, '贷款今天到期');
  assert.deepEqual(reminderEvents(snapshot([loan]), '2027-02-23'), []);
  assert.deepEqual(reminderEvents(snapshot([{ ...loan, current_balance: 0 }]), '2027-01-23'), []);
});

test('full structured actual or settled loan payments suppress reminders, partial and planned payments do not', () => {
  const loan = { ...car, current_balance: -1100 };
  for (const status of ['actual', 'settled']) {
    const paid = snapshot([loan], [loanPayment({ status })]);
    assert.deepEqual(reminderEvents(paid, '2026-11-20'), []);
    assert.deepEqual(reminderEvents(paid, '2026-11-23'), []);
    assert.equal(reminderEvents(paid, '2026-12-23').length, 1);
  }

  for (const transaction of [
    loanPayment({ status: 'planned' }),
    loanPayment({ amount: 50, to_amount: 50 }),
    loanPayment({ description: '普通转账' }),
    loanPayment({ transaction_date: '2026-11-24' }),
  ]) {
    assert.equal(reminderEvents(snapshot([loan], [transaction]), '2026-11-23').length, 1);
  }
  const reversed = loanPayment({ id: 'reversal', amount: -100, to_amount: -100 });
  assert.equal(reminderEvents(snapshot([car], [loanPayment(), reversed]), '2026-11-23').length, 1);
});

test('legacy principal and interest matched by date and source count as full loan payment', () => {
  const loan = { ...car, loan_annual_interest_rate: 12, current_balance: -1100 };
  const principal = loanPayment({ description: '贷款本金 #1' });
  const interest = {
    id: 'interest-1',
    type: 'expense', account_id: 'wallet', amount: 12,
    currency: 'MYR', status: 'actual', description: '贷款利息 #1',
    transaction_date: principal.transaction_date,
  };
  assert.equal(reminderEvents(snapshot([loan], [principal]), '2026-11-23').length, 1);
  assert.deepEqual(reminderEvents(snapshot([loan], [principal, interest]), '2026-11-23'), []);
});

test('configured credit card closes on the clamped calendar day and belongs to the correct payment month', () => {
  const short = { ...card, statement_day: 31, payment_due_day: 6 };
  const ledger = snapshot([short]);
  assert.equal(reminderEvents(ledger, '2027-02-28')[0].title, '信用卡账单结算提醒');
  assert.equal(reminderEvents(ledger, '2027-03-03')[0].body,
    '「信用卡A」将在 2027-03-06 到期，请安排还款。');
  assert.equal(reminderEvents(ledger, '2027-03-06')[0].title, '信用卡今天到期');
  assert.deepEqual(reminderEvents(ledger, '2027-02-06').map((event) => event.title), ['信用卡今天到期']);
  const sameMonth = snapshot([{ ...card, statement_day: 5 }]);
  assert.equal(reminderEvents(sameMonth, '2026-11-20')[0].title, '近期信用卡还款提醒');
  assert.equal(reminderEvents(sameMonth, '2026-11-23')[0].title, '信用卡今天到期');
  assert.equal(reminderEvents(snapshot([{ ...card, credit_limit: null, payment_due_day: null }]), '2026-11-28')[0].title,
    '信用卡账单结算提醒');
});

test('a due date within three days of closing still gets an estimated advance reminder', () => {
  const shortCycle = { ...card, statement_day: 25, payment_due_day: 27 };
  assert.equal(reminderEvents(snapshot([shortCycle]), '2026-11-24')[0].body,
    '「信用卡A」预计于 2026-11-27 到期，请安排还款。');
  assert.equal(reminderEvents(snapshot([shortCycle]), '2026-11-27')[0].title,
    '信用卡今天到期');
  assert.deepEqual(reminderEvents(snapshot([{ ...shortCycle, current_balance: 0 }]), '2026-11-24'), []);
});

test('credit reminders use ledger balance and only account for occurred entries', () => {
  // FinanceRepository.accountBalanceAt rewinds actual rows after the cutoff.
  // calculateCreditCardBilling then subtracts unbilled debt after the statement.
  const futureCharge = {
    id: 'expense-1',
    account_id: card.id, type: 'expense', amount: 200, currency: 'MYR',
    status: 'actual', transaction_date: '2026-11-27',
  };
  const nextCycleCharge = { ...futureCharge, transaction_date: '2026-11-15' };
  assert.deepEqual(reminderEvents(snapshot([{ ...card, current_balance: -200 }], [nextCycleCharge]), '2026-11-23'), []);
  assert.equal(reminderEvents(snapshot([{ ...card, current_balance: -300 }], [futureCharge]), '2026-11-23').length, 1);
  const payment = loanPayment({ to_account_id: card.id, amount: 100, to_amount: 0 });
  const phase2 = { investment_snapshot_semantics: 'immutable_v1' };
  const paid = snapshot([{ ...card, current_balance: 0 }], [payment], phase2);
  assert.deepEqual(reminderEvents(paid, '2026-11-23'), []);
  const futurePayment = loanPayment({ ...payment, transaction_date: '2026-11-24' });
  assert.equal(reminderEvents(snapshot([{ ...card, current_balance: 0 }], [futurePayment], phase2), '2026-11-23').length, 1);
});

test('reminder preferences and inactive accounts suppress all applicable events', () => {
  assert.deepEqual(reminderEvents(snapshot([card, car], [], { notifications_enabled: 'false' }), '2026-11-23'), []);
  const meta = { notification_preferences_json: '[true,false,true,true,true,false,false]' };
  const optional = snapshot([card, car], [], meta);
  assert.deepEqual(reminderEvents(optional, '2026-11-20').map((item) => item.title),
    ['近期信用卡还款提醒', '近期贷款还款提醒']);
  assert.deepEqual(reminderEvents(optional, '2026-11-23'), []);
  assert.deepEqual(reminderEvents(optional, '2026-11-28'), []);
  assert.deepEqual(reminderEvents(snapshot([car], [], { loan_payment_push_enabled: 'false' }), '2026-11-23'), []);
  assert.deepEqual(reminderEvents(snapshot([{ ...card, is_active: false }, { ...car, is_active: false }]), '2026-11-23'), []);
  assert.deepEqual(reminderEvents(null, '2026-11-23'), []);
  assert.deepEqual(reminderEvents(snapshot([car]), '2026-11-23T10:00:00.000Z'), []);
});

const explicit = { loan_installment_semantics: 'explicit_v1' };

test('card due reminders distinguish preserved zero receipts from full ordinary repayments', () => {
  const oldCard = { ...card, initial_balance: -100, current_balance: -100 };
  const payment = { ...loanPayment(), to_account_id: card.id, description: 'ordinary', to_amount: 0 };
  const due = (bill, tx, meta, payer) => reminderEvents({ accounts: [bill, payer], transactions: [tx], meta },
    '2026-11-23').length;
  const paidFrom = { ...wallet, current_balance: 400 };
  assert.equal(due(oldCard, payment, explicit, paidFrom), 1);
  assert.equal(due({ ...oldCard, current_balance: 0 }, { ...payment, to_amount: null }, explicit, paidFrom), 0);
  // An old cached target debit can be repaired if the source actually debited the transfer.
  assert.equal(due(oldCard, payment, {}, paidFrom), 0);
  assert.equal(due(oldCard, payment, {}, wallet), 1, 'unexplained old source balance does not prove a credit');
});

test('installments settle contract-currency principal and interest independently after signed reversals', () => {
  const loan = { ...car, loan_annual_interest_rate: 12 };
  const payment = loanPayment({
    description: 'edited', loan_installment_number: 1,
    currency: 'USD', amount: 28, loan_payment_amount: 112, to_amount: 100,
  });
  const reversal = { ...payment, id: 'reverse-interest', amount: -3, loan_payment_amount: -12, to_amount: 0 };
  const partial = { ...payment, id: 'partial', amount: 2, loan_payment_amount: 8, to_amount: 0 };
  const occurs = (rows) => reminderEvents(snapshot([loan], rows, explicit), '2026-11-23').length;
  assert.equal(occurs([payment]), 0);
  assert.equal(occurs([payment, reversal]), 1);
  assert.equal(occurs([payment, reversal, partial]), 1);
  assert.equal(occurs([payment, reversal, { ...partial, loan_payment_amount: 12 }]), 0);
  assert.equal(occurs([{ ...payment, to_amount: 105 }]), 1, 'extra principal cannot cover unpaid interest');
  assert.equal(occurs([loanPayment({ amount: 112 })]), 1, 'new ordinary transfers have no installment identity');
  assert.equal(occurs([{ ...payment, status: 'planned' }]), 1);
  assert.equal(occurs([{ ...payment, transaction_date: '2026-11-24' }]), 1);
});

test('zero-principal interest installments and explicit split halves can clear a payment', () => {
  const small = { ...car, loan_term_months: 360, initial_balance: -1, current_balance: -1,
    loan_principal: 1, loan_annual_interest_rate: 12 };
  const interestOnly = loanPayment({ amount: .01, to_amount: 0, loan_installment_number: 1, description: '' });
  assert.equal(reminderEvents(snapshot([small], [interestOnly], explicit), '2026-11-23').length, 0);
  const loan = { ...car, loan_annual_interest_rate: 12 };
  const linked = { legacy_loan_part_number: 1, legacy_loan_id: loan.id };
  const principal = loanPayment({ ...linked, description: 'changed principal memo' });
  const interest = { ...linked, id: 'interest', type: 'expense', account_id: 'wallet',
    currency: 'MYR', amount: 12, description: 'changed interest memo', transaction_date: '2026-11-20' };
  assert.equal(reminderEvents(snapshot([loan], [principal, interest], explicit), '2026-11-23').length, 0);
  assert.equal(reminderEvents(snapshot([loan], [principal], explicit), '2026-11-23').length, 1);
  const fakePrincipal = loanPayment({ description: '贷款本金 #1' });
  const fakeInterest = { ...interest, legacy_loan_part_number: null, legacy_loan_id: null,
    transaction_date: fakePrincipal.transaction_date, description: '贷款利息 #1' };
  assert.equal(reminderEvents(snapshot([loan], [fakePrincipal, fakeInterest], explicit), '2026-11-23').length, 1);
});

test('flat rates distribute integer cents through the last contracted month', () => {
  const flat = { ...car, loan_repayment_method: 'flatRate', loan_term_months: 600,
    loan_principal: 1000, initial_balance: -1000 };
  const schedule = Array.from({ length: 600 }, (_, i) => activeLoanInstallment(flat, i + 1));
  const cent = (value) => Math.round(value * 100);
  assert.deepEqual(schedule.slice(0, 3).map((p) => cent(p.principal)), [166, 167, 167]);
  assert.equal(cent(schedule.at(-1).principal), 167);
  assert.equal(schedule.reduce((sum, row) => sum + cent(row.principal), 0), 100000);
  const fraction = { ...flat, loan_principal: 1000.01, initial_balance: -1000.01, loan_annual_interest_rate: 3.875 };
  const fractional = Array.from({ length: 600 }, (_, i) => activeLoanInstallment(fraction, i + 1));
  assert.equal(fractional.reduce((sum, row) => sum + cent(row.principal), 0), 100001);
  assert.equal(fractional.reduce((sum, row) => sum + cent(row.payment) - cent(row.principal), 0), 193752);
  const midstream = { ...flat, initial_balance: -3.33 };
  assert.equal(cent(activeLoanInstallment(midstream, 1).principal) + cent(activeLoanInstallment(midstream, 2).principal), 333);
  assert.equal(activeLoanInstallment(midstream, 3), null);
});

test('old overdue credit is not reissued as a new monthly due and refunds cover current debt', () => {
  const overdue = { ...card, statement_day: 10, payment_due_day: 20, current_balance: -100 };
  const charge = { id: 'march', account_id: card.id, currency: 'MYR', amount: 100, type: 'expense',
    status: 'actual', transaction_date: '2026-03-08' };
  assert.equal(reminderEvents(snapshot([overdue], [charge]), '2026-03-20').length, 1);
  assert.equal(reminderEvents(snapshot([overdue], [charge]), '2026-04-20').length, 0);
  const april = { ...charge, id: 'april', transaction_date: '2026-04-08', amount: 50 };
  const refund = { ...april, type: 'adjustment', amount: 50, id: 'credit' };
  assert.equal(reminderEvents(snapshot([overdue], [charge, april, refund]), '2026-04-20').length, 0);
});

test('short February and March closes can both be payable on March 31', () => {
  const account = { ...card, statement_day: 30, payment_due_day: 31 };
  const february = { id: 'feb', account_id: card.id, type: 'expense', amount: 100, currency: 'MYR',
    transaction_date: '2027-02-15', status: 'actual' };
  assert.equal(reminderEvents(snapshot([account], [february]), '2027-03-31')[0].title, '信用卡今天到期');
});
