import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/finance_repository.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';
import 'settings_screen.dart';
import 'settings_reference_pages.dart';

const _financeCompassRepositoryUrl =
    'https://github.com/lawpowen-cte/finance-compass-app';
const _financeCompassReleasesUrl =
    'https://github.com/lawpowen-cte/finance-compass-app/releases/latest';
const _financeCompassIssuesUrl =
    'https://github.com/lawpowen-cte/finance-compass-app/issues';
const _financeCompassSupportQrAsset =
    'assets/support/touch-n-go-support-qr.jpg';

class SettingsV2Screen extends StatelessWidget {
  const SettingsV2Screen({
    super.key,
    required this.repository,
    required this.settingsController,
  });

  final FinanceRepository repository;
  final AppSettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: compassPagePadding,
      children: [
        CompassPageHeader(
          title: '设置',
          actions: [
            IconButton(
              tooltip: '关于与支持',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const FinanceCompassAboutPage(),
                ),
              ),
              icon: const Icon(Icons.help_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: '搜索设置',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            readOnly: true,
            onTap: () => showSearch<void>(
              context: context,
              delegate: _SettingsSearchDelegate(
                onOpen: (title) => _openAdvanced(context, title),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _LocalProfileRow(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AccountSyncPage(repository: repository),
            ),
          ),
        ),
        const Divider(),
        const SizedBox(height: 10),
        const _SettingsGroupTitle('管理我的财务'),
        CompassSettingsRow(
          icon: Icons.currency_exchange_rounded,
          title: '货币、汇率与显示',
          value: repository.baseCurrency,
          onTap: () => _openAdvanced(context, '货币、汇率与显示'),
        ),
        const Divider(),
        CompassSettingsRow(
          icon: Icons.sell_outlined,
          title: '类别、模板与周期规则',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FinanceRulesCenterPage(repository: repository),
            ),
          ),
        ),
        const Divider(),
        const SizedBox(height: 10),
        const _SettingsGroupTitle('数据与设备'),
        CompassSettingsRow(
          icon: Icons.cloud_upload_outlined,
          title: '备份、恢复与迁移',
          subtitle: '升级与导入前自动建立恢复点',
          value: '本地 JSON',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BackupRestorePage(repository: repository),
            ),
          ),
        ),
        const Divider(),
        CompassSettingsRow(
          icon: Icons.file_present_outlined,
          title: '导入与导出',
          value: 'JSON / CSV',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ImportExportPage(repository: repository),
            ),
          ),
        ),
        const Divider(),
        const SizedBox(height: 10),
        const _SettingsGroupTitle('个性化'),
        CompassSettingsRow(
          icon: Icons.brush_outlined,
          title: '外观与主题',
          value: '深色',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppearancePage(
                settingsController: settingsController,
              ),
            ),
          ),
        ),
        const Divider(),
        CompassSettingsRow(
          icon: Icons.notifications_none_rounded,
          title: '通知与提醒',
          value: repository.metaValues['notifications_enabled'] == 'false'
              ? '已关闭'
              : '应用内已开启',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationsPage(repository: repository),
            ),
          ),
        ),
        const Divider(),
        const SizedBox(height: 10),
        const _SettingsGroupTitle('智能与高级'),
        CompassSettingsRow(
          icon: Icons.trending_up_rounded,
          title: '智能分析与网关',
          subtitle: repository.aiGatewayUrl.isEmpty
              ? '外部 AI 分析'
              : repository.aiGatewayUrl,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AiGatewayPage(repository: repository),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'Finance Compass · 本地优先',
            style: TextStyle(color: Color(0xFF829399)),
          ),
        ),
      ],
    );
  }

  void _openAdvanced(BuildContext context, String title) {
    final Widget page = switch (title) {
      '个人账户' => AccountSyncPage(repository: repository),
      '货币、汇率与显示' => CurrencyDisplayPage(
          repository: repository,
          settingsController: settingsController,
        ),
      '类别、模板与周期规则' => FinanceRulesCenterPage(repository: repository),
      '备份、恢复与迁移' => BackupRestorePage(repository: repository),
      '导入与导出' => ImportExportPage(repository: repository),
      '外观与主题' => AppearancePage(settingsController: settingsController),
      '通知与提醒' => NotificationsPage(repository: repository),
      '智能分析与网关' => AiGatewayPage(repository: repository),
      _ => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SettingsScreen(
            repository: repository,
            settingsController: settingsController,
          ),
        ),
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }
}

class FinanceCompassAboutPage extends StatelessWidget {
  const FinanceCompassAboutPage({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接，请稍后重试。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于 Finance Compass')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: compassPagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Finance Compass',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text('版本 0.8.0+41 · 本地优先的个人财务罗盘'),
              const SizedBox(height: 12),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('你的财务资料保存在本机'),
                  subtitle: Text('只有你主动导出时，账本资料才会离开设备。'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openUrl(
                  context,
                  _financeCompassRepositoryUrl,
                ),
                icon: const Icon(Icons.code_rounded),
                label: const Text('在 GitHub 查看源代码'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openUrl(
                  context,
                  _financeCompassReleasesUrl,
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载最新版本'),
              ),
              TextButton.icon(
                onPressed: () => _openUrl(context, _financeCompassIssuesUrl),
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('报告问题'),
              ),
              const Divider(height: 32),
              Text(
                '请开发者喝杯咖啡',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '如果 Finance Compass 对你有帮助，欢迎自愿支持继续开发。支持完全自愿，不会解锁额外功能，也不形成服务权益；付款前请确认收款人是 LAW PO WEN。',
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Touch n Go 开发支持收款二维码，收款人 LAW PO WEN',
                image: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    _financeCompassSupportQrAsset,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '二维码只是静态图片；应用不接入支付 SDK，不读取付款结果，也不会因为支持与否改变任何功能。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSearchDelegate extends SearchDelegate<void> {
  _SettingsSearchDelegate({required this.onOpen});
  final ValueChanged<String> onOpen;

  static const entries = [
    '个人账户',
    '货币、汇率与显示',
    '类别、模板与周期规则',
    '备份、恢复与迁移',
    '导入与导出',
    '外观与主题',
    '通知与提醒',
    '智能分析与网关',
  ];

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(Icons.arrow_back),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final matches = entries
        .where((entry) => entry.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView(
      padding: compassPagePadding,
      children: matches
          .map((entry) => ListTile(
                title: Text(entry),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  close(context, null);
                  onOpen(entry);
                },
              ))
          .toList(),
    );
  }
}

class _SettingsGroupTitle extends StatelessWidget {
  const _SettingsGroupTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            color: FinanceColors.compassTeal,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _LocalProfileRow extends StatelessWidget {
  const _LocalProfileRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFF2B7B77),
              child: Text('L', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('个人账户 · 本地模式',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text('Google 登录与同步 · 计划中',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }
}
