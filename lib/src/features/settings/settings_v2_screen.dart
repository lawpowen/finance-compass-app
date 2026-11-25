import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_version.dart';
import '../../core/data/finance_repository.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/theme/finance_theme.dart';
import '../shared/compass_ui.dart';
import 'settings_screen.dart';
import 'settings_reference_pages.dart';

const _financeCompassRepositoryUrl =
    'https://github.com/lawpowen/finance-compass-app';
const _financeCompassReleasesUrl =
    'https://github.com/lawpowen/finance-compass-app/releases/latest';
const _financeCompassIssuesUrl =
    'https://github.com/lawpowen/finance-compass-app/issues';
const _financeCompassSupportQrAsset =
    'assets/support/touch-n-go-support-qr.jpg';
const _financeVersionDisplay =
    kIsWeb ? '$appVersion · $webReleaseLabel' : appVersion;

class SettingsV2Screen extends StatelessWidget {
  const SettingsV2Screen({
    super.key,
    required this.repository,
    required this.settingsController,
    this.syncing = false,
    this.syncSettings,
  });

  final FinanceRepository repository;
  final AppSettingsController settingsController;
  final bool syncing;
  final Widget? syncSettings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: settingsController,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) => _buildPage(
            context,
            wide: constraints.maxWidth >= compassDesktopMinWidth,
          ),
        ),
      );

  Widget _buildPage(BuildContext context, {required bool wide}) {
    CompassSettingsRow setting({
      required IconData icon,
      required String title,
      String? subtitle,
      String? value,
    }) =>
        CompassSettingsRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          value: wide ? null : value,
          trailing: wide && value != null
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 128),
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : null,
          onTap: () => _openAdvanced(context, title),
        );

    void openSearch() => showSearch<void>(
          context: context,
          delegate: _SettingsSearchDelegate(
            onOpen: (title) => _openAdvanced(context, title),
          ),
        );

    final search = SizedBox(
      height: 44,
      child: wide
          ? OutlinedButton(
              onPressed: openSearch,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('搜索设置'),
                ],
              ),
            )
          : TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: '搜索设置',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              readOnly: true,
              onTap: openSearch,
            ),
    );
    final about = IconButton(
      tooltip: '关于与支持',
      onPressed: () => _openAbout(context),
      icon: const Icon(Icons.help_outline_rounded),
    );
    final profile = _LocalProfileRow(
      syncing: syncing,
      onTap: () => _openAdvanced(context, '个人账户'),
    );
    final version = CompassSettingsRow(
      icon: Icons.info_outline_rounded,
      title: '版本信息',
      subtitle: _financeVersionDisplay,
      onTap: () => _openAbout(context),
    );
    final sections = [
      _SettingsSection(
        title: '管理我的财务',
        rows: [
          setting(
            icon: Icons.currency_exchange_rounded,
            title: '货币、汇率与显示',
            value: repository.baseCurrency,
          ),
          setting(
            icon: Icons.sell_outlined,
            title: '类别、模板与周期规则',
          ),
        ],
      ),
      _SettingsSection(
        title: '数据与设备',
        rows: [
          setting(
            icon: Icons.cloud_upload_outlined,
            title: '备份、恢复与迁移',
            value: '本地 JSON',
          ),
          setting(
            icon: Icons.file_present_outlined,
            title: '导入与导出',
            value: 'JSON / CSV',
          ),
        ],
      ),
      _SettingsSection(
        title: '个性化',
        rows: [
          setting(
            icon: Icons.palette_outlined,
            title: '外观与主题',
            value: settingsController.themeStyle.label,
          ),
          setting(
            icon: Icons.notifications_none_rounded,
            title: '通知与提醒',
            value: repository.metaValues['notifications_enabled'] == 'false'
                ? '已关闭'
                : '应用内已开启',
          ),
        ],
      ),
      _SettingsSection(
        title: '智能与高级',
        rows: [
          setting(
            icon: Icons.trending_up_rounded,
            title: '智能分析与网关',
            subtitle: repository.aiGatewayUrl.isEmpty
                ? null
                : repository.aiGatewayUrl,
          ),
        ],
      ),
    ];

    if (wide) {
      return ListView(
        padding: compassScrollPadding(context, compassDesktopPagePadding),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CompassPageHeader(title: '设置', actions: [about]),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 288,
                        child: CompassCard(
                          radius: 16,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              profile,
                              if (syncSettings case final actions?) ...[
                                const Divider(height: 1),
                                actions,
                              ],
                              const Divider(height: 1),
                              version,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            search,
                            for (final section in sections) ...[
                              const SizedBox(height: 12),
                              section.desktopCard(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: compassScrollPadding(context, compassPagePadding),
      children: [
        CompassPageHeader(title: '设置', actions: [about]),
        const SizedBox(height: 14),
        search,
        const SizedBox(height: 12),
        profile,
        const Divider(),
        version,
        if (syncSettings case final actions?) ...[
          const Divider(),
          actions,
        ],
        for (final section in sections) ...[
          const Divider(),
          const SizedBox(height: 10),
          ...section.children,
        ],
      ],
    );
  }

  void _openAbout(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FinanceCompassAboutPage(syncing: syncing),
      ),
    );
  }

  void _openAdvanced(BuildContext context, String title) {
    if (title == '版本信息') {
      _openAbout(context);
      return;
    }
    final Widget page = switch (title) {
      '个人账户' => AccountSyncPage(repository: repository),
      '货币、汇率与显示' => CurrencyDisplayPage(
          repository: repository,
          settingsController: settingsController,
        ),
      '类别、模板与周期规则' => FinanceRulesCenterPage(repository: repository),
      '备份、恢复与迁移' => BackupRestorePage(repository: repository),
      '导入与导出' => ImportExportPage(repository: repository),
      '外观与主题' => AppearancePage(
          settingsController: settingsController,
          baseCurrency: repository.baseCurrency,
        ),
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
  const FinanceCompassAboutPage({super.key, this.syncing = false});

  final bool syncing;

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
          padding: compassScrollPadding(context, compassPagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
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
                  const Text('当前版本 $_financeVersionDisplay'),
                  const SizedBox(height: 12),
                  if (syncing)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.cloud_done_outlined),
                        title: Text('自托管账本'),
                        trailing: CompassHelpButton(
                          title: '自托管账本',
                          message:
                              '已登录设备共享同一账本。退出后可切换到独立的离线本地账本，也可以下载 JSON 备份。',
                        ),
                      ),
                    )
                  else ...[
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.shield_outlined),
                        title: Text('本机账本'),
                        trailing: CompassHelpButton(
                          title: '本机账本',
                          message: '财务资料保存在本机。导出或分享由你主动发起。',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.language_outlined),
                        title: Text('Web 离线本地模式'),
                        trailing: CompassHelpButton(
                          title: 'Web 离线本地模式',
                          message:
                              '账本保存在当前浏览器，各设备独立使用。清除网站数据会删除本地账本，请定期导出 JSON。',
                        ),
                      ),
                    ),
                  ],
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
                    onPressed: () =>
                        _openUrl(context, _financeCompassIssuesUrl),
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('报告问题'),
                  ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'Finance Compass',
                    ),
                    child: const Text('授权信息'),
                  ),
                  const Divider(height: 32),
                  CompassHelpHeading(
                    title: Text(
                      '请开发者喝杯咖啡',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    label: '自愿支持',
                    message: '支持完全自愿，应用功能和服务权益与支持无关。'
                        '二维码是静态图片。应用不接入支付 SDK，也不读取付款结果。',
                  ),
                  const Text('自愿支持。付款前请确认收款人是 LAW PO WEN。'),
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
                ],
              ),
            ),
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
    '版本信息',
  ];

  static const _searchAliases = <String, List<String>>{
    '外观与主题': ['主题', '外观', '黑白极简', '多巴胺', '苹果液态玻璃', 'theme', 'appearance'],
  };

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
    final normalized = query.trim().toLowerCase();
    final matches = entries.where((entry) {
      if (normalized.isEmpty || entry.toLowerCase().contains(normalized)) {
        return true;
      }
      final aliases = _searchAliases[entry];
      return aliases != null &&
          aliases.any((alias) => alias.toLowerCase().contains(normalized));
    }).toList();
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

class _SettingsSection {
  const _SettingsSection({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  List<Widget> get children => [
        _SettingsGroupTitle(title),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          rows[index],
        ],
      ];

  Widget desktopCard() => CompassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class _SettingsGroupTitle extends StatelessWidget {
  const _SettingsGroupTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: palette.monochrome ? palette.textPrimary : palette.seed,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LocalProfileRow extends StatelessWidget {
  const _LocalProfileRow({required this.onTap, required this.syncing});

  final VoidCallback onTap;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: palette.seed,
              child: Text(
                'L',
                style: TextStyle(color: financeForegroundOn(palette.seed)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(syncing ? '个人账户 · 同步模式' : '个人账户 · 本地模式',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(syncing ? '已登录自托管账本' : '账本保存在当前设备',
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
