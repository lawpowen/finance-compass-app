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
import '../../core/theme/finance_colors.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/month_range.dart';
import '../categories/category_manage_screen.dart';
import '../shared/compass_ui.dart';
import '../transactions/transaction_automation_pages.dart';
import 'settings_screen.dart';

class AccountSyncPage extends StatefulWidget {
  const AccountSyncPage({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  State<AccountSyncPage> createState() => _AccountSyncPageState();
}

class _AccountSyncPageState extends State<AccountSyncPage> {
  final enabled = <bool>[false, false, false, false];

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
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
                    Text('${widget.repository.transactions.length} 条交易仅保存在此设备',
                        style: Theme.of(context).textTheme.bodySmall),
                    const Text(
                      '● 离线可用',
                      style: TextStyle(color: FinanceColors.compassTeal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              foregroundColor: FinanceColors.compassText,
            ),
            icon: const Icon(Icons.cloud_outlined,
                color: FinanceColors.compassTeal),
            label: const Row(
              children: [
                Text('使用 Google 登录', style: TextStyle(fontSize: 18)),
                Spacer(),
                Text('计划中'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '登录后可跨设备同步；不登录也能使用全部本地功能',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 30),
          const CompassSectionLabel('计划同步的内容'),
          ...[
            (Icons.account_balance_wallet_outlined, '账户与交易'),
            (Icons.pie_chart_outline_rounded, '预算与类别'),
            (Icons.calendar_month_outlined, '模板与周期规则'),
            (Icons.settings_outlined, '应用偏好'),
          ].indexed.map(
                (entry) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary:
                      Icon(entry.$2.$1, color: FinanceColors.compassTeal),
                  title: Text(entry.$2.$2),
                  value: enabled[entry.$1],
                  onChanged: null,
                ),
              ),
          const SizedBox(height: 20),
          const CompassSectionLabel('首次同步'),
          const CompassSettingsRow(
            icon: Icons.cloud_upload_outlined,
            title: '同步前自动备份',
            value: '随 Google 同步开放',
          ),
          const CompassSettingsRow(
            icon: Icons.warning_amber_rounded,
            title: '发现冲突',
            value: '保留两份并提醒选择',
          ),
          Text('ⓘ  仅同步应用数据，不上传导出的 JSON / CSV 文件',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 22),
          CompassPrimaryButton(
            label: '备份当前数据',
            icon: Icons.cloud_upload_outlined,
            outlined: true,
            color: FinanceColors.compassTeal,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    BackupRestorePage(repository: widget.repository),
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
  late int symbol;
  late int separator;

  @override
  void initState() {
    super.initState();
    symbol = widget.repository.metaValues['currency_symbol_style'] == 'symbol'
        ? 0
        : 1;
    separator =
        widget.repository.metaValues['number_separator_style'] == 'space_comma'
            ? 1
            : 0;
  }

  String _previewMoney(double value, String currency) {
    final parts = value.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => separator == 1 ? ' ' : ',',
    );
    final prefix = symbol == 0
        ? switch (currency) {
            'MYR' => 'RM',
            'CNY' => 'RMB',
            _ => currency,
          }
        : currency;
    return '$prefix $grouped${separator == 1 ? ',' : '.'}${parts.last}';
  }

  void _openFullSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('编辑货币与汇率')),
          body: SettingsScreen(
            repository: widget.repository,
            settingsController: widget.settingsController,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
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
                  child: Text(_previewMoney(1000, 'MYR'),
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
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
                    _previewMoney(1538.46, 'CNY'),
                    style: const TextStyle(
                        color: FinanceColors.compassTeal, fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Center(child: Text('1 CNY = RM 0.6500')),
          const SizedBox(height: 22),
          CompassSettingsRow(
            icon: Icons.monetization_on_outlined,
            title: '主币种',
            value: widget.repository.baseCurrency,
            onTap: _openFullSettings,
          ),
          CompassSettingsRow(
            icon: Icons.sell_outlined,
            title: '辅助币种',
            value: widget.repository.currencyPriority.length > 1
                ? widget.repository.currencyPriority[1]
                : '未设置',
            onTap: _openFullSettings,
          ),
          const SizedBox(height: 20),
          const CompassSectionLabel('显示方式'),
          _ChoiceSetting(
            icon: Icons.account_balance_wallet_outlined,
            labels: const ['RM', 'MYR'],
            selected: symbol,
            onChanged: (value) => setState(() => symbol = value),
          ),
          _ChoiceSetting(
            icon: Icons.format_quote_outlined,
            labels: const ['1,234.56', '1 234,56'],
            selected: separator,
            onChanged: (value) => setState(() => separator = value),
          ),
          CompassSettingsRow(
            icon: Icons.grid_view_rounded,
            title: '小数位',
            value: '2',
            onTap: _openFullSettings,
          ),
          const SizedBox(height: 20),
          const CompassSectionLabel('其他币种汇率'),
          ...widget.repository.currencyPriority
              .where((code) => code != widget.repository.baseCurrency)
              .take(3)
              .map(
                (code) => _RateRow(
                  code: code,
                  value:
                      '${widget.repository.baseCurrency} ${(widget.repository.exchangeRatesToBase[code] ?? 0).toStringAsFixed(4)}',
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

  Future<void> _saveDisplayPreferences() async {
    await widget.repository.database.setMetaValue(
      'currency_symbol_style',
      symbol == 0 ? 'symbol' : 'code',
    );
    await widget.repository.database.setMetaValue(
      'number_separator_style',
      separator == 1 ? 'space_comma' : 'comma_dot',
    );
    setCompassMoneyStyle(
      useCurrencyCode: symbol == 1,
      useEuropeanSeparators: separator == 1,
    );
    ref.invalidate(financeRepositoryProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金额显示方式已保存。')),
      );
    }
  }
}

class FinanceRulesCenterPage extends StatelessWidget {
  const FinanceRulesCenterPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  Widget build(BuildContext context) {
    final total = repository.categories.length +
        repository.transactionTemplates.length +
        repository.recurringTransactionRules.length;
    final activeRules = repository.recurringTransactionRules
        .where((rule) => rule.isActive)
        .length;
    return _SettingsDetailShell(
      title: '规则中心',
      children: [
        Text(
          '$total',
          style: const TextStyle(
            color: FinanceColors.compassTeal,
            fontSize: 42,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text('项财务规则', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
            '${repository.categories.length} 类别 · '
            '${repository.transactionTemplates.length} 模板 · '
            '${repository.recurringTransactionRules.length} 周期规则',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 28),
        compassHairline,
        const SizedBox(height: 26),
        const CompassSectionLabel('管理规则'),
        _LargeRuleRow(
          icon: Icons.sell_outlined,
          title: '类别管理',
          subtitle: '支出、收入、投资与转账',
          value: '${repository.categories.length} 个',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryManageScreen(repository: repository),
            ),
          ),
        ),
        _LargeRuleRow(
          icon: Icons.bolt_rounded,
          title: '快速模板',
          subtitle: '前 5 个显示在闪电快捷面板',
          value: '${repository.transactionTemplates.length} 个',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuickTemplateManagerPage(repository: repository),
            ),
          ),
        ),
        _LargeRuleRow(
          icon: Icons.event_repeat_outlined,
          title: '周期交易',
          subtitle: '自动生成未来计划',
          value: '${repository.recurringTransactionRules.length} 条',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecurringPlanPage(repository: repository),
            ),
          ),
        ),
        const SizedBox(height: 26),
        const CompassSectionLabel('需要关注'),
        _LargeRuleRow(
          icon: Icons.notifications_none_rounded,
          title: '$activeRules 条周期规则正在运行',
          subtitle: '',
          value: '查看',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecurringPlanPage(repository: repository),
            ),
          ),
        ),
        _LargeRuleRow(
          icon: Icons.format_list_numbered_rounded,
          title:
              '快捷入口已使用 ${repository.transactionTemplates.length.clamp(0, 5)} / 5 个位置',
          subtitle: '',
          value: '调整顺序',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuickTemplateManagerPage(repository: repository),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('ⓘ  类别会被模板和周期规则共同引用',
            style: Theme.of(context).textTheme.bodySmall),
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
          SnackBar(content: Text('操作失败：$error')),
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
        final imported = await _pickPreviewAndImport(context, ref);
        if (!mounted || !imported) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复完成，当前数据已重新载入。')),
        );
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      });

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
        title: '备份、恢复与迁移',
        help: true,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 80, color: FinanceColors.compassTeal),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastBackupName == null ? '可以创建本地备份' : '最近备份已保存',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: FinanceColors.compassTeal,
                              ),
                    ),
                    Text(_lastBackupName ?? '尚未在本次会话中手动备份',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '${widget.repository.transactions.length} 条交易 · '
              '${widget.repository.categories.length} 个类别 · '
              '${widget.repository.transactionTemplates.length} 个模板 · '
              '${widget.repository.recurringTransactionRules.length} 条周期规则',
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('仅保存在此设备',
                style: TextStyle(color: FinanceColors.compassTeal)),
          ),
          const SizedBox(height: 20),
          CompassPrimaryButton(
            label: '立即备份',
            icon: Icons.cloud_upload_outlined,
            outlined: true,
            onPressed: _busy ? null : () => _createBackup(),
          ),
          const SizedBox(height: 26),
          const CompassSectionLabel('自动保护'),
          const CompassSettingsRow(
            icon: Icons.verified_user_outlined,
            title: '导入前自动恢复点',
            subtitle: '每次替换资料前，应用会先保留当前数据库',
            value: '已开启',
          ),
          const CompassSettingsRow(
            icon: Icons.folder_outlined,
            title: '保存位置',
            value: '由系统文件选择器决定',
          ),
          const CompassSettingsRow(
            icon: Icons.history_rounded,
            title: '备份格式',
            value: 'Finance Compass JSON',
          ),
          const SizedBox(height: 24),
          const CompassSectionLabel('恢复与迁移'),
          CompassSettingsRow(
            icon: Icons.file_open_outlined,
            title: '从备份恢复',
            subtitle: '选择 JSON，预览后替换当前资料',
            onTap: _busy ? null : _restoreBackup,
          ),
          CompassSettingsRow(
            icon: Icons.phone_android_outlined,
            title: '迁移到新设备',
            subtitle: '导出完整 JSON，再在新设备导入',
            onTap: _busy ? null : _createBackup,
          ),
          const SizedBox(height: 18),
          Text('ⓘ  备份不会上传到云端；Google 同步功能仍在计划中',
              style: Theme.of(context).textTheme.bodySmall),
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
          SnackBar(content: Text('操作失败：$error')),
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
        final imported = await _pickPreviewAndImport(context, ref);
        if (!mounted || !imported) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入完成，当前数据已重新载入。')),
        );
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      });

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
        title: '导入与导出',
        help: true,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows_rounded,
                  color: FinanceColors.compassTeal, size: 92),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '你的数据可以自由带走',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: FinanceColors.compassTeal,
                              ),
                    ),
                    Text('文件由你保存，不会自动上传',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const CompassSectionLabel('完整资料'),
          CompassSettingsRow(
            icon: Icons.upload_file_outlined,
            title: '导出完整数据',
            subtitle: 'JSON · 账户、交易、预算、类别、模板与周期规则',
            value: '导出',
            onTap: _busy ? null : _exportFull,
          ),
          CompassSettingsRow(
            icon: Icons.download_for_offline_outlined,
            title: '导入数据文件',
            subtitle: '选择 Finance Compass JSON',
            onTap: _busy ? null : _import,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 48, top: 2),
            child: Text(
              'ⓘ  导入前会先预览；确认后将替换当前资料，并自动创建恢复点',
              style: TextStyle(color: FinanceColors.compassOrange),
            ),
          ),
          const SizedBox(height: 30),
          const CompassSectionLabel('分析与规划'),
          CompassSettingsRow(
            icon: Icons.query_stats_rounded,
            title: 'AI 分析摘要',
            subtitle: '去除不必要资料的分析用 JSON',
            value: '导出',
            onTap: _busy ? null : _exportAiSummary,
          ),
          CompassSettingsRow(
            icon: Icons.table_chart_outlined,
            title: '未来规划表',
            subtitle: '未来 24 个月 · CSV',
            value: '导出',
            onTap: _busy ? null : _exportFuturePlan,
          ),
          const SizedBox(height: 30),
          const CompassSectionLabel('最近导出'),
          CompassSettingsRow(
            icon: Icons.description_outlined,
            title: _lastExport ?? '本次会话尚未导出',
            subtitle: _lastExport == null ? '导出后会在这里显示文件名' : '已通过系统文件选择器保存',
          ),
          const SizedBox(height: 22),
          Text('ⓘ  备份与恢复请前往上一项设置；导出文件不会自动加入备份',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          CompassPrimaryButton(
            label: '导出完整数据',
            icon: Icons.file_upload_outlined,
            outlined: true,
            onPressed: _busy ? null : () => _exportFull(),
          ),
        ],
      );
}

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key, required this.settingsController});
  final AppSettingsController settingsController;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late final PageController _themePageController;
  late AppThemeStyle _previewStyle;
  late int mode;
  int preview = 0;
  int? _pageAnimationTarget;
  int _pageAnimationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _previewStyle = widget.settingsController.themeStyle;
    mode = _isDarkTheme(_previewStyle) ? 2 : 1;
    _themePageController = PageController(
      initialPage: AppThemeStyle.values.indexOf(_previewStyle),
      viewportFraction: .84,
    );
  }

  @override
  void dispose() {
    _themePageController.dispose();
    super.dispose();
  }

  void _setPreviewStyle(AppThemeStyle style) {
    _previewStyle = style;
    mode = _isDarkTheme(style) ? 2 : 1;
  }

  void _previewTheme(AppThemeStyle style, {bool animate = true}) {
    final index = AppThemeStyle.values.indexOf(style);
    setState(() => _setPreviewStyle(style));
    if (!animate || !_themePageController.hasClients) return;
    final generation = ++_pageAnimationGeneration;
    _pageAnimationTarget = index;
    _themePageController
        .animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    )
        .whenComplete(() {
      if (!mounted || generation != _pageAnimationGeneration) return;
      _pageAnimationTarget = null;
      if (!_themePageController.hasClients) return;
      final settled = _themePageController.page?.round();
      if (settled != null && settled != index) {
        setState(() => _setPreviewStyle(AppThemeStyle.values[settled]));
      }
    });
  }

  void _handlePageChanged(int index) {
    final target = _pageAnimationTarget;
    if (target != null && index != target) return;
    setState(() => _setPreviewStyle(AppThemeStyle.values[index]));
  }

  Future<void> _applyPreviewTheme() async {
    final style = _previewStyle;
    await widget.settingsController.setThemeStyle(style);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已应用「${_themeLabel(style)}」主题')),
    );
  }

  Future<void> _showThemePicker() async {
    final selected = await showModalBottomSheet<AppThemeStyle>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('选择主题', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...AppThemeStyle.values.map(
              (style) => ListTile(
                title: Text(_themeLabel(style)),
                trailing: _previewStyle == style
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, style),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      _previewTheme(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = AppThemeStyle.values.indexOf(_previewStyle);
    final previewPalette = paletteForStyle(_previewStyle);
    final isCurrent = widget.settingsController.themeStyle == _previewStyle;
    return _SettingsDetailShell(
      title: '外观与主题',
      help: true,
      children: [
        const CompassSectionLabel('显示模式'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ModeChoice(
                label: '跟随系统（计划中）', icon: Icons.phone_android, selected: false),
            _ModeChoice(
                label: '浅色',
                icon: Icons.light_mode_outlined,
                selected: mode == 1,
                onTap: () => _previewTheme(AppThemeStyle.tide)),
            _ModeChoice(
                label: '深色',
                icon: Icons.dark_mode_outlined,
                selected: mode == 2,
                onTap: () => _previewTheme(AppThemeStyle.abyss)),
          ],
        ),
        const SizedBox(height: 26),
        const CompassSectionLabel('选择主题'),
        const SizedBox(height: 4),
        SizedBox(
          height: 340,
          child: PageView.builder(
            controller: _themePageController,
            itemCount: AppThemeStyle.values.length,
            onPageChanged: _handlePageChanged,
            itemBuilder: (context, index) {
              final style = AppThemeStyle.values[index];
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.fromLTRB(
                  6,
                  index == selectedIndex ? 2 : 12,
                  6,
                  index == selectedIndex ? 2 : 12,
                ),
                child: _ThemePreviewCard(
                  key: ValueKey('theme-preview-${style.name}'),
                  style: style,
                  previewIndex: preview,
                  selected: index == selectedIndex,
                  onTap: () => _previewTheme(style),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${isCurrent ? '✓' : '左右拖动预览'}  ${_themeLabel(_previewStyle)}${isCurrent ? ' · 当前使用' : ''}',
            style: TextStyle(color: previewPalette.seed),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Wrap(
            spacing: 5,
            children: List.generate(
              AppThemeStyle.values.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == selectedIndex ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == selectedIndex
                      ? previewPalette.seed
                      : Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        CompassSettingsRow(
          icon: Icons.grid_view_rounded,
          title: '查看全部 12 款主题',
          onTap: _showThemePicker,
        ),
        const SizedBox(height: 16),
        const CompassSectionLabel('自动切换'),
        const SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.schedule_rounded),
          title: Text('日落后使用深色主题'),
          subtitle: Text('计划中'),
          value: false,
          onChanged: null,
        ),
        CompassSettingsRow(
          icon: Icons.light_mode_outlined,
          title: '浅色主题',
          value: '潮汐',
          onTap: () => _previewTheme(AppThemeStyle.tide),
        ),
        CompassSettingsRow(
          icon: Icons.dark_mode_outlined,
          title: '深色主题',
          value: '墨绿',
          onTap: () => _previewTheme(AppThemeStyle.abyss),
        ),
        const SizedBox(height: 18),
        const CompassSectionLabel('预览内容'),
        _ChoiceSetting(
          icon: Icons.preview_outlined,
          labels: const ['总览', '交易'],
          selected: preview,
          onChanged: (value) => setState(() => preview = value),
        ),
        const SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('增强文字对比度'),
          subtitle: Text('计划中'),
          value: false,
          onChanged: null,
        ),
        const SizedBox(height: 12),
        CompassPrimaryButton(
          label: isCurrent ? '当前正在使用' : '设为当前主题',
          color: previewPalette.seed,
          onPressed: _applyPreviewTheme,
        ),
      ],
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    super.key,
    required this.style,
    required this.previewIndex,
    required this.selected,
    required this.onTap,
  });

  final AppThemeStyle style;
  final int previewIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = paletteForStyle(style);
    final borderColor = selected ? palette.seed : palette.border;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.backgroundTop,
            palette.background,
            palette.backgroundBottom,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: borderColor, width: selected ? 1.4 : .8),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: palette.seed.withValues(alpha: .16),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DefaultTextStyle(
          style: TextStyle(color: palette.textPrimary, fontSize: 11),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
            child: previewIndex == 0
                ? _ThemeDashboardPreview(palette: palette)
                : _ThemeTransactionsPreview(palette: palette),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '${_themeLabel(style)}主题预览',
      hint: selected ? null : '点击预览，不会立即应用',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class _ThemeDashboardPreview extends StatelessWidget {
  const _ThemeDashboardPreview({required this.palette});

  final FinanceThemePalette palette;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('总览', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Icon(Icons.notifications_none_rounded,
                  size: 17, color: palette.textMuted),
            ],
          ),
          const SizedBox(height: 13),
          Text('总资产 (MYR)', style: TextStyle(color: palette.textMuted)),
          const SizedBox(height: 2),
          const Text('168,888.00',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w500)),
          Text('今日收益  +1,234.56 (+0.74%)',
              style: TextStyle(color: palette.seed)),
          const SizedBox(height: 7),
          CompassAreaChart(
            values: const [10, 9, 11, 10, 12, 11, 14],
            lineColor: palette.seed,
            height: 42,
          ),
          Divider(color: palette.border, height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniMetric(label: '收入', value: '+28,600', color: palette.seed),
              _MiniMetric(
                  label: '支出', value: '-16,320', color: palette.expense),
              _MiniMetric(label: '净流入', value: '+12,280', color: palette.seed),
            ],
          ),
          const SizedBox(height: 9),
          _MiniAccountRow(
              icon: Icons.account_balance_wallet_outlined,
              label: '现金账户',
              value: '12,338',
              palette: palette),
          _MiniAccountRow(
              icon: Icons.savings_outlined,
              label: '储蓄账户',
              value: '56,800',
              palette: palette),
          const Spacer(),
          _MiniNavigation(palette: palette, selected: 0),
        ],
      );
}

class _ThemeTransactionsPreview extends StatelessWidget {
  const _ThemeTransactionsPreview({required this.palette});

  final FinanceThemePalette palette;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('交易', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 13),
          Text('7月净现金流', style: TextStyle(color: palette.textMuted)),
          Text('MYR 5,380',
              style: TextStyle(
                color: palette.seed,
                fontSize: 23,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 12),
          _MiniTransactionRow(
              icon: Icons.work_outline_rounded,
              label: '薪资收入',
              value: '+ 8,800',
              color: palette.seed,
              palette: palette),
          _MiniTransactionRow(
              icon: Icons.shopping_cart_outlined,
              label: '超市购物',
              value: '- 156.80',
              color: palette.expense,
              palette: palette),
          _MiniTransactionRow(
              icon: Icons.restaurant_outlined,
              label: '午餐',
              value: '- 18.00',
              color: palette.expense,
              palette: palette),
          _MiniTransactionRow(
              icon: Icons.local_gas_station_outlined,
              label: '加油',
              value: '- 120.00',
              color: palette.expense,
              palette: palette),
          const Spacer(),
          _MiniNavigation(palette: palette, selected: 2),
        ],
      );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9)),
          Text(value, style: TextStyle(color: color, fontSize: 10)),
        ],
      );
}

class _MiniAccountRow extends StatelessWidget {
  const _MiniAccountRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final String value;
  final FinanceThemePalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: palette.seed.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 14, color: palette.seed),
            ),
            const SizedBox(width: 8),
            Text(label),
            const Spacer(),
            Text(value),
          ],
        ),
      );
}

class _MiniTransactionRow extends StatelessWidget {
  const _MiniTransactionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final FinanceThemePalette palette;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 9),
            Text(label),
            const Spacer(),
            Text(value, style: TextStyle(color: color)),
          ],
        ),
      );
}

class _MiniNavigation extends StatelessWidget {
  const _MiniNavigation({required this.palette, required this.selected});

  final FinanceThemePalette palette;
  final int selected;

  static const icons = [
    Icons.home_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.swap_horiz_rounded,
    Icons.pie_chart_outline_rounded,
    Icons.bar_chart_rounded,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          icons.length,
          (index) => Icon(
            icons[index],
            size: 16,
            color: index == selected ? palette.seed : palette.textMuted,
          ),
        ),
      );
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool enabled = true;
  final switches = <bool>[true, true, true, true, true, false, true];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabledRaw =
        await widget.repository.database.getMetaValue('notifications_enabled');
    final switchesRaw = await widget.repository.database
        .getMetaValue('notification_preferences_json');
    if (!mounted) return;
    setState(() {
      if (enabledRaw != null) enabled = enabledRaw == 'true';
      if (switchesRaw != null) {
        final decoded = jsonDecode(switchesRaw);
        if (decoded is List && decoded.length == switches.length) {
          for (var i = 0; i < switches.length; i++) {
            switches[i] = decoded[i] == true;
          }
        }
      }
    });
  }

  Future<void> _save() async {
    await widget.repository.database
        .setMetaValue('notifications_enabled', '$enabled');
    await widget.repository.database.setMetaValue(
      'notification_preferences_json',
      jsonEncode(switches),
    );
    ref.invalidate(financeRepositoryProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒偏好已保存。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
        title: '通知与提醒',
        help: true,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.notifications_active_outlined,
                size: 56, color: FinanceColors.compassTeal),
            title: const Text('应用内提醒已开启'),
            subtitle: const Text('控制总览“需要关注”；系统推送尚未开放'),
            value: enabled,
            onChanged: (value) => setState(() => enabled = value),
          ),
          const SizedBox(height: 16),
          const CompassSectionLabel('信用卡'),
          _NotificationToggle(
              icon: Icons.credit_card_rounded,
              title: '还款提醒',
              subtitle: '在总览“需要关注”显示待还账单',
              value: switches[0],
              onChanged: (v) => setState(() => switches[0] = v)),
          _NotificationToggle(
              icon: Icons.calendar_month_outlined,
              title: '账单结算提醒',
              subtitle: '结算后在总览显示账单状态',
              value: switches[1],
              onChanged: (v) => setState(() => switches[1] = v)),
          _NotificationToggle(
              icon: Icons.percent_rounded,
              title: '额度使用提醒',
              subtitle: '系统推送排程计划中',
              value: false,
              onChanged: null),
          const SizedBox(height: 16),
          const CompassSectionLabel('计划与预算'),
          _NotificationToggle(
              icon: Icons.repeat_rounded,
              title: '周期交易提醒',
              subtitle: '系统推送排程计划中',
              value: false,
              onChanged: null),
          _NotificationToggle(
              icon: Icons.pie_chart_outline_rounded,
              title: '预算临界提醒',
              subtitle: '在总览“需要关注”显示预算状态',
              value: switches[4],
              onChanged: (v) => setState(() => switches[4] = v)),
          _NotificationToggle(
              icon: Icons.description_outlined,
              title: '每周现金流摘要',
              subtitle: '系统推送排程计划中',
              value: false,
              onChanged: null),
          const SizedBox(height: 16),
          const CompassSectionLabel('安静时间'),
          CompassSettingsRow(
              icon: Icons.dark_mode_outlined,
              title: '免打扰时段',
              subtitle: '系统通知排程完成后开放',
              value: '计划中'),
          _NotificationToggle(
              icon: Icons.notification_important_outlined,
              title: '紧急还款提醒',
              subtitle: '系统推送排程计划中',
              value: false,
              onChanged: null),
          const SizedBox(height: 14),
          const CompassCard(
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: FinanceColors.compassTeal),
                SizedBox(width: 12),
                Expanded(child: Text('这些设置会立即控制应用内“需要关注”；Android 系统通知排程尚未实现。')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CompassPrimaryButton(
            label: '保存提醒设置',
            color: FinanceColors.compassTeal,
            onPressed: _save,
          ),
        ],
      );
}

class AiGatewayPage extends StatefulWidget {
  const AiGatewayPage({super.key, required this.repository});
  final FinanceRepository repository;

  @override
  State<AiGatewayPage> createState() => _AiGatewayPageState();
}

class _AiGatewayPageState extends State<AiGatewayPage> {
  bool _busy = false;

  String get _analysisText => AiAnalysisService.buildExternalAnalysisText(
        widget.repository,
        monthCount: 6,
        futureMonthCount: 6,
      );

  Future<void> _preview() async {
    final text = _analysisText;
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

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          text: _analysisText,
          subject: 'Finance Compass 财务分析',
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsDetailShell(
        title: '外部 AI 分析',
        help: true,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy_outlined,
                  size: 74, color: FinanceColors.compassTeal),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '由你选择 AI App',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: FinanceColors.compassTeal,
                              ),
                    ),
                    Text('应用只生成分析文字，不会自动上传资料',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          const CompassSectionLabel('发送前检查'),
          CompassSettingsRow(
              icon: Icons.search_rounded,
              title: '预览分析资料',
              value: '${_analysisText.length} 字符',
              onTap: _preview),
          const CompassCard(
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    color: FinanceColors.compassTeal),
                SizedBox(width: 12),
                Expanded(child: Text('不会自动发送完整备份；只有点下方按钮后才会打开系统分享面板')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          CompassPrimaryButton(
              label: '选择外部 AI App',
              icon: Icons.ios_share_rounded,
              color: FinanceColors.compassTeal,
              onPressed: _busy ? null : () => _share()),
        ],
      );
}

class _SettingsDetailShell extends StatelessWidget {
  const _SettingsDetailShell({
    required this.title,
    required this.children,
    this.help = false,
  });
  final String title;
  final List<Widget> children;
  final bool help;

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
                    if (help)
                      IconButton(
                        tooltip: '本页说明',
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text('$title说明'),
                            content: const Text(
                              '可操作项目会显示箭头、按钮或开关；标记“计划中”的项目当前不会响应点击。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('知道了'),
                              ),
                            ],
                          ),
                        ),
                        icon: const Icon(Icons.help_outline_rounded),
                      )
                    else
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
    required this.subtitle,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(value,
                  style: const TextStyle(color: FinanceColors.compassTeal)),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final content = Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? FinanceColors.compassTeal
                    : FinanceColors.compassBorder,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon),
          ),
          const SizedBox(height: 6),
          Text(label),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: FinanceColors.compassTeal),
        title: Text(title),
        subtitle: Text(subtitle),
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

bool _isDarkTheme(AppThemeStyle style) => {
      AppThemeStyle.night,
      AppThemeStyle.abyss,
      AppThemeStyle.graphite,
      AppThemeStyle.darkGreen,
      AppThemeStyle.darkWood,
    }.contains(style);

String _themeLabel(AppThemeStyle style) => switch (style) {
      AppThemeStyle.tide => '潮汐',
      AppThemeStyle.ocean => '海洋',
      AppThemeStyle.sky => '晴空',
      AppThemeStyle.ember => '余烬',
      AppThemeStyle.forest => '森林',
      AppThemeStyle.dune => '沙丘',
      AppThemeStyle.aurora => '极光',
      AppThemeStyle.night => '夜色',
      AppThemeStyle.abyss => '墨绿',
      AppThemeStyle.graphite => '石墨',
      AppThemeStyle.darkGreen => '深林',
      AppThemeStyle.darkWood => '沉木',
    };

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

Future<bool> _pickPreviewAndImport(
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
  final path = file.path;
  final bytes = file.bytes;
  if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
    return false;
  }
  final mutations = ref.read(exportMutationsProvider.notifier);
  final preview = path != null && path.isNotEmpty
      ? await mutations.previewImport(path)
      : await mutations.previewImportBytes(bytes!);
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
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入预览'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出时间：${preview.exportedAt ?? '-'}'),
              Text('账户：${preview.accounts}'),
              Text('类别：${preview.categories}'),
              Text('预算：${preview.budgets}'),
              Text('交易：${preview.transactions}'),
              Text('资产快照：${preview.assetSnapshots}'),
              const SizedBox(height: 12),
              Text(
                kIsWeb
                    ? '确认会替换当前资料。请先下载当前完整 JSON；Web 浏览器不会在服务器保留隐藏恢复点。'
                    : '确认后会先建立恢复点，再用此文件替换当前资料。',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return false;

  if (path != null && path.isNotEmpty) {
    await mutations.importJson(path);
  } else {
    await mutations.importJsonBytes(bytes!);
  }
  return true;
}
