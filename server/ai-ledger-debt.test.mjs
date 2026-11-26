import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createAiDebtView } from './ai-ledger-debt.mjs';
import { balanceAsOf, debtLedgerIndex, parseDay } from './reminder-events.mjs';

const bank = { id: 'bank', name: 'Bank', account_type: 'bankSaving', currency: 'MYR' };
const card = (id, close, due, balance) => ({ id, name: id, account_type: 'creditCard', currency: 'MYR',
  credit_limit: 5000, statement_day: close, payment_due_day: due, initial_balance: 0, current_balance: balance });
const expense = (id, account_id, amount, transaction_date) => ({ id, type: 'expense', account_id, amount, transaction_date });
const transfer = (id, account_id, to_account_id, amount, transaction_date, extra = {}) =>
  ({ id, type: 'transfer', account_id, to_account_id, amount, transaction_date, ...extra });
function view(accounts, transactions, asOf, meta = { loan_installment_semantics:'explicit_v1' }) {
  const snapshot = { accounts: [...accounts, bank], transactions, meta };
  const index = debtLedgerIndex(snapshot);
  return createAiDebtView(snapshot, { asOf, convert: (value, currency) => currency === 'MYR' ? value : null,
    balanceAt: (id, day) => balanceAsOf(index.accounts.get(id), index.byAccount.get(id) ?? [], parseDay(day)) });
}

test('card-to-PayLater transfer settles the recipient on occurrence, the source on bank posting; cash falls due just once', () => {
  const accounts = [card('Laz', 9, 25, 0), card('UOB', 25, 14, -241.94)];
  const txs = [
    expense('buy', 'Laz', 241.94, '2026-11-09'),
    transfer('refinance', 'UOB', 'Laz', 241.94, '2026-11-25', { card_posting_date: '2026-11-26' }),
  ];
  const before = view(accounts, txs, '2026-11-24');
  assert.equal(before.cards('Laz')[0].billed_balance, 241.94);
  assert.equal(before.pressure30().total_base, 0);
  const [laz, uob] = view(accounts, txs, '2026-11-25').cards();
  assert.equal(laz.billed_balance, 0);
  assert.equal(laz.recent_entries[0].billing_day, '2026-11-25');
  assert.equal(uob.unbilled_balance, 241.94);
  assert.equal(uob.recent_entries[0].statement_date, '2026-12-25');
  assert.equal(uob.statements[0].original_amount, 0);
  assert.equal(uob.next_statement.due_date, '2027-01-14');
  assert.equal(view(accounts, txs, '2026-12-20').pressure30().total_base, 241.94);
});

test('funding counts a scheduled bank payment exactly once even when late; planned refinancing moves debt into the next cycle', () => {
  const accounts = [card('Laz', 9, 25, -100), card('UOB', 25, 14, 0)];
  const bill = expense('buy', 'Laz', 100, '2026-11-03');
  const late = transfer('plan', 'bank', 'Laz', 40, '2026-11-27', { status: 'planned' });
  const funding = view(accounts, [bill, late], '2026-11-20').pressure30();
  assert.equal(funding.total_base, 100);
  assert.deepEqual(funding.items.map((i) => i.amount), [60, 40]);
  const move = { ...late, account_id: 'UOB', amount: 100 };
  assert.equal(view(accounts, [bill, move], '2026-11-20').pressure30().total_base, 0);
});

test('future confirmed within the whole next statement is included; unpriced currency and manual statement override stay explicit', () => {
  const a = { ...card('Laz', 9, 25, -290.44), currency: 'XYZ' };
  const txs = [
    expense('old', 'Laz', 100, '2026-11-03'), transfer('paid', 'bank', 'Laz', 100, '2026-11-25'),
    expense('this-month', 'Laz', 79.56, '2026-11-20'), expense('next-month', 'Laz', 180.88, '2026-12-09'),
    expense('later', 'Laz', 30, '2027-01-04'), {...expense('plan', 'Laz', 500, '2026-12-03'), status:'planned'},
  ];
  const meta = { credit_card_statement_amounts_Laz_json: '{"2026-11-09":123.45}' };
  const result = view([a], txs, '2026-11-25', meta).cards('Laz')[0];
  assert.equal(result.unbilled_balance, 260.44);
  assert.equal(result.committed_outstanding, 290.44);
  assert.equal(result.statements[0].original_amount, 123.45);
  const due = view([a], txs, '2026-12-15', meta).pressure30();
  assert.equal(due.total_base, null);
  assert.deepEqual(due.unpriced_currencies, ['XYZ']);
  assert.equal(due.by_currency[0].amount, 260.44);
});

test('loan settlement uses contract-currency principal and interest, signed reversals, and ignores edited memo text', () => {
  const ledger = JSON.parse(readFileSync(new URL('../test/fixtures/loan_settlement_v3.json', import.meta.url)));
  const loanAt = (day) => view(ledger.accounts, ledger.transactions, day, ledger.meta).loans()[0];
  const paid = loanAt('2026-11-20'), reversed = loanAt('2026-11-23');
  assert.equal(paid.remaining_periods, 1);
  assert.equal(paid.next_installment.number, 2);
  assert.equal(reversed.remaining_periods, 2);
  assert.deepEqual(reversed.next_installment, { number:1, due_date:'2026-11-23', principal:22, interest:0, payment:22 });
  assert.equal(reversed.remaining_principal, 100);
  assert.equal(reversed.remaining_interest, 1);
  // The signed reversal tomorrow reopens November's installment within the
  // horizon even though it was fully covered at the November 20 cutoff.
  assert.equal(view(ledger.accounts, ledger.transactions, '2026-11-20', ledger.meta).pressure30().total_base, 22);
});

test('legacy split principal and interest suppress only their own installment after matching the source and day', () => {
  const loan = { id:'car', name:'Car', account_type:'loan', currency:'MYR', initial_balance:-200, current_balance:-100,
    loan_principal:200, loan_start_date:'2026-10-01', loan_payment_day:25, loan_term_months:2,
    loan_annual_interest_rate:12, loan_repayment_method:'equalPrincipal' };
  const principal = transfer('principal','bank','car',100,'2026-11-22',{description:'贷款本金 #1'});
  const interest = { ...expense('interest','bank',2,'2026-11-22'), description:'贷款利息 #1' };
  const paid = view([loan],[principal,interest],'2026-11-25',{}).loans()[0];
  assert.equal(paid.remaining_periods,1);
  assert.equal(paid.next_installment.payment,101);
  const unmatched = view([loan],[principal,{...interest,transaction_date:'2026-11-21'}],'2026-11-25',{}).loans()[0];
  assert.equal(unmatched.next_installment.payment,102);
});

test('incomplete billing profile explicitly estimates maturity and does not invent statement boundaries', () => {
  const a = { ...card('Card', 10, 20, -75), credit_limit:null };
  const debt = view([a], [], '2026-11-28');
  assert.equal(debt.cards()[0].estimated, true);
  assert.equal(debt.cards()[0].due_date, '2026-12-25');
  assert.equal(debt.cards()[0].next_statement, null);
  assert.equal(debt.pressure30().total_base, 75);
});

test('dated opening and reversal keep older unpaid statements distinct from the latest maturity', () => {
  const a = card('Card', 9, 25, -140);
  const txs = [expense('a', 'Card', 100, '2026-10-01'), expense('b', 'Card', 80, '2026-11-01'),
    transfer('paid', 'bank', 'Card', 60, '2026-11-15'), transfer('undo', 'bank', 'Card', -20, '2026-11-18')];
  const [summary] = view([a], txs, '2026-11-20').cards();
  assert.deepEqual(summary.open_statements.map((s) => [s.due_date, s.amount]), [['2026-10-25',60],['2026-11-25',80]]);
  assert.equal(summary.due_date, '2026-10-25');
  assert.equal(summary.open_total, 140);
  assert.equal(view([a], txs, '2026-11-20').pressure30().total_base, 140);
});
