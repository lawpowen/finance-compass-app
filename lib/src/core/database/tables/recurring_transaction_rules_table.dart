import 'package:drift/drift.dart';

@DataClassName('RecurringTransactionRuleRow')
class RecurringTransactionRules extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get accountId => text()();
  TextColumn get toAccountId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get currency => text()();
  RealColumn get toAmount => real().nullable()();
  TextColumn get toCurrency => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  IntColumn get intervalMonths => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('actual'))();
  TextColumn get description => text().nullable()();
  TextColumn get merchant => text().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get generatedMonthKeysJson =>
      text().withDefault(const Constant('[]'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
