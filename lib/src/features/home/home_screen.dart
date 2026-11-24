import 'dart:ui' show ImageFilter;

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
import '../shared/compass_loading.dart';
import '../shared/compass_ui.dart';
import '../settings/settings_v2_screen.dart';
import '../transactions/transactions_v2_screen.dart';

const _workspaceMaxWidth = 1240.0;

const _destinations = [
  (
    label: '总览',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
  ),
  (
    label: '账户',
    icon: Icons.wallet_outlined,
    selectedIcon: Icons.wallet_rounded,
  ),
  (
    label: '交易',
    icon: Icons.swap_horiz_rounded,
    selectedIcon: Icons.swap_horiz_rounded,
  ),
  (
    label: '预算',
    icon: Icons.pie_chart_outline_rounded,
    selectedIcon: Icons.pie_chart_rounded,
  ),
  (
    label: '报表',
    icon: Icons.bar_chart_rounded,
    selectedIcon: Icons.bar_chart_rounded,
  ),
  (
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];

class FinanceWorkspaceNavigation {
  final _keys = List.generate(
    _destinations.length,
    (_) => GlobalKey<NavigatorState>(),
    growable: false,
  );

  bool get hasOpenPage =>
      _keys.any((key) => key.currentState?.canPop() ?? false);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.settingsController,
    this.syncSettings,
    this.workspaceNavigation,
  });

  final AppSettingsController settingsController;
  final Widget? syncSettings;
  final FinanceWorkspaceNavigation? workspaceNavigation;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int selectedIndex = 0;
  final _openedTabs = <int>{0};
  late final _navigation =
      widget.workspaceNavigation ?? FinanceWorkspaceNavigation();
  bool _showedLoading = false;
  bool _openedWorkspace = false;

  void _selectDestination(int index) {
    if (selectedIndex == index) {
      _navigation._keys[index].currentState?.maybePop();
      return;
    }
    setState(() {
      _openedTabs.add(index);
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repositoryAsync = ref.watch(financeRepositoryProvider);
    final desktop = MediaQuery.sizeOf(context).width >= compassDesktopMinWidth;
    final palette = paletteForStyle(widget.settingsController.themeStyle);
    final workspaceBackground = BoxDecoration(
      gradient: LinearGradient(
        colors: [
          palette.backgroundTop,
          palette.background,
          palette.backgroundBottom,
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );

    return repositoryAsync.when(
      loading: () {
        _showedLoading = true;
        return DecoratedBox(
          decoration: workspaceBackground,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: const SafeArea(child: CompassWorkspaceLoading()),
          ),
        );
      },
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
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        final reveal = _showedLoading && !_openedWorkspace && !reducedMotion;
        _openedWorkspace = true;
        setActiveBaseCurrency(repository.baseCurrency);
        setCompassMoneyStyle(
          useCurrencyCode:
              repository.metaValues['currency_symbol_style'] != 'symbol',
          useEuropeanSeparators:
              repository.metaValues['number_separator_style'] == 'space_comma',
        );
        final screens = <Widget Function()>[
          () => DashboardV2Screen(
                repository: repository,
                onOpenAccounts: () => _selectDestination(1),
                onOpenBudgets: () => _selectDestination(3),
              ),
          () => AccountsV2Screen(repository: repository),
          () => TransactionsV2Screen(repository: repository),
          () => BudgetsV2Screen(repository: repository),
          () => ReportsV2Screen(repository: repository),
          () => SettingsV2Screen(
                repository: repository,
                settingsController: widget.settingsController,
                syncing: ref.watch(ledgerSyncSessionProvider) != null,
                syncSettings: widget.syncSettings,
              ),
        ];

        return DecoratedBox(
          decoration: workspaceBackground,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: desktop ? _workspaceMaxWidth : double.infinity,
                  height: double.infinity,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reveal ? 0.0 : 1.0, end: 1.0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    builder: (context, progress, child) {
                      final opacity = reducedMotion ? 1.0 : progress;
                      return Opacity(
                        opacity: opacity,
                        alwaysIncludeSemantics: true,
                        child: Transform.translate(
                          offset: Offset(0, 3 * (1 - opacity)),
                          child: child,
                        ),
                      );
                    },
                    child: IndexedStack(
                      index: selectedIndex,
                      children: [
                        for (var i = 0; i < screens.length; i++)
                          if (_openedTabs.contains(i))
                            _WorkspaceTab(
                              navigatorKey: _navigation._keys[i],
                              active: selectedIndex == i,
                              child: screens[i](),
                            )
                          else
                            const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: _CompassDock(
              desktop: desktop,
              palette: palette,
              selectedIndex: selectedIndex,
              onSelected: _selectDestination,
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.navigatorKey,
    required this.active,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: active,
      child: FocusScope(
        descendantsAreFocusable: active,
        descendantsAreTraversable: active,
        child: NavigatorPopHandler<Object?>(
          enabled: active,
          onPopWithResult: (result) {
            if (active) navigatorKey.currentState?.maybePop(result);
          },
          child: HeroControllerScope.none(
            child: Navigator(
              key: navigatorKey,
              onDidRemovePage: (_) {},
              pages: [
                MaterialPage<void>(
                  key: const ValueKey('tab-root'),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompassDock extends StatelessWidget {
  const _CompassDock({
    required this.desktop,
    required this.palette,
    required this.selectedIndex,
    required this.onSelected,
  });

  final bool desktop;
  final FinanceThemePalette palette;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    final height = desktop ? 62.0 : 58.0;
    final iconSize = desktop ? 23.0 : 21.0;
    final selectedRadius = BorderRadius.circular(13);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: desktop ? 424 : 350),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: .86),
                    border: Border.all(color: palette.border),
                    borderRadius: radius,
                    boxShadow: [
                      if (!palette.monochrome)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .17),
                          blurRadius: 18,
                          offset: const Offset(0, 5),
                        ),
                    ],
                  ),
                  child: NavigationBarTheme(
                    data: NavigationBarTheme.of(context).copyWith(
                      iconTheme: WidgetStatePropertyAll(
                        IconThemeData(size: iconSize, color: palette.textMuted),
                      ),
                      labelTextStyle: WidgetStateProperty.resolveWith(
                        (states) => TextStyle(
                          fontSize: 11,
                          height: 1.15,
                          color: states.contains(WidgetState.selected)
                              ? palette.seed
                              : palette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    child: NavigationBar(
                      height: height,
                      selectedIndex: selectedIndex,
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      indicatorColor: Colors.transparent,
                      animationDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: [
                        for (final destination in _destinations)
                          NavigationDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.monochrome
                                    ? palette.surfaceAlt
                                    : palette.seed.withValues(alpha: .17),
                                borderRadius: selectedRadius,
                              ),
                              child: SizedBox.square(
                                dimension: 31,
                                child: Icon(destination.selectedIcon,
                                    color: palette.seed),
                              ),
                            ),
                            label: destination.label,
                            tooltip: '',
                          ),
                      ],
                      onDestinationSelected: onSelected,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
