import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/platform/local_file_io.dart' as local_files;
import '../../core/providers/mutations/export_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../shared/compass_ui.dart';

Future<bool> pickPreviewAndImportLedger(
  BuildContext context,
  WidgetRef ref,
) async {
  final picked = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    withData: true,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  final file = picked?.files.single;
  if (file == null || !context.mounted) return false;
  final path = kIsWeb ? null : file.path;
  // Preview and import use the same bytes, even if the file changes on disk.
  final bytes = file.bytes ??
      (path == null || path.isEmpty
          ? null
          : await local_files.readFileBytes(path));
  if (bytes == null || !context.mounted) return false;

  final mutations = ref.read(exportMutationsProvider.notifier);
  final syncing = ref.read(ledgerSyncSessionProvider) != null;
  final preview = await mutations.previewImportBytes(bytes);
  if (!context.mounted) return false;
  final total = preview.accounts +
      preview.categories +
      preview.budgets +
      preview.transactions +
      preview.assetSnapshots;
  if (total == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这个 JSON 没有可导入的 Finance Compass 数据。')),
    );
    return false;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _ImportLedgerPreview(preview: preview, syncing: syncing),
  );
  if (confirmed != true || !context.mounted) return false;

  await mutations.importJsonBytes(
    bytes,
    detachUnresolvedCategoryParents: preview.hasUnresolvedCategoryParents,
  );
  return true;
}

class _ImportLedgerPreview extends StatelessWidget {
  const _ImportLedgerPreview({required this.preview, required this.syncing});

  final ImportPreview preview;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final repairs = preview.categoryParentRepairs;
    final unresolved = preview.hasUnresolvedCategoryParents;
    return AlertDialog(
      title: const Text('导入预览'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            syncing
                ? '确认会替换同步账本，并更新其他设备。请先下载当前完整 JSON。'
                : kIsWeb
                    ? '确认会替换当前账本。请先下载完整 JSON，作为恢复备份。'
                    : '确认后会先建立恢复点，再用此文件替换当前资料。',
          ),
          const SizedBox(height: 12),
          Text('导出时间 ${preview.exportedAt ?? '-'}'),
          Text('账户 ${preview.accounts}'),
          Text('类别 ${preview.categories}'),
          Text('预算 ${preview.budgets}'),
          Text('交易 ${preview.transactions}'),
          Text('资产快照 ${preview.assetSnapshots}'),
          if (repairs.isNotEmpty) ...[
            const SizedBox(height: 12),
            CompassHelpHeading(
              title:
                  Text('上级分类修复', style: Theme.of(context).textTheme.titleSmall),
              label: '上级分类修复',
              message: '旧备份中找不到上级分类编号时，会尝试匹配同类型的唯一同名分类，且确保关联不会形成循环。'
                  '无法匹配的分类会成为顶层分类，其交易和预算会保留。',
            ),
            if (unresolved) const Text('无法确认的上级关系会移除。分类及其交易和预算会保留。'),
            for (final repair in repairs)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  repair.parentName == null
                      ? '「${repair.categoryName}」保留为顶层，原上级为「${repair.originalParent}」'
                      : '「${repair.categoryName}」将归入「${repair.parentName}」',
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(repairs.isEmpty ? '确认导入' : '修复并导入'),
        ),
      ],
    );
  }
}
