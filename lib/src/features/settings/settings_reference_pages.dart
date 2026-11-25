import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/finance_repository.dart';
import '../../core/providers/mutations/export_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/services/ai_analysis_service.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/settings/app_theme_style.dart';
import '../../core/sync/ledger_sync.dart';
import '../../core/sync/push_notifications.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/month_range.dart';
import '../categories/category_manage_screen.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_donut.dart';
import '../transactions/transaction_automation_pages.dart';
import 'import_ledger_dialog.dart';
import 'settings_screen.dart';

class AccountSyncPage extends ConsumerStatefulWidget {
  const AccountSyncPage({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<AccountSyncPage> createState() => _AccountSyncPageState();
}

class _AccountSyncPageState extends ConsumerState<AccountSyncPage> {
  @override
  Widget build(BuildContext context) {
    final ledger =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    if (ref.watch(ledgerSyncSessionProvider) != null) {
      return _SettingsDetailShell(
        title: '账户与同步',
        children: [
          const ListTile(
            leading: Icon(Icons.cloud_done_outlined),
            title: Text('已登录同步账本'),
          ),
          CompassSettingsRow(
            icon: Icons.download_outlined,
            title: '备份当前账本',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BackupRestorePage(repository: ledger),
              ),
            ),
          ),
        ],
      );
    }
    return _buildLocal(context, ledger);
  }

  Widget _buildLocal(BuildContext context, FinanceRepository ledger) =>
      _SettingsDetailShell(
        title: '账户与同步',
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFF367B76),
                child: Text('L', style: TextStyle(fontSize: 25)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本地模式', style: Theme.of(context).textTheme.titleLarge),
                    Text('${ledger.transactions.length} 条交易仅保存在此设备',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          CompassPrimaryButton(
            label: '备份当前数据',
            icon: Icons.cloud_upload_outlined,
            outlined: true,
            color: FinanceColors.compassTeal,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BackupRestorePage(repository: ledger),
              ),
            ),
          ),
        ],
      );
}

class CurrencyDisplayPage extends ConsumerStatefulWidget {
  const CurrencyDisplayPage({
    super.key,
    required this.repository,
    required this.settingsController,
  });
  final FinanceRepository repository;
  final AppSettingsController settingsController;

  @override
  ConsumerState<CurrencyDisplayPage> createState() =>
      _CurrencyDisplayPageState();
}

class _CurrencyDisplayPageState extends ConsumerState<CurrencyDisplayPage> {
  int? _symbolDraft;
  int? _separatorDraft;

  String _previewMoney(
      double value, String currency, int symbol, int separator) {
    final parts = value.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => separator == 1 ? ' ' : ',',
    );
    final prefix = symbol == 0 ? currencyLabel(currency) : currency;
    return '$prefix $grouped${separator == 1 ? ',' : '.'}${parts.last}';
  }

  void _openFullSettings() {
    final ledger =
        ref.read(financeRepositoryProvider).valueOrNull ?? widget.repository;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('编辑货币与汇率')),
          body: SettingsScreen(
            repository: ledger,
            settingsController: widget.settingsController,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final savedSymbol =
        repository.metaValues['currency_symbol_style'] == 'symbol' ? 0 : 1;
    final savedSeparator =
        repository.metaValues['number_separator_style'] == 'space_comma'
            ? 1
            : 0;
    final symbol = _symbolDraft ?? savedSymbol;
    final separator = _separatorDraft ?? savedSeparator;
    final base = repository.baseCurrency;
    final secondary = repository.secondaryCurrency;
    final rate = secondary == null
        ? null
        : exchangeRateToBase(
            secondary,
            repository.exchangeRatesToBase,
            baseCurrency: base,
          );

    return _SettingsDetailShell(
      title: '货币、汇率与显示',
      children: [
        const CompassSectionLabel('换算预览'),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(color: FinanceColors.compassTeal),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_previewMoney(1000, base, symbol, separator),
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
            if (secondary != null && rate != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward_rounded),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    border: Border.all(color: FinanceColors.compassBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _previewMoney(1000 / rate, secondary, symbol, separator),
                    style: const TextStyle(
                        color: FinanceColors.compassTeal, fontSize: 18),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (secondary != null && rate != null) ...[
          const SizedBox(height: 10),
          Center(
              child: Text('1 $secondary = $base ${rate.toStringAsFixed(4)}')),
        ],
        const SizedBox(height: 22),
        CompassSettingsRow(
          icon: Icons.monetization_on_outlined,
          title: '主币种',
          value: base,
          onTap: _openFullSettings,
        ),
        CompassSettingsRow(
          icon: Icons.sell_outlined,
          title: '辅助币种',
          value: secondary ?? '未设置',
          onTap: _openFullSettings,
        ),
        const SizedBox(height: 20),
        const CompassSectionLabel('显示方式'),
        _ChoiceSetting(
          icon: Icons.account_balance_wallet_outlined,
          labels: [currencyLabel(base), base],
          selected: symbol,
          onChanged: (value) => setState(
              () => _symbolDraft = value == savedSymbol ? null : value),
        ),
        _ChoiceSetting(
          icon: Icons.format_quote_outlined,
          labels: const ['1,234.56', '1 234,56'],
          selected: separator,
          onChanged: (value) => setState(
              () => _separatorDraft = value == savedSeparator ? null : value),
        ),
        CompassSettingsRow(
          icon: Icons.grid_view_rounded,
          title: '小数位',
          value: '2',
          onTap: _openFullSettings,
        ),
        const SizedBox(height: 20),
        const CompassSectionLabel('其他币种汇率'),
        ...repository.currencyPriority.where((code) => code != base).map(
              (code) => _RateRow(
                code: code,
                value: repository.hasExchangeRate(code)
                    ? '$base ${repository.exchangeRatesToBase[code]!.toStringAsFixed(4)}'
                    : '未估值',
                onTap: _openFullSettings,
              ),
            ),
        CompassSettingsRow(
          icon: Icons.format_list_bulleted_rounded,
          title: '管理币种顺序',
          onTap: _openFullSettings,
        ),
        const SizedBox(height: 20),
        const CompassSectionLabel('应用范围'),
        CompassSettingsRow(
          icon: Icons.bar_chart_rounded,
          title: '总览与报表',
          value: '使用主币种',
          onTap: _openFullSettings,
        ),
        CompassSettingsRow(
          icon: Icons.info_outline_rounded,
          title: '非主币种金额',
          value: '显示换算提示',
          onTap: _openFullSettings,
        ),
        const SizedBox(height: 18),
        CompassPrimaryButton(
          label: '应用并保存',
          color: FinanceColors.compassTeal,
          onPressed: _saveDisplayPreferences,
        ),
      ],
    );
  }

  Future<void> _saveDisplayPreferences() async {
    final symbol = _symbolDraft;
    final separator = _separatorDraft;
    try {
      final saved = await ref
          .read(financeRepositoryProvider.notifier)
          .mutate((repository) async {
        await repository.database.transaction(() async {
          if (symbol != null) {
            await repository.database.setMetaValue(
                'currency_symbol_style', symbol == 0 ? 'symbol' : 'code');
          }
          if (separator != null) {
            await repository.database.setMetaValue('number_separator_style',
                separator == 1 ? 'space_comma' : 'comma_dot');
          }
        });
        return repository.refresh();
      });
      if (!mounted || saved == null) return;
      setCompassMoneyStyle(
        useCurrencyCode: saved.metaValues['currency_symbol_style'] != 'symbol',
        useEuropeanSeparators:
            saved.metaValues['number_separator_style'] == 'space_comma',
      );
      setState(() {
        if (_symbolDraft == symbol) _symbolDraft = null;
        if (_separatorDraft == separator) _separatorDraft = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金额显示方式已保存。')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }
}

class FinanceRulesCenterPage extends ConsumerWidget {
  const FinanceRulesCenterPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger =
        ref.watch(financeRepositoryProvider).valueOrNull ?? repository;
    return _SettingsDetailShell(
      title: '规则中心',
      children: [
        _LargeRuleRow(
          icon: Icons.sell_outlined,
          title: '类别管理',
          value: '${ledger.categories.length} 个',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryManageScreen(repository: ledger),
            ),
          ),
        ),
        _LargeRuleRow(
          icon: Icons.bolt_rounded,
          title: '快速模板',
          value: '${ledger.transactionTemplates.length} 个',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuickTemplateManagerPage(repository: ledger),
            ),
          ),
        ),
        _LargeRuleRow(
          icon: Icons.event_repeat_outlined,
          title: '周期交易',
          value: '${ledger.recurringTransactionRules.length} 条',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecurringPlanPage(repository: ledger),
            ),
          ),
        ),
      ],
    );
  }
}

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  bool _busy = false;
  String? _lastBackupName;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
            '操作失败：${error is FormatException ? error.message : error}',
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBackup() => _run(() async {
        final name = _datedFileName('finance_compass_backup');
        final bytes =
            await ref.read(exportMutationsProvider.notifier).exportJsonBytes();
        final path = await _saveBytes(
          name: name,
          extension: 'json',
          bytes: bytes,
        );
        if (!mounted || path == null) return;
        setState(() => _lastBackupName = '$name.json');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已保存\n$path')),
        );
      });

  Future<void> _restoreBackup() => _run(() async {
        final imported = await pickPreviewAndImportLedger(context, ref);
        if (!mounted || !imported) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复完成，当前数据已重新载入。')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      });

  @override
  Widget build(BuildContext context) => _buildBackup(
        context,
        syncing: ref.watch(ledgerSyncSessionProvider) != null,
      );

  Widget _buildBackup(BuildContext context, {required bool syncing}) =>
      _SettingsDetailShell(
        title: '备份、恢复与迁移',
        children: [
          Text(
            syncing ? '账本保存在同步服务器' : '仅保存在此设备',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_lastBackupName != null) ...[
            const SizedBox(height: 8),
            Text(_lastBackupName!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          CompassPrimaryButton(
            label: '立即备份',
            icon: Icons.cloud_upload_outlined,
            outlined: true,
            onPressed: _busy ? null : () => _createBackup(),
          ),
          const SizedBox(height: 26),
          CompassHelpHeading(
            title: const CompassSectionLabel('导入保护'),
            label: '导入保护',
            message:
                kIsWeb ? '替换账本前，请下载当前账本的完整 JSON，以便恢复。' : '每次替换资料前，应用会先保留当前数据库。',
          ),
          CompassSettingsRow(
            icon: Icons.verified_user_outlined,
            title: kIsWeb ? '导入前手动备份' : '导入前自动恢复点',
          ),
          const SizedBox(height: 24),
          const CompassHelpHeading(
            title: CompassSectionLabel('恢复与迁移'),
            label: '恢复与迁移',
            message: '恢复时先选择 JSON 并核对预览，确认后会替换当前资料。迁移时先导出完整 JSON，再到新设备导入。',
          ),
          CompassSettingsRow(
            icon: Icons.file_open_outlined,
            title: '从备份恢复',
            subtitle: '确认后替换当前资料',
            onTap: _busy ? null : _restoreBackup,
          ),
          CompassSettingsRow(
            icon: Icons.phone_android_outlined,
            title: '迁移到新设备',
            onTap: _busy ? null : _createBackup,
          ),
        ],
      );
}

class ImportExportPage extends ConsumerStatefulWidget {
  const ImportExportPage({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends ConsumerState<ImportExportPage> {
  bool _busy = false;
  String? _lastExport;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
            '操作失败：${error is FormatException ? error.message : error}',
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({
    required String prefix,
    required String extension,
    required Future<Uint8List> Function() bytesBuilder,
  }) =>
      _run(() async {
        final name = _datedFileName(prefix);
        final bytes = await bytesBuilder();
        if (bytes.isEmpty) throw StateError('导出内容为空');
        final path = await _saveBytes(
          name: name,
          extension: extension,
          bytes: bytes,
        );
        if (!mounted || path == null) return;
        setState(() => _lastExport = '$name.$extension');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出完成（${bytes.length} bytes）\n$path')),
        );
      });

  Future<void> _exportFull() => _export(
        prefix: 'finance_compass',
        extension: 'json',
        bytesBuilder: () =>
            ref.read(exportMutationsProvider.notifier).exportJsonBytes(),
      );

  Future<void> _exportAiSummary() => _export(
        prefix: 'finance_compass_ai_summary',
        extension: 'json',
        bytesBuilder: () =>
            ref.read(exportMutationsProvider.notifier).exportAiSummaryBytes(
                  monthKeys: recentMonthKeys(count: 6),
                ),
      );

  Future<void> _exportFuturePlan() => _export(
        prefix: 'finance_compass_future_24_months',
        extension: 'csv',
        bytesBuilder: () => ref
            .read(exportMutationsProvider.notifier)
            .exportFuturePlanningCsvBytes(months: 24),
      );

  Future<void> _import() => _run(() async {
        final imported = await pickPreviewAndImportLedger(context, ref);
        if (!mounted || !imported) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入完成，当前数据已重新载入。')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      });

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
        title: '导入与导出',
        children: [
          const CompassSectionLabel('完整资料'),
          CompassSettingsRow(
            icon: Icons.upload_file_outlined,
            title: '导出完整数据',
            value: 'JSON',
            onTap: _busy ? null : _exportFull,
          ),
          CompassSettingsRow(
            icon: Icons.download_for_offline_outlined,
            title: '导入数据文件',
            subtitle: '确认后替换当前账本',
            onTap: _busy ? null : _import,
          ),
          const SizedBox(height: 30),
          const CompassHelpHeading(
            title: CompassSectionLabel('分析与规划'),
            label: '分析与规划',
            message: '分析摘要以 JSON 保存到所选位置。规划表可用表格应用打开。',
          ),
          CompassSettingsRow(
            icon: Icons.query_stats_rounded,
            title: 'AI 分析摘要',
            value: 'JSON',
            onTap: _busy ? null : _exportAiSummary,
          ),
          CompassSettingsRow(
            icon: Icons.table_chart_outlined,
            title: '未来规划表',
            subtitle: '未来 24 个月',
            value: 'CSV',
            onTap: _busy ? null : _exportFuturePlan,
          ),
          if (_lastExport != null) ...[
            const SizedBox(height: 24),
            const CompassSectionLabel('最近导出'),
            CompassSettingsRow(
              icon: Icons.description_outlined,
              title: _lastExport!,
            ),
          ],
        ],
      );
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool? _enabledDraft;
  bool? _loanDraft;
  final _switchDrafts = <int, bool>{};
  bool _saving = false;
  bool _pushBusy = false;
  BrowserPushStatus? _pushStatus;
  String? _pushError;
  String? _saveError;

  DevicePushNotifications? get _push {
    final session = ref.read(ledgerSyncSessionProvider);
    return kIsWeb && session != null ? DevicePushNotifications(session) : null;
  }

  @override
  void initState() {
    super.initState();
    _inspectPush();
  }

  List<bool> _switches(FinanceRepository ledger) {
    final values = <bool>[true, true, true, true, true, false, true];
    final raw = ledger.metaValues['notification_preferences_json'];
    if (raw == null) return values;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (var i = 0; i < values.length && i < decoded.length; i++) {
          if (decoded[i] is bool) values[i] = decoded[i] as bool;
        }
      }
    } on FormatException {
      // Earlier ledgers can lack readable switch preferences.
    }
    return values;
  }

  Future<void> _save() async {
    if (_saving) return;
    final enabled = _enabledDraft;
    final loan = _loanDraft;
    final updates = Map.of(_switchDrafts);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(financeRepositoryProvider.notifier)
          .mutate((repository) async {
        final database = repository.database;
        await database.transaction(() async {
          if (enabled != null) {
            await database.setMetaValue('notifications_enabled', '$enabled');
          }
          if (updates.isNotEmpty) {
            final switches = _switches(repository);
            for (final entry in updates.entries) {
              switches[entry.key] = entry.value;
            }
            await database.setMetaValue(
                'notification_preferences_json', jsonEncode(switches));
          }
          if (loan != null) {
            await database.setMetaValue('loan_payment_push_enabled', '$loan');
          }
        });
        return repository.refresh();
      });
      if (mounted) {
        _enabledDraft = null;
        _loanDraft = null;
        _switchDrafts.clear();
        _showMessage('提醒偏好已保存。');
      }
    } on SyncException catch (error) {
      if (mounted) setState(() => _saveError = error.message);
    } catch (_) {
      if (mounted) setState(() => _saveError = '无法保存提醒偏好，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _inspectPush() async {
    final push = _push;
    if (push == null || _pushBusy) return;
    await _runPush(push, () async {});
  }

  Future<void> _runPush(
    DevicePushNotifications push,
    Future<void> Function() action, {
    String? message,
  }) async {
    if (_pushBusy) return;
    setState(() {
      _pushBusy = true;
      _pushError = null;
    });
    String? errorMessage;
    try {
      await action();
      if (mounted && message != null) _showMessage(message);
    } on SyncException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = '本设备通知操作未完成。请检查浏览器通知权限后重试。';
    }
    if (!mounted) return;
    BrowserPushStatus? status;
    try {
      status = await push.inspect();
    } catch (_) {
      errorMessage ??= '无法检查设备通知。请刷新通知状态后重试。';
    }
    if (!mounted) return;
    setState(() {
      _pushStatus = status;
      _pushError = errorMessage ?? status?.error;
      _pushBusy = false;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<Widget> _devicePushControls(DevicePushNotifications push) {
    final status = _pushStatus;
    final isEnabled = status?.enabled == true;
    final endpoint = status?.endpoint;
    final publicKey = status?.publicKey;
    return [
      const CompassHelpHeading(
        title: CompassSectionLabel('本设备的系统通知'),
        label: '系统通知',
        message:
            '系统通知按订阅设备的时区在上午 9:00 发送。iPhone 或 iPad 先把应用添加至主屏幕，再从主屏幕打开并启用通知。',
      ),
      Text(
        _pushBusy
            ? '正在更新通知状态…'
            : switch (status) {
                BrowserPushStatus(supported: false) => '此浏览器不支持系统通知。',
                BrowserPushStatus(permission: 'denied') =>
                  '浏览器已阻止通知。允许本站发送通知后，请刷新通知状态。',
                BrowserPushStatus(enabled: true) => '系统通知已启用。',
                null => '通知状态暂不可用。',
                _ => '系统通知未启用。',
              },
      ),
      if (_pushError case final error?)
        Semantics(liveRegion: true, child: Text(error)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (isEnabled && endpoint != null) ...[
            OutlinedButton(
              onPressed: _pushBusy
                  ? null
                  : () => _runPush(push, () => push.sendTest(endpoint),
                      message: '测试已发送，请查看本设备的系统通知。'),
              child: const Text('发送测试通知'),
            ),
            OutlinedButton(
              onPressed: _pushBusy
                  ? null
                  : () => _runPush(push, push.disable, message: '已停用本设备的系统通知。'),
              child: const Text('停用系统通知'),
            ),
          ] else if (publicKey != null)
            FilledButton(
              onPressed: _pushBusy
                  ? null
                  : () => _runPush(push, () => push.enable(publicKey),
                      message: '已启用本设备的系统通知。'),
              child: const Text('启用系统通知'),
            )
          else
            OutlinedButton(
              onPressed: _pushBusy ? null : _inspectPush,
              child: const Text('刷新通知状态'),
            ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final savedEnabled =
        repository.metaValues['notifications_enabled'] != 'false';
    final savedLoan =
        repository.metaValues['loan_payment_push_enabled'] != 'false';
    final savedSwitches = _switches(repository);
    final switches = [
      for (var i = 0; i < savedSwitches.length; i++)
        _switchDrafts[i] ?? savedSwitches[i],
    ];
    final enabled = _enabledDraft ?? savedEnabled;
    final loanReminders = _loanDraft ?? savedLoan;
    final push = _push;
    final canEdit = !_saving;
    void setSwitch(int index, bool value) => setState(() {
          if (savedSwitches[index] == value) {
            _switchDrafts.remove(index);
          } else {
            _switchDrafts[index] = value;
          }
        });
    return _SettingsDetailShell(
      title: '通知与提醒',
      children: [
        if (push != null) ..._devicePushControls(push),
        Row(
          children: [
            Expanded(
              child: _NotificationToggle(
                icon: Icons.notifications_active_outlined,
                title: '账本提醒',
                value: enabled,
                onChanged: canEdit
                    ? (value) => setState(() =>
                        _enabledDraft = value == savedEnabled ? null : value)
                    : null,
              ),
            ),
            CompassHelpButton(
              title: '账本提醒',
              message: push == null ? '控制总览“需要关注”的提示。' : '控制应用内提醒和定时系统通知。',
            ),
          ],
        ),
        const SizedBox(height: 16),
        CompassHelpHeading(
          title: const CompassSectionLabel('信用卡'),
          label: '信用卡提醒',
          message: push == null
              ? '还款提醒在总览“需要关注”显示待还账单，结算提醒在信用卡结算日显示。'
              : '还款提醒在未还账单到期前 3 天发送。结算提醒在信用卡设定的结算日发送，也可开启到期当天提醒。',
        ),
        _NotificationToggle(
            icon: Icons.credit_card_rounded,
            title: '还款提醒',
            value: switches[0],
            onChanged: canEdit ? (v) => setSwitch(0, v) : null),
        _NotificationToggle(
            icon: Icons.calendar_month_outlined,
            title: '账单结算提醒',
            value: switches[1],
            onChanged: canEdit ? (v) => setSwitch(1, v) : null),
        if (push != null) ...[
          const SizedBox(height: 16),
          const CompassHelpHeading(
            title: CompassSectionLabel('贷款与到期'),
            label: '贷款与到期提醒',
            message: '贷款还款提醒在未还分期到期前 3 天发送。到期当天也可提醒缴付未还的信用卡账单和贷款分期。',
          ),
          _NotificationToggle(
            icon: Icons.account_balance_outlined,
            title: '贷款还款提醒',
            value: loanReminders,
            onChanged: canEdit
                ? (value) => setState(
                    () => _loanDraft = value == savedLoan ? null : value)
                : null,
          ),
          _NotificationToggle(
            icon: Icons.notification_important_outlined,
            title: '到期当天提醒',
            value: switches[6],
            onChanged: canEdit ? (v) => setSwitch(6, v) : null,
          ),
        ],
        const SizedBox(height: 16),
        const CompassHelpHeading(
          title: CompassSectionLabel('预算'),
          label: '预算提醒',
          message: '预算临界时在总览“需要关注”显示预算状态。',
        ),
        _NotificationToggle(
            icon: Icons.pie_chart_outline_rounded,
            title: '预算临界提醒',
            value: switches[4],
            onChanged: canEdit ? (v) => setSwitch(4, v) : null),
        const SizedBox(height: 12),
        if (_saveError case final error?) ...[
          Semantics(liveRegion: true, child: Text(error)),
          const SizedBox(height: 8),
        ],
        CompassPrimaryButton(
          label: _saving ? '正在保存…' : '保存提醒设置',
          color: financePaletteOf(context).seed,
          onPressed: canEdit ? _save : null,
        ),
      ],
    );
  }
}

class AiGatewayPage extends ConsumerStatefulWidget {
  const AiGatewayPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  ConsumerState<AiGatewayPage> createState() => _AiGatewayPageState();
}

class _AiGatewayPageState extends ConsumerState<AiGatewayPage> {
  bool _busy = false;

  String _analysisText(FinanceRepository ledger) =>
      AiAnalysisService.buildExternalAnalysisText(
        ledger,
        monthCount: 6,
        futureMonthCount: 6,
      );

  Future<void> _preview(FinanceRepository ledger) async {
    final text = _analysisText(ledger);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发送内容预览'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _share(FinanceRepository ledger) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          text: _analysisText(ledger),
          subject: 'Finance Compass 财务分析',
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    return _SettingsDetailShell(
      title: '外部 AI 分析',
      children: [
        const CompassSectionLabel('分析范围'),
        const CompassSettingsRow(
            icon: Icons.calendar_month_outlined,
            title: '历史资料',
            value: '最近 6 个月'),
        const CompassSettingsRow(
            icon: Icons.calendar_month_outlined,
            title: '未来计划',
            value: '未来 6 个月'),
        const CompassSettingsRow(
            icon: Icons.description_outlined, title: '包含预计交易与预算', value: '是'),
        const SizedBox(height: 18),
        const CompassHelpHeading(
          title: CompassSectionLabel('发送前检查'),
          label: '分享隐私',
          message: '选择分享对象后，摘要会发送给所选应用。可以先打开预览检查拟分享的财务资料。',
        ),
        CompassSettingsRow(
            icon: Icons.search_rounded,
            title: '预览分析资料',
            onTap: () => _preview(ledger)),
        const SizedBox(height: 14),
        CompassPrimaryButton(
            label: '选择外部 AI App',
            icon: Icons.ios_share_rounded,
            color: FinanceColors.compassTeal,
            onPressed: _busy ? null : () => _share(ledger)),
      ],
    );
  }
}

class _SettingsDetailShell extends StatelessWidget {
  const _SettingsDetailShell({
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: CompassBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    const CompassBackButton(),
                    const Spacer(),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    const SizedBox(width: 24),
                  ],
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      );
}

class _ChoiceSetting extends StatelessWidget {
  const _ChoiceSetting({
    required this.icon,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final IconData icon;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
                width: 38, child: Icon(icon, color: FinanceColors.compassTeal)),
            const SizedBox(width: 8),
            Expanded(
              child: CompassSegmentedControl(
                labels: labels,
                selectedIndex: selected,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.code,
    required this.value,
    required this.onTap,
  });
  final String code;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CompassSettingsRow(
        icon: Icons.monetization_on_outlined,
        title: code,
        value: value,
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: onTap,
      );
}

class _LargeRuleRow extends StatelessWidget {
  const _LargeRuleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: FinanceColors.compassBorder)),
          ),
          child: Row(
            children: [
              CompassIconBadge(icon: icon, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              Text(value,
                  style: const TextStyle(color: FinanceColors.compassTeal)),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: financePaletteOf(context).seed),
        title: Text(title),
        value: value,
        onChanged: onChanged,
      );
}

String _datedFileName(String prefix) {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  return '${prefix}_${now.year}-$month-${day}_$hour$minute';
}

Future<String?> _saveBytes({
  required String name,
  required String extension,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) {
    throw StateError('拒绝保存空文件');
  }
  return FilePicker.platform.saveFile(
    dialogTitle: '选择保存位置',
    fileName: '$name.$extension',
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: bytes,
  );
}

class AppearancePage extends StatefulWidget {
  const AppearancePage({
    super.key,
    required this.settingsController,
    required this.baseCurrency,
  });

  final AppSettingsController settingsController;
  final String baseCurrency;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late AppThemeStyle _previewStyle;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _previewStyle = widget.settingsController.themeStyle;
  }

  Future<void> _applyTheme() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.settingsController.setThemeStyle(_previewStyle);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存主题失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appliedStyle = widget.settingsController.themeStyle;
    final hasChange = _previewStyle != appliedStyle;
    return Theme(
      data: buildFinanceTheme(_previewStyle),
      child: Builder(
        builder: (themedContext) {
          final palette = financePaletteOf(themedContext);
          final textTheme = Theme.of(themedContext).textTheme;
          final donutColors = financeDonutSeries(themedContext);
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: CompassBackground(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: compassScrollPadding(
                        themedContext,
                        const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      ),
                      children: [
                        Row(
                          children: [
                            const CompassBackButton(),
                            const Spacer(),
                            Text('外观与主题', style: textTheme.titleLarge),
                            const Spacer(),
                            const SizedBox(width: 24),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _AppearanceLivePreview(
                          style: _previewStyle,
                          palette: palette,
                          donutColors: donutColors,
                          baseCurrency: widget.baseCurrency,
                        ),
                        const SizedBox(height: 20),
                        CompassHelpHeading(
                          title: const CompassSectionLabel('选择主题'),
                          label: '主题预览',
                          message: [
                            '选择主题后可实时预览。点击应用主题才会保存到本机。',
                            for (final style in AppThemeStyle.selectableStyles)
                              '${style.label}：${style.description}',
                          ].join('\n\n'),
                        ),
                        const SizedBox(height: 10),
                        for (final style in AppThemeStyle.selectableStyles) ...[
                          _ThemeOptionCard(
                            style: style,
                            previewSelected: _previewStyle == style,
                            currentlyApplied: appliedStyle == style,
                            onTap: _saving
                                ? null
                                : () => setState(() => _previewStyle = style),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 12),
                        CompassPrimaryButton(
                          label: _saving
                              ? '正在应用...'
                              : hasChange
                                  ? '应用主题'
                                  : '当前已应用',
                          onPressed: hasChange && !_saving ? _applyTheme : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AppearanceLivePreview extends StatelessWidget {
  const _AppearanceLivePreview({
    required this.style,
    required this.palette,
    required this.donutColors,
    required this.baseCurrency,
  });

  final AppThemeStyle style;
  final FinanceThemePalette palette;
  final List<Color> donutColors;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final actionColor = palette.resolvedPrimaryAction;
    return CompassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('效果预览 · ${style.label}', style: textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      compassMoney(28450, currency: baseCurrency, decimals: 0),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        fontFeatures: compassTabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              compassGlassHighlight(
                color: palette.glassHighlightColor,
                borderRadius: BorderRadius.circular(12),
                intensity: .55,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.glassHighlightColor != null
                        ? null
                        : actionColor,
                    gradient: palette.glassHighlightColor != null
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [const Color(0xFF1E8AE8), actionColor],
                            stops: const [0.0, 0.5],
                          )
                        : null,
                    boxShadow: palette.glassHighlightColor != null &&
                            !compassIsCpuSoftwareWeb
                        ? [
                            BoxShadow(
                              color: actionColor.withValues(alpha: .32),
                              blurRadius: 14,
                              spreadRadius: -3,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                    borderRadius: BorderRadius.circular(
                      palette.glassHighlightColor != null ? 12 : 10,
                    ),
                  ),
                  child: Text(
                    '记账',
                    style: TextStyle(
                      color: financeForegroundOn(actionColor),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CompassStatusBadge(label: '收入 + 6,200', color: palette.income),
              CompassStatusBadge(label: '支出 - 1,840', color: palette.expense),
              CompassStatusBadge(label: '预算 82%', color: palette.warning),
            ],
          ),
          const SizedBox(height: 12),
          CompassDualProgressBar(
            actualRatio: 0.62,
            plannedRatio: 0.16,
            alertThreshold: 0.8,
            height: 6,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('图表与胶囊预览', style: textTheme.bodySmall),
              const Spacer(),
              for (final color in donutColors.take(4))
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.donutSeparatorColor ?? palette.surface,
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
          if (palette.glassHighlightColor != null) ...[
            const SizedBox(height: 12),
            compassGlassHighlight(
              color: palette.glassHighlightColor,
              borderRadius: BorderRadius.circular(999),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: .64),
                      const Color(0xFFE6F4FF).withValues(alpha: .48),
                      Colors.white.withValues(alpha: .58),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .72),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      for (final (index, icon) in const [
                        Icons.account_balance_wallet_rounded,
                        Icons.wallet_outlined,
                        Icons.swap_horiz_rounded,
                        Icons.pie_chart_outline_rounded,
                        Icons.bar_chart_rounded,
                        Icons.settings_outlined,
                      ].indexed)
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: index == 0
                                  ? BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.white.withValues(alpha: .94),
                                          const Color(0xFFD6EEFF)
                                              .withValues(alpha: .78),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: .90),
                                      ),
                                    )
                                  : null,
                              child: Icon(
                                icon,
                                size: 15,
                                color: index == 0
                                    ? palette.seed
                                    : palette.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.style,
    required this.previewSelected,
    required this.currentlyApplied,
    required this.onTap,
  });

  final AppThemeStyle style;
  final bool previewSelected;
  final bool currentlyApplied;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final optionPalette = paletteForStyle(style);
    final activePalette = financePaletteOf(context);
    final swatches = <Color>[
      optionPalette.background,
      optionPalette.seed,
      optionPalette.resolvedPrimaryAction,
      ...?optionPalette.donutColors?.take(2),
    ];
    final activeGlass = activePalette.glassHighlightColor != null;
    return CompassCard(
      padding: EdgeInsets.zero,
      // Liquid Glass keeps option rows translucent (null => diagonal glass
      // fill) and tints the previewed one with a frosted selection lens.
      color: previewSelected
          ? (activeGlass
              ? (activePalette.selectedSurface ?? activePalette.surfaceAlt)
                  .withValues(alpha: .78)
              : activePalette.surfaceAlt)
          : (activeGlass ? null : activePalette.resolvedCardSurface),
      borderColor: previewSelected
          ? activePalette.seed
          : (activeGlass ? null : activePalette.border),
      onTap: onTap,
      child: Padding(
        key: Key('theme-option-${style.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final swatch in swatches.take(4))
                      Container(
                        width: 13,
                        height: 13,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                          border: Border.all(color: activePalette.border),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    style.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (currentlyApplied)
                    CompassStatusBadge(
                      label: '当前使用',
                      color: activePalette.income,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              previewSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: previewSelected
                  ? activePalette.seed
                  : activePalette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
