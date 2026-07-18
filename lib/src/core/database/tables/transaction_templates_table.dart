import 'package:drift/drift.dart';

@DataClassName('TransactionTemplateRow')
class TransactionTemplates extends Table {
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
  TextColumn get status => text().withDefault(const Constant('actual'))();
  TextColumn get description => text().nullable()();
  TextColumn get merchant => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
