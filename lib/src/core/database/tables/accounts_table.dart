import 'package:drift/drift.dart';

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get accountType => text()();
  TextColumn get reportGroup => text()();
  TextColumn get currency => text()();
  RealColumn get initialBalance => real().withDefault(const Constant(0))();
  RealColumn get currentBalance => real()();
  TextColumn get institution => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  RealColumn get creditLimit => real().nullable()();
  IntColumn get statementDay => integer().nullable()();
  IntColumn get paymentDueDay => integer().nullable()();
  RealColumn get loanPrincipal => real().nullable()();
  RealColumn get loanAnnualInterestRate => real().nullable()();
  IntColumn get loanTermMonths => integer().nullable()();
  DateTimeColumn get loanStartDate => dateTime().nullable()();
  DateTimeColumn get loanTrackingStartDate => dateTime().nullable()();
  IntColumn get loanPaymentDay => integer().nullable()();
  TextColumn get loanRepaymentMethod => text().nullable()();
  RealColumn get loanQuotedMonthlyPayment => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
