import 'package:drift/drift.dart';

import '../models/account.dart';

/// Repairs pre-enum ledger data before any reader constructs an Account.
/// Invoked inside the database's beforeOpen transaction.
Future<void> repairLegacyAccountReportGroups(DatabaseConnectionUser db) async {
  const key = 'account_report_groups_v1';
  final version = await db.customSelect(
    'SELECT value FROM app_meta WHERE key = ?',
    variables: [Variable.withString(key)],
  ).getSingleOrNull();
  if (version?.read<String>('value') == 'true') return;

  final valid = ReportGroup.values.map((group) => group.name).toList();
  final placeholders = List.filled(valid.length, '?').join(',');
  final rows = await db
      .customSelect(
        'SELECT id, account_type FROM accounts '
        'WHERE report_group IS NULL OR report_group NOT IN ($placeholders)',
        variables: valid.map(Variable.withString).toList(),
      )
      .get();
  for (final row in rows) {
    final type = AccountType.values.byName(row.read<String>('account_type'));
    await db.customStatement(
      'UPDATE accounts SET report_group = ? WHERE id = ?',
      [allowedReportGroups(type).first.name, row.read<String>('id')],
    );
  }
  await db.customStatement(
    'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
    [key, 'true'],
  );
}
