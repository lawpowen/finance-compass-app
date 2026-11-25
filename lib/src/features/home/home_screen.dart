import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/gestures.dart' show PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
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
import '../settings/settings_screen.dart';
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
  FinanceRepository? _cachedRepository;
  bool? _cachedSyncing;
  Widget? _cachedSyncSettings;
  AppSettingsController? _cachedSettingsController;
  final List<Widget?> _cachedTabScreens =
      List<Widget?>.filled(_destinations.length, null);

  int? _rateEditorTab;

  Future<void> _openRateEditor(FinanceRepository repository) async {
    if (_rateEditorTab case final int openTab) {
      if (openTab != selectedIndex) _selectDestination(openTab);
      return;
    }
    final navigator = _navigation._keys[selectedIndex].currentState;
    if (navigator == null) return;
    setState(() => _rateEditorTab = selectedIndex);
    try {
      await navigator.push<void>(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('编辑货币与汇率')),
          body: SettingsScreen(
            repository: repository,
            settingsController: widget.settingsController,
          ),
        ),
      ));
    } finally {
      if (mounted) setState(() => _rateEditorTab = null);
    }
  }

  Widget _tabScreenFor(int index, FinanceRepository repository, bool syncing) {
    return _cachedTabScreens[index] ??= switch (index) {
      0 => DashboardV2Screen(
          repository: repository,
          onOpenAccounts: () => _selectDestination(1),
          onOpenTransactions: () => _selectDestination(2),
          onOpenBudgets: () => _selectDestination(3),
        ),
      1 => AccountsV2Screen(repository: repository),
      2 => TransactionsV2Screen(repository: repository),
      3 => BudgetsV2Screen(repository: repository),
      4 => ReportsV2Screen(repository: repository),
      _ => SettingsV2Screen(
          repository: repository,
          settingsController: widget.settingsController,
          syncing: syncing,
          syncSettings: widget.syncSettings,
        ),
    };
  }

  void _selectDestination(int index) {
    if (selectedIndex == index) {
      _navigation._keys[index].currentState?.popUntil((route) => route.isFirst);
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

    return repositoryAsync.when(
      loading: () {
        _showedLoading = true;
        return Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: RepaintBoundary(child: CompassBackdropLayer()),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              body: const SafeArea(child: CompassWorkspaceLoading()),
            ),
          ],
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
        final unpriced = repository.unpricedCurrencies;
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
        final syncing = ref.watch(ledgerSyncSessionProvider) != null;
        if (!identical(_cachedRepository, repository) ||
            _cachedSyncing != syncing ||
            !identical(_cachedSyncSettings, widget.syncSettings) ||
            !identical(_cachedSettingsController, widget.settingsController)) {
          _cachedRepository = repository;
          _cachedSyncing = syncing;
          _cachedSyncSettings = widget.syncSettings;
          _cachedSettingsController = widget.settingsController;
          _cachedTabScreens.fillRange(0, _cachedTabScreens.length, null);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: RepaintBoundary(child: CompassBackdropLayer()),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              body: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: desktop ? _workspaceMaxWidth : double.infinity,
                    height: double.infinity,
                    child: Column(children: [
                      if (unpriced.isNotEmpty)
                        Material(
                          key: const Key('missing-exchange-rates'),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 16, end: 8),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(
                                  "${unpriced.take(3).join('、')}${unpriced.length > 3 ? ' 等 ${unpriced.length} 种币种' : ''} 未估值，合计仅含有汇率的金额。",
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                )),
                                TextButton(
                                  onPressed: _rateEditorTab == selectedIndex
                                      ? null
                                      : () => _openRateEditor(repository),
                                  child: const Text('设置汇率'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
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
                              for (var i = 0; i < _destinations.length; i++)
                                if (_openedTabs.contains(i))
                                  _WorkspaceTab(
                                    navigatorKey: _navigation._keys[i],
                                    active: selectedIndex == i,
                                    child:
                                        _tabScreenFor(i, repository, syncing),
                                  )
                                else
                                  const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ),
                    ]),
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
          ],
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

class _CompassDock extends StatefulWidget {
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
  State<_CompassDock> createState() => _CompassDockState();
}

class _CompassDockState extends State<_CompassDock> {
  int? _hoveredIndex;
  ({Duration time, Offset position})? _lastTouch;

  bool _supportsHover(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

  void _updateHover(PointerEvent event, double width) {
    if (!_supportsHover(event.kind) || width <= 0) return;
    if (_lastTouch case final touch?
        when event.kind == PointerDeviceKind.mouse) {
      final elapsed = event.timeStamp - touch.time;
      // Mobile browsers can synthesize mouse hover at the touch location.
      if (!elapsed.isNegative &&
          elapsed < const Duration(milliseconds: 500) &&
          (event.position - touch.position).distance < 24) {
        return;
      }
    }
    final slotWidth = width / _destinations.length;
    final slot = (event.localPosition.dx / slotWidth)
        .floor()
        .clamp(0, _destinations.length - 1)
        .toInt();
    final index = Directionality.of(context) == TextDirection.rtl
        ? _destinations.length - 1 - slot
        : slot;
    if (index != _hoveredIndex) {
      setState(() => _hoveredIndex = index);
    }
  }

  void _clearTouchHover(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _lastTouch = (time: event.timeStamp, position: event.position);
    _clearHover();
  }

  void _clearHover() {
    if (_hoveredIndex != null) {
      setState(() => _hoveredIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = widget.desktop;
    final palette = widget.palette;
    final selectedIndex = widget.selectedIndex;
    final radius = BorderRadius.circular(999);
    final height = desktop ? 62.0 : 58.0;
    final iconSize = desktop ? 24.0 : 22.0;
    final cpuSoftwareWeb = compassIsCpuSoftwareWeb;
    final isLiquidGlass = palette.glassHighlightColor != null;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final enableBlur = !cpuSoftwareWeb && palette.dockBlurSigma > 0;
    final effectiveSigma = math.min(palette.dockBlurSigma, 20.0);
    final effectiveSurfaceAlpha = cpuSoftwareWeb
        ? math.max(
            palette.dockSurfaceAlpha,
            isLiquidGlass ? 0.93 : 0.96,
          )
        : palette.dockSurfaceAlpha;
    final dockSurfaceDecoration = isLiquidGlass
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: cpuSoftwareWeb
                  ? [
                      Colors.white.withValues(alpha: .88),
                      const Color(0xFFE6F4FF).withValues(alpha: .82),
                      Colors.white.withValues(alpha: .86),
                    ]
                  : [
                      Colors.white.withValues(alpha: .64),
                      const Color(0xFFE6F4FF).withValues(alpha: .48),
                      Colors.white.withValues(alpha: .58),
                    ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: .72),
              width: 1.0,
            ),
            borderRadius: radius,
          )
        : BoxDecoration(
            color: palette.surface.withValues(alpha: effectiveSurfaceAlpha),
            border: Border.all(color: palette.border),
            borderRadius: radius,
          );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: desktop ? 424 : 350),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dockWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Listener(
                      onPointerDown: _clearTouchHover,
                      onPointerUp: _clearTouchHover,
                      child: MouseRegion(
                        onEnter: (event) => _updateHover(event, dockWidth),
                        onHover: (event) => _updateHover(event, dockWidth),
                        onExit: (event) {
                          if (_supportsHover(event.kind)) _clearHover();
                        },
                        child: RepaintBoundary(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              boxShadow: [
                                if (palette.dockShadowColor case final shadow?)
                                  BoxShadow(
                                    color: shadow,
                                    blurRadius: cpuSoftwareWeb
                                        ? 0
                                        : (isLiquidGlass ? 22 : 14),
                                    offset: Offset(
                                      0,
                                      cpuSoftwareWeb
                                          ? 1
                                          : (isLiquidGlass ? 8 : 4),
                                    ),
                                  )
                                else if (!palette.monochrome)
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .17),
                                    blurRadius: cpuSoftwareWeb ? 0 : 14,
                                    offset: Offset(0, cpuSoftwareWeb ? 1 : 4),
                                  ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: radius,
                              child: BackdropFilter(
                                enabled: enableBlur,
                                filter: ImageFilter.blur(
                                  sigmaX: effectiveSigma,
                                  sigmaY: effectiveSigma,
                                  tileMode: TileMode.clamp,
                                ),
                                child: compassGlassHighlight(
                                  color: palette.glassHighlightColor,
                                  borderRadius: radius,
                                  child: DecoratedBox(
                                    decoration: dockSurfaceDecoration,
                                    child: NavigationBarTheme(
                                      data: NavigationBarTheme.of(context)
                                          .copyWith(
                                        iconTheme: WidgetStatePropertyAll(
                                          IconThemeData(
                                            size: iconSize,
                                            color: palette.textMuted,
                                          ),
                                        ),
                                        overlayColor:
                                            WidgetStateProperty.resolveWith(
                                          (states) => states
                                                  .contains(WidgetState.pressed)
                                              ? palette.seed
                                                  .withValues(alpha: .10)
                                              : Colors.transparent,
                                        ),
                                        labelTextStyle:
                                            WidgetStateProperty.resolveWith(
                                          (states) => TextStyle(
                                            fontSize: 11,
                                            height: 1.15,
                                            color: states.contains(
                                                    WidgetState.selected)
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
                                        animationDuration: disableAnimations
                                            ? Duration.zero
                                            : const Duration(milliseconds: 180),
                                        labelBehavior:
                                            NavigationDestinationLabelBehavior
                                                .alwaysHide,
                                        destinations: [
                                          for (var i = 0;
                                              i < _destinations.length;
                                              i++)
                                            NavigationDestination(
                                              icon: _DockAnimatedIcon(
                                                index: i,
                                                icon: i == selectedIndex
                                                    ? _destinations[i]
                                                        .selectedIcon
                                                    : _destinations[i].icon,
                                                selected: i == selectedIndex,
                                                hoveredIndex: _hoveredIndex,
                                                desktop: desktop,
                                                palette: palette,
                                                cpuSoftwareWeb: cpuSoftwareWeb,
                                                disableAnimations:
                                                    disableAnimations,
                                              ),
                                              label: _destinations[i].label,
                                              tooltip: '',
                                            ),
                                        ],
                                        onDestinationSelected:
                                            widget.onSelected,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _DockFloatingLabel(
                      hoveredIndex: _hoveredIndex,
                      dockWidth: dockWidth,
                      dockHeight: height,
                      palette: palette,
                      cpuSoftwareWeb: cpuSoftwareWeb,
                      disableAnimations: disableAnimations,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DockAnimatedIcon extends StatelessWidget {
  const _DockAnimatedIcon({
    required this.index,
    required this.icon,
    required this.selected,
    required this.hoveredIndex,
    required this.desktop,
    required this.palette,
    required this.cpuSoftwareWeb,
    required this.disableAnimations,
  });

  final int index;
  final IconData icon;
  final bool selected;
  final int? hoveredIndex;
  final bool desktop;
  final FinanceThemePalette palette;
  final bool cpuSoftwareWeb;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final isLiquidGlass = palette.glassHighlightColor != null;
    final distance =
        hoveredIndex == null ? null : (index - hoveredIndex!).abs();
    final isHovered = distance == 0;
    final isNeighbor = distance == 1;

    final double scale;
    final double liftY;
    if (isHovered) {
      scale = selected ? (desktop ? 1.18 : 1.12) : (desktop ? 1.22 : 1.15);
      liftY = desktop ? -4.0 : -3.5;
    } else if (isNeighbor) {
      scale = 1.07;
      liftY = -1.8;
    } else if (selected) {
      scale = 1.04;
      liftY = -1.0;
    } else {
      scale = 1.0;
      liftY = 0.0;
    }

    final duration =
        disableAnimations ? Duration.zero : const Duration(milliseconds: 210);
    // A bounded curve keeps the capsule inside the pill on interrupted hovers.
    const curve = Curves.easeOutCubic;
    final showCapsule = selected || isHovered;
    final Color? capsuleColor = switch ((isLiquidGlass, selected, isHovered)) {
      (true, true, _) => null,
      (true, false, true) => Colors.white.withValues(alpha: .50),
      (false, true, _) => palette.selectedSurface ??
          (palette.monochrome
              ? palette.surfaceAlt
              : palette.seed.withValues(alpha: .17)),
      (false, false, true) => palette.seed.withValues(alpha: .10),
      _ => null,
    };

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: liftY),
      duration: duration,
      curve: curve,
      builder: (context, dy, child) => Transform.translate(
        offset: Offset(0, dy),
        transformHitTests: false,
        child: child,
      ),
      child: AnimatedScale(
        scale: scale,
        duration: duration,
        curve: curve,
        alignment: Alignment.center,
        child: AnimatedContainer(
          key: Key('compass-dock-icon-$index'),
          duration: duration,
          curve: curve,
          width: desktop ? 44 : 36,
          height: desktop ? 32 : 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: capsuleColor,
            gradient: isLiquidGlass && selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: .94),
                      const Color(0xFFD6EEFF).withValues(alpha: .78),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(999),
            border: isLiquidGlass && showCapsule
                ? Border.all(
                    color: Colors.white.withValues(alpha: selected ? .90 : .72),
                  )
                : null,
            boxShadow: [
              if (!cpuSoftwareWeb && (isHovered || isLiquidGlass && selected))
                BoxShadow(
                  color: isLiquidGlass
                      ? const Color(0x2B0A6ED1)
                      : palette.seed.withValues(alpha: .18),
                  blurRadius: desktop ? 2.5 : 1.5,
                  spreadRadius: -1.5,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Icon(
            icon,
            color: showCapsule ? palette.seed : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _DockFloatingLabel extends StatelessWidget {
  const _DockFloatingLabel({
    required this.hoveredIndex,
    required this.dockWidth,
    required this.dockHeight,
    required this.palette,
    required this.cpuSoftwareWeb,
    required this.disableAnimations,
  });

  final int? hoveredIndex;
  final double dockWidth;
  final double dockHeight;
  final FinanceThemePalette palette;
  final bool cpuSoftwareWeb;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final index = hoveredIndex;
    if (index == null) return const SizedBox.shrink();

    final pillBoxWidth = math.min(92.0, dockWidth);
    final slotCenter = (index + 0.5) * (dockWidth / _destinations.length);
    final start = (slotCenter - pillBoxWidth / 2)
        .clamp(0.0, dockWidth - pillBoxWidth)
        .toDouble();
    final isLiquidGlass = palette.glassHighlightColor != null;
    final radius = BorderRadius.circular(999);
    final bg = (palette.monochrome ? palette.textPrimary : palette.seed)
        .withValues(alpha: 1);
    // At this luminance black and white have equal contrast against the fill.
    final fg = bg.computeLuminance() > .179 ? Colors.black : Colors.white;
    final contents = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      child: Text(
        _destinations[index].label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: 12,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: isLiquidGlass ? const Color(0xFF15283B) : fg,
        ),
      ),
    );

    final Widget pill;
    if (isLiquidGlass) {
      pill = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            if (!cpuSoftwareWeb)
              const BoxShadow(
                color: Color(0x2B0A6ED1),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            enabled: !cpuSoftwareWeb,
            filter: ImageFilter.blur(
              sigmaX: 14,
              sigmaY: 14,
              tileMode: TileMode.clamp,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: .92),
                    const Color(0xFFE6F4FF).withValues(alpha: .84),
                  ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .94),
                  width: 1,
                ),
              ),
              child: contents,
            ),
          ),
        ),
      );
    } else {
      pill = DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          boxShadow: [
            if (!cpuSoftwareWeb)
              BoxShadow(
                color: palette.monochrome
                    ? Colors.black.withValues(alpha: .16)
                    : palette.seed.withValues(alpha: .28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: contents,
      );
    }

    return AnimatedPositionedDirectional(
      start: start,
      bottom: dockHeight + 10,
      width: pillBoxWidth,
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 6),
                child: Transform.scale(
                  scale: 0.92 + 0.08 * t,
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: const Key('compass-dock-hover-label'),
                child: pill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
