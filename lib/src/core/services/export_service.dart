import 'dart:typed_data';

import '../data/finance_repository.dart';

/// Exports a single ledger revision using the app's canonical wire formats.
/// Restore operations go through the ledger mutation boundary.
class ExportService {
  const ExportService.fromRepository(this.repository);
  final FinanceRepository repository;

  Future<Map<String, dynamic>> buildJsonSnapshotPayload() =>
      repository.buildJsonSnapshotPayload();
  Future<Uint8List> exportJsonSnapshotBytes() =>
      repository.exportJsonSnapshotBytes();
  Future<String> exportJsonSnapshot([String? targetPath]) =>
      repository.exportJsonSnapshot(targetPath);
  Future<ImportPreview> previewImportJson(String path) =>
      repository.previewImportJson(path);
  Map<String, dynamic> buildAiSummaryPayload(
          {required List<String> monthKeys}) =>
      repository.buildAiSummaryPayload(monthKeys: monthKeys);
  Uint8List exportAiSummaryBytes({required List<String> monthKeys}) =>
      repository.exportAiSummaryBytes(monthKeys: monthKeys);
  Future<String> exportAiSummaryJson(String path,
          {required List<String> monthKeys}) =>
      repository.exportAiSummaryJson(path, monthKeys: monthKeys);
  Uint8List exportFuturePlanningCsvBytes({int months = 24}) =>
      repository.exportFuturePlanningCsvBytes(months: months);
}
