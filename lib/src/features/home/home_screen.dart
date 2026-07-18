import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_provider.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../accounts/accounts_v2_screen.dart';
import '../budgets/budgets_v2_screen.dart';
import '../dashboard/dashboard_v2_screen.dart';
import '../reports/reports_v2_screen.dart';
import '../settings/settings_v2_screen.dart';
import '../transactions/transactions_v2_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.settingsController});

  final AppSettingsController settingsController;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final repositoryAsync = ref.watch(financeRepositoryProvider);

    return repositoryAsync.when(
      loading: () => const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to open finance database: $error'),
            ),
          ),
        ),
      ),
      data: (repository) {
        setActiveBaseCurrency(repository.baseCurrency);
        final palette = paletteForStyle(widget.settingsController.themeStyle);
        final screens = [
          DashboardV2Screen(repository: repository),
          AccountsV2Screen(repository: repository),
          TransactionsV2Screen(repository: repository),
          BudgetsV2Screen(repository: repository),
          ReportsV2Screen(repository: repository),
          SettingsV2Screen(
            repository: repository,
            settingsController: widget.settingsController,
          ),
        ];

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.backgroundTop,
                palette.background,
                palette.backgroundBottom,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              bottom: false,
              child: IndexedStack(index: selectedIndex, children: screens),
            ),
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.background.withValues(alpha: .97),
                border: Border(
                  top: BorderSide(
                    color: palette.border.withValues(alpha: .65),
                    width: .7,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: selectedIndex,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: '总览',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.wallet_outlined),
                    selectedIcon: Icon(Icons.wallet_rounded),
                    label: '账户',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.swap_horiz_rounded),
                    label: '交易',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.pie_chart_outline_rounded),
                    selectedIcon: Icon(Icons.pie_chart_rounded),
                    label: '预算',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bar_chart_rounded),
                    label: '报表',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '设置',
                  ),
                ],
                onDestinationSelected: (index) {
                  setState(() => selectedIndex = index);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
