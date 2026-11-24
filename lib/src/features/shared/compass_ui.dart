import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show kIsWeb, listEquals, visibleForTesting;
import 'package:flutter/material.dart';

import '../../core/theme/finance_colors.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/currency_formatter.dart' show activeBaseCurrencyCode;

/// Allows tests to simulate the Android CPU-only CanvasKit rendering path.
@visibleForTesting
bool? debugOverrideCompassCpuSoftwareWeb;

/// Returns true when the Web runtime explicitly selects CPU software CanvasKit
/// (via `?cpu=1`), or when overridden in tests.
bool get compassIsCpuSoftwareWeb =>
    debugOverrideCompassCpuSoftwareWeb ??
    (kIsWeb && Uri.base.queryParameters.containsKey('cpu'));

const compassPagePadding = EdgeInsets.fromLTRB(20, 16, 20, 28);
const compassDesktopPagePadding = EdgeInsets.fromLTRB(28, 24, 28, 32);
const compassDesktopMinWidth = 960.0;
const compassHairline = Divider(height: 1, thickness: .7);
const compassTabularFigures = [FontFeature.tabularFigures()];

EdgeInsets compassScrollPadding(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(
      bottom: padding.bottom + MediaQuery.paddingOf(context).bottom,
    );
bool _compassUseCurrencyCode = true;
bool _compassUseEuropeanSeparators = false;

void setCompassMoneyStyle({
  required bool useCurrencyCode,
  required bool useEuropeanSeparators,
}) {
  _compassUseCurrencyCode = useCurrencyCode;
  _compassUseEuropeanSeparators = useEuropeanSeparators;
}

String compassMoney(
  double value, {
  String? currency,
  int decimals = 2,
  bool showCurrency = true,
}) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(decimals).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => _compassUseEuropeanSeparators ? ' ' : ',',
  );
  final decimalMark = _compassUseEuropeanSeparators ? ',' : '.';
  final fraction = decimals == 0 ? '' : '$decimalMark${parts.last}';
  if (!showCurrency) return '${negative ? '-' : ''}$grouped$fraction';
  final displayCurrency = currency ?? activeBaseCurrencyCode;
  final prefix = _compassUseCurrencyCode
      ? displayCurrency
      : switch (displayCurrency.toUpperCase()) {
          'MYR' => 'RM',
          'USD' => 'US\$',
          'CNY' => 'RMB',
          'TWD' => 'NT\$',
          _ => displayCurrency,
        };
  return '${negative ? '- ' : ''}$prefix $grouped$fraction';
}

class CompassBackdropLayer extends StatelessWidget {
  const CompassBackdropLayer({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        colors: palette.backgroundGradientColors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    if (palette.glassHighlightColor == null) {
      return DecoratedBox(
        decoration: decoration,
        child: child ?? const SizedBox.expand(),
      );
    }
    // The ambient blooms are static: isolate the scrolling page content in its
    // own layer so content repaints never re-rasterize the aurora picture.
    return DecoratedBox(
      decoration: decoration,
      child: CustomPaint(
        painter: const _LiquidGlassAmbientPainter(),
        isComplex: true,
        child: child == null
            ? const SizedBox.expand()
            : RepaintBoundary(child: child),
      ),
    );
  }
}

class _LiquidGlassAmbientPainter extends CustomPainter {
  const _LiquidGlassAmbientPainter();

  /// Azure, iris, aqua, ice and a soft pearl key light. Positions/radii are
  /// fractions of the viewport so the composition holds from 320px to desktop.
  static const _blooms = <({double dx, double dy, double r, Color color})>[
    (dx: .10, dy: .06, r: .58, color: Color(0x7A5EC0FF)),
    (dx: .92, dy: .15, r: .50, color: Color(0x669FA8FF)),
    (dx: .18, dy: .56, r: .50, color: Color(0x5E4CD4DE)),
    (dx: .86, dy: .86, r: .56, color: Color(0x54B6D8FF)),
    (dx: .58, dy: .32, r: .30, color: Color(0x5CFFFFFF)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final extent = math.max(size.width, size.height);
    for (final bloom in _blooms) {
      final center = Offset(size.width * bloom.dx, size.height * bloom.dy);
      final radius = extent * bloom.r;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final c = bloom.color;
      // Eased (gaussian-like) falloff hides 8-bit banding through the blur.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              c,
              c.withValues(alpha: c.a * .64),
              c.withValues(alpha: c.a * .24),
              c.withValues(alpha: c.a * .06),
              c.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.34, 0.64, 0.86, 1.0],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_LiquidGlassAmbientPainter oldDelegate) => false;
}

class CompassBackground extends StatelessWidget {
  const CompassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CompassBackdropLayer(child: child);
}

/// Paints a glass rim without adding layout padding or a gesture layer.
///
/// [intensity] scales the interior sheen/caustics (0..1); use a lower value on
/// saturated fills (buttons) so white-on-colour labels keep their contrast.
Widget compassGlassHighlight({
  required Color? color,
  required BorderRadius borderRadius,
  required Widget child,
  double intensity = 1,
}) {
  if (color == null) return child;
  return CustomPaint(
    foregroundPainter: _CompassGlassHighlightPainter(
      color,
      borderRadius,
      intensity.clamp(0.0, 1.0).toDouble(),
    ),
    child: child,
  );
}

class _CompassGlassHighlightPainter extends CustomPainter {
  const _CompassGlassHighlightPainter(
    this.color,
    this.borderRadius, [
    this.intensity = 1,
  ]);

  final Color color;
  final BorderRadius borderRadius;
  final double intensity;

  static const _caustic = Color(0xFF8FE6FF);
  static const _iris = Color(0xFFC7B8FF);
  static const _bevelShadow = Color(0xFF0A3D66);

  Color _light(double alpha) => color.withValues(alpha: color.a * alpha);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 4 || size.height <= 4) return;
    final k = intensity;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(borderRadius.toRRect(bounds));

    // 1. Soft top sheen band (pixel-capped so tall cards stay clear below).
    final sheenRect =
        Rect.fromLTWH(0, 0, size.width, math.min(size.height * .5, 72));
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_light(.18 * k), _light(.05 * k), _light(0)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(sheenRect),
    );

    // 2. Curved specular crescent hugging the top-left corner.
    final glowRadius = math.min(size.shortestSide * 1.1, 150.0);
    final glowCenter = Offset(glowRadius * .16, glowRadius * .04);
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [_light(.30 * k), _light(.10 * k), _light(0)],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    // 3. Prismatic cyan/iris caustic bounce on the opposite (bottom-right) rim.
    final causticRadius = math.min(size.shortestSide * .9, 120.0);
    final causticCenter = Offset(
      size.width - causticRadius * .12,
      size.height - causticRadius * .04,
    );
    canvas.drawCircle(
      causticCenter,
      causticRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _caustic.withValues(alpha: .16 * k),
            _iris.withValues(alpha: .08 * k),
            _iris.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: causticCenter, radius: causticRadius),
        ),
    );
    canvas.restore();

    // 4. Crisp Fresnel rim: bright at the lit corner, prismatic on the far rim.
    final rimK = .6 + .4 * k;
    final outerBounds = bounds.deflate(0.65);
    canvas.drawRRect(
      borderRadius.toRRect(outerBounds),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _light(1.0 * rimK),
            _light(.30 * rimK),
            _caustic.withValues(alpha: .30 * rimK),
            _iris.withValues(alpha: .34 * rimK),
            _light(.74 * rimK),
          ],
          stops: const [0.0, 0.32, 0.62, 0.82, 1.0],
        ).createShader(outerBounds),
    );

    // 5. Inner bevel: lit top lip fading into a faint lower shadow for depth.
    if (size.width > 8 && size.height > 8) {
      final innerBounds = bounds.deflate(1.8);
      canvas.drawRRect(
        borderRadius.toRRect(innerBounds),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _light(.42 * rimK),
              _light(0),
              _bevelShadow.withValues(alpha: .14),
            ],
            stops: const [0.0, 0.42, 1.0],
          ).createShader(innerBounds),
      );
    }
  }

  @override
  bool shouldRepaint(_CompassGlassHighlightPainter oldDelegate) =>
      color != oldDelegate.color ||
      borderRadius != oldDelegate.borderRadius ||
      intensity != oldDelegate.intensity;
}

class CompassPageHeader extends StatelessWidget {
  const CompassPageHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.subtitle,
    this.leading,
    this.centered = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          if (centered) const Spacer(),
          if (centered) titleWidget else Expanded(child: titleWidget),
          if (centered) const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class CompassBackButton extends StatelessWidget {
  const CompassBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed ?? () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
      );
}

class CompassCard extends StatelessWidget {
  const CompassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.radius = 20,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final borderRadius = BorderRadius.circular(radius);
    final cpuSoftware = compassIsCpuSoftwareWeb;
    final isLiquidGlass = palette.glassHighlightColor != null;
    final usesBackdropBlur = !cpuSoftware && palette.cardBlurSigma > 0;
    final inner = Padding(
      padding: padding,
      child: child,
    );
    final interactiveInner = onTap == null
        ? inner
        : Material(
            color: Colors.transparent,
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              child: inner,
            ),
          );
    final cardShadows = [
      if (palette.cardShadowColor case final shadow?)
        BoxShadow(
          color: shadow,
          blurRadius: cpuSoftware ? 0 : (isLiquidGlass ? 18 : 10),
          offset: Offset(0, cpuSoftware ? 1 : (isLiquidGlass ? 8 : 2)),
        ),
    ];
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: isLiquidGlass && color == null
            ? null
            : (color ?? palette.resolvedCardSurface),
        gradient: isLiquidGlass && color == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: cpuSoftware
                    ? [
                        Colors.white.withValues(alpha: .84),
                        palette.resolvedCardSurface.withValues(alpha: .78),
                        const Color(0xFFEAF5FF).withValues(alpha: .82),
                      ]
                    : [
                        Colors.white.withValues(alpha: .68),
                        palette.resolvedCardSurface,
                        const Color(0xFFEAF5FF).withValues(alpha: .56),
                      ],
              )
            : null,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ??
              (isLiquidGlass
                  ? Colors.white.withValues(alpha: .62)
                  : palette.border),
          width: isLiquidGlass || palette.monochrome ? 1.0 : .8,
        ),
        boxShadow: usesBackdropBlur ? const [] : cardShadows,
      ),
      child: interactiveInner,
    );
    final highlightedCard = compassGlassHighlight(
      color: palette.glassHighlightColor,
      borderRadius: borderRadius,
      child: card,
    );
    if (usesBackdropBlur) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: cardShadows,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: palette.cardBlurSigma,
              sigmaY: palette.cardBlurSigma,
              tileMode: TileMode.clamp,
            ),
            child: highlightedCard,
          ),
        ),
      );
    }
    return highlightedCard;
  }
}

class CompassSectionTitle extends StatelessWidget {
  const CompassSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

/// A compact, focusable way to read supplemental guidance on any device.
class CompassHelpButton extends StatelessWidget {
  const CompassHelpButton({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return IconButton(
      tooltip: '查看${title}说明',
      icon: const Icon(Icons.help_outline_rounded, size: 16),
      style: IconButton.styleFrom(
        foregroundColor: palette.textMuted,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(48),
        side: BorderSide.none,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: Text(title),
          content: Text(message),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}

class CompassHelpHeading extends StatelessWidget {
  const CompassHelpHeading({
    super.key,
    required this.title,
    required this.label,
    required this.message,
  });

  final Widget title;
  final String label;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: title),
          CompassHelpButton(title: label, message: message),
        ],
      );
}

class CompassSectionLabel extends StatelessWidget {
  const CompassSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 7),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color ?? palette.seed,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

class CompassIconBadge extends StatelessWidget {
  const CompassIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 46,
    this.outlined = false,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? financePaletteOf(context).seed;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: outlined
            ? Colors.transparent
            : resolvedColor.withValues(alpha: .16),
        shape: BoxShape.circle,
        border: outlined
            ? Border.all(
                color: resolvedColor.withValues(alpha: .72),
                width: 1,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: resolvedColor, size: size * .52),
    );
  }
}

class CompassActionBubble extends StatelessWidget {
  const CompassActionBubble({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.foregroundColor,
    this.borderColor,
    this.heroTag,
    this.size = 56,
    this.elevation = 6,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? foregroundColor;
  final Color? borderColor;
  final Object? heroTag;
  final double size;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final resolvedColor = color ?? palette.seed;
    final resolvedForeground =
        foregroundColor ?? financeForegroundOn(resolvedColor);
    final glass = palette.glassHighlightColor != null;
    final fab = FloatingActionButton(
      heroTag: heroTag,
      onPressed: onPressed,
      backgroundColor: resolvedColor,
      foregroundColor: resolvedForeground,
      elevation: glass ? 0 : elevation,
      highlightElevation: glass ? 0 : null,
      shape: glass
          ? CircleBorder(
              side: BorderSide(
                color: borderColor ?? Colors.white.withValues(alpha: .7),
              ),
            )
          : borderColor == null
              ? const CircleBorder()
              : CircleBorder(side: BorderSide(color: borderColor!)),
      child: Icon(icon, size: size * .48),
    );
    return SizedBox(
      width: size,
      height: size,
      child: glass
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: compassIsCpuSoftwareWeb || elevation <= 0
                    ? const []
                    : [
                        BoxShadow(
                          color: resolvedColor.withValues(alpha: .32),
                          blurRadius: 18,
                          spreadRadius: -3,
                          offset: const Offset(0, 7),
                        ),
                      ],
              ),
              child: compassGlassHighlight(
                color: palette.glassHighlightColor,
                borderRadius: BorderRadius.circular(size / 2),
                intensity: .7,
                child: fab,
              ),
            )
          : fab,
    );
  }
}

class CompassSettingsRow extends StatelessWidget {
  const CompassSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.subtitle,
    this.value,
    this.color,
    this.trailing,
    this.iconSize = 25,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final resolvedColor = color ?? financePaletteOf(context).seed;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Icon(icon, color: resolvedColor, size: iconSize),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (value != null)
            Flexible(
              child: Text(
                value!,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
          if (trailing != null) trailing!,
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(Icons.chevron_right_rounded, color: muted, size: 24),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

class CompassSegmentedControl extends StatelessWidget {
  const CompassSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? palette.selectedSurface ??
                          palette.seed.withValues(alpha: .22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  border: selected
                      ? Border.all(
                          color: palette.seed.withValues(alpha: .32),
                        )
                      : null,
                ),
                child: Text(
                  labels[index],
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color:
                            selected ? palette.textPrimary : palette.textMuted,
                      ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class CompassPrimaryButton extends StatelessWidget {
  const CompassPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final resolvedColor = color ?? palette.resolvedPrimaryAction;
    final outlineColor =
        color ?? (palette.primaryAction == null ? resolvedColor : palette.seed);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final glossy =
        !outlined && palette.glassHighlightColor != null && onPressed != null;
    final radius = BorderRadius.circular(glossy ? 16 : 12);
    final button = outlined
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: outlineColor,
              side: BorderSide(color: outlineColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: child,
          )
        : FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              // Glossy mode paints the liquid fill underneath, so the
              // button itself only contributes ink, focus and semantics.
              backgroundColor: glossy ? Colors.transparent : resolvedColor,
              foregroundColor: financeForegroundOn(resolvedColor),
              shadowColor: glossy ? Colors.transparent : null,
              elevation: glossy ? 0 : null,
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
            child: child,
          );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: glossy
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                // Sapphire-aqua liquid: the lighter lip stays in the top band
                // so the centred label sits on >= 4.5:1 resolved colour.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color == null
                        ? const Color(0xFF1E8AE8)
                        : Color.lerp(resolvedColor, Colors.white, .16)!,
                    resolvedColor,
                    Color.lerp(resolvedColor, const Color(0xFF06396E), .3)!,
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
                boxShadow: compassIsCpuSoftwareWeb
                    ? const []
                    : [
                        BoxShadow(
                          color: resolvedColor.withValues(alpha: .34),
                          blurRadius: 18,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: compassGlassHighlight(
                color: palette.glassHighlightColor,
                borderRadius: radius,
                intensity: .55,
                child: button,
              ),
            )
          : button,
    );
  }
}

class CompassStatusBadge extends StatelessWidget {
  const CompassStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.inverted = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final foreground = inverted ? financeForegroundOn(color) : color;
    // Liquid Glass: frosted pearl capsule with a faint tint and specular lip.
    final frosted =
        !inverted && financePaletteOf(context).glassHighlightColor != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            frosted ? null : (inverted ? color : color.withValues(alpha: .11)),
        gradient: frosted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    color.withValues(alpha: .07),
                    Colors.white.withValues(alpha: .82),
                  ),
                  Color.alphaBlend(
                    color.withValues(alpha: .13),
                    Colors.white.withValues(alpha: .58),
                  ),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(999),
        border: inverted
            ? null
            : Border.all(
                color: frosted
                    ? Color.alphaBlend(
                        color.withValues(alpha: .18),
                        Colors.white.withValues(alpha: .86),
                      )
                    : color.withValues(alpha: .28),
                width: .7,
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.15,
                fontFeatures: compassTabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CompassDualProgressBar extends StatelessWidget {
  const CompassDualProgressBar({
    super.key,
    required this.actualRatio,
    this.plannedRatio = 0,
    this.alertThreshold = 0.8,
    this.height = 6,
    this.actualColor,
    this.plannedColor,
    this.trackColor,
    this.semanticsLabel,
  });

  final double actualRatio;
  final double plannedRatio;
  final double alertThreshold;
  final double height;
  final Color? actualColor;
  final Color? plannedColor;
  final Color? trackColor;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final safeActual =
        actualRatio.isFinite ? actualRatio.clamp(0.0, 1.0).toDouble() : 0.0;
    final safePlanned =
        plannedRatio.isFinite ? plannedRatio.clamp(0.0, 1.0).toDouble() : 0.0;
    final total = (actualRatio.isFinite ? actualRatio : 0.0) +
        (plannedRatio.isFinite ? plannedRatio : 0.0);
    final resolvedActualColor = actualColor ??
        (total > 1.0
            ? palette.expense
            : total >= alertThreshold
                ? palette.warning
                : palette.seed);
    final resolvedPlannedColor = plannedColor ?? resolvedActualColor;
    final resolvedTrackColor = trackColor ?? palette.surfaceAlt;

    final bar = SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: _CompassDualProgressPainter(
          actualRatio: safeActual,
          plannedRatio: safePlanned,
          alertThreshold: alertThreshold,
          actualColor: resolvedActualColor,
          plannedColor: resolvedPlannedColor,
          trackColor: resolvedTrackColor,
          thresholdColor: palette.cardBorderStrong.withValues(alpha: .7),
        ),
      ),
    );
    if (semanticsLabel case final label?) {
      return Semantics(
        label: label,
        value: '${(total * 100).round()}%',
        excludeSemantics: true,
        child: bar,
      );
    }
    return bar;
  }
}

class _CompassDualProgressPainter extends CustomPainter {
  const _CompassDualProgressPainter({
    required this.actualRatio,
    required this.plannedRatio,
    required this.alertThreshold,
    required this.actualColor,
    required this.plannedColor,
    required this.trackColor,
    required this.thresholdColor,
  });

  final double actualRatio;
  final double plannedRatio;
  final double alertThreshold;
  final Color actualColor;
  final Color plannedColor;
  final Color trackColor;
  final Color thresholdColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final radius = Radius.circular(size.height / 2);
    final trackRect = Offset.zero & size;
    final trackRRect = RRect.fromRectAndRadius(trackRect, radius);
    canvas.save();
    canvas.clipRRect(trackRRect);

    canvas.drawRect(trackRect, Paint()..color = trackColor);

    final actualWidth = (size.width * actualRatio).clamp(0.0, size.width);
    if (actualWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, actualWidth, size.height),
        Paint()..color = actualColor,
      );
    }

    final remainingWidth = size.width - actualWidth;
    final plannedWidth = (size.width * plannedRatio).clamp(0.0, remainingWidth);
    if (plannedWidth > 0) {
      final plannedRect =
          Rect.fromLTWH(actualWidth, 0, plannedWidth, size.height);
      canvas.drawRect(
        plannedRect,
        Paint()..color = plannedColor.withValues(alpha: .22),
      );
      canvas.save();
      canvas.clipRect(plannedRect);
      final stripePaint = Paint()
        ..color = plannedColor.withValues(alpha: .65)
        ..strokeWidth = 1.4;
      final step = math.max(4.0, size.height * 0.85);
      for (var x = plannedRect.left - size.height;
          x < plannedRect.right + size.height;
          x += step) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          stripePaint,
        );
      }
      canvas.restore();
    }

    if (alertThreshold > 0 && alertThreshold < 1) {
      final markerX = size.width * alertThreshold;
      canvas.drawLine(
        Offset(markerX, 0),
        Offset(markerX, size.height),
        Paint()
          ..color = thresholdColor
          ..strokeWidth = 1,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompassDualProgressPainter oldDelegate) =>
      oldDelegate.actualRatio != actualRatio ||
      oldDelegate.plannedRatio != plannedRatio ||
      oldDelegate.alertThreshold != alertThreshold ||
      oldDelegate.actualColor != actualColor ||
      oldDelegate.plannedColor != plannedColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.thresholdColor != thresholdColor;
}

class CompassDistributionBar extends StatelessWidget {
  const CompassDistributionBar({
    super.key,
    required this.values,
    required this.colors,
    this.labels,
    this.height = 22,
  });

  final List<double> values;
  final List<Color> colors;
  final List<String>? labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (sum, item) => sum + item.abs());
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: List.generate(values.length, (index) {
            final ratio =
                total == 0 ? 1 / values.length : values[index].abs() / total;
            return Expanded(
              flex: math.max(1, (ratio * 1000).round()),
              child: ColoredBox(
                color: colors[index],
                child: labels == null
                    ? null
                    : Center(
                        child: Text(
                          labels![index],
                          style: TextStyle(
                            color: financeForegroundOn(colors[index]),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class CompassAreaChart extends StatefulWidget {
  const CompassAreaChart({
    super.key,
    required this.values,
    this.height = 170,
    this.lineColor,
    this.markerIndex,
    this.markerColor = FinanceColors.compassOrange,
    this.labels,
    this.formatValue,
    this.showMinMaxLabels = false,
  });

  final List<double> values;
  final double height;
  final Color? lineColor;
  final int? markerIndex;
  final Color markerColor;
  final List<String>? labels;
  final String Function(double value)? formatValue;
  final bool showMinMaxLabels;

  @override
  State<CompassAreaChart> createState() => _CompassAreaChartState();
}

class _CompassAreaChartState extends State<CompassAreaChart> {
  int? _activeIndex;

  bool get _interactive =>
      widget.values.length >= 2 &&
      (widget.labels != null || widget.formatValue != null);

  void _updateFromDx(double dx, double width) {
    if (!_interactive || width <= 0 || widget.values.length < 2) return;
    final ratio = (dx / width).clamp(0.0, 1.0);
    final index = (ratio * (widget.values.length - 1))
        .round()
        .clamp(0, widget.values.length - 1);
    if (_activeIndex != index) {
      setState(() => _activeIndex = index);
    }
  }

  void _clearActive() {
    if (_activeIndex != null) {
      setState(() => _activeIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final resolvedLineColor = widget.lineColor ?? palette.seed;
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final paint = RepaintBoundary(
            child: CustomPaint(
              painter: _CompassAreaChartPainter(
                values: widget.values,
                lineColor: resolvedLineColor,
                markerIndex: widget.markerIndex,
                markerColor: widget.markerColor,
                activeIndex: _activeIndex,
                labels: widget.labels,
                formatValue: widget.formatValue,
                showMinMaxLabels: widget.showMinMaxLabels,
                palette: palette,
              ),
            ),
          );
          if (!_interactive) return paint;
          return MouseRegion(
            onHover: (event) => _updateFromDx(event.localPosition.dx, width),
            onExit: (_) => _clearActive(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _updateFromDx(details.localPosition.dx, width),
              onHorizontalDragStart: (details) =>
                  _updateFromDx(details.localPosition.dx, width),
              onHorizontalDragUpdate: (details) =>
                  _updateFromDx(details.localPosition.dx, width),
              onHorizontalDragEnd: (_) => _clearActive(),
              onTapUp: (_) => _clearActive(),
              onTapCancel: _clearActive,
              child: paint,
            ),
          );
        },
      ),
    );
  }
}

class _CompassAreaChartPainter extends CustomPainter {
  const _CompassAreaChartPainter({
    required this.values,
    required this.lineColor,
    required this.markerIndex,
    required this.markerColor,
    required this.activeIndex,
    required this.labels,
    required this.formatValue,
    required this.showMinMaxLabels,
    required this.palette,
  });

  final List<double> values;
  final Color lineColor;
  final int? markerIndex;
  final Color markerColor;
  final int? activeIndex;
  final List<String>? labels;
  final String Function(double value)? formatValue;
  final bool showMinMaxLabels;
  final FinanceThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1.0, maxValue - minValue);
    final topY = size.height * .12;
    final bottomY = size.height * .84;
    Offset pointAt(int index) {
      final fraction =
          minValue == maxValue ? .5 : (values[index] - minValue) / range;
      return Offset(
        size.width * index / (values.length - 1),
        topY + (bottomY - topY) * (1 - fraction),
      );
    }

    if (showMinMaxLabels && maxValue > minValue) {
      final guidePaint = Paint()
        ..color = palette.border.withValues(alpha: .75)
        ..strokeWidth = 0.8;
      for (final y in [topY, bottomY]) {
        for (var x = 0.0; x < size.width; x += 7) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + 3.5, size.width), y),
            guidePaint,
          );
        }
      }
      if (formatValue case final format?) {
        _paintScaleLabel(
          canvas,
          size,
          format(maxValue),
          topY + 3,
        );
        _paintScaleLabel(
          canvas,
          size,
          format(minValue),
          bottomY - 14,
        );
      }
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final previous = pointAt(i - 1);
      final current = pointAt(i);
      final midX = (previous.dx + current.dx) / 2;
      path.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          colors: [
            lineColor.withValues(alpha: .28),
            lineColor.withValues(alpha: .02)
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final index = markerIndex;
    if (index != null && index >= 0 && index < values.length) {
      final point = pointAt(index);
      canvas.drawLine(
        Offset(point.dx, point.dy),
        Offset(point.dx, size.height),
        Paint()
          ..color = markerColor
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(point, 6, Paint()..color = markerColor);
    }
    if (activeIndex case final hoverIndex?
        when hoverIndex >= 0 && hoverIndex < values.length) {
      final point = pointAt(hoverIndex);
      canvas.drawLine(
        Offset(point.dx, 0),
        Offset(point.dx, size.height),
        Paint()
          ..color = palette.textMuted.withValues(alpha: .45)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(point, 5.5, Paint()..color = palette.surface);
      canvas.drawCircle(point, 3.8, Paint()..color = lineColor);

      final label = labels != null && hoverIndex < labels!.length
          ? labels![hoverIndex]
          : null;
      final valueText = formatValue != null
          ? formatValue!(values[hoverIndex])
          : values[hoverIndex].toStringAsFixed(0);
      final tooltipText =
          label != null && label.isNotEmpty ? '$label · $valueText' : valueText;
      final painter = TextPainter(
        text: TextSpan(
          text: tooltipText,
          style: TextStyle(
            color: financeForegroundOn(palette.textPrimary),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: compassTabularFigures,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: math.max(80, size.width - 16));
      final pillWidth = painter.width + 14;
      final pillHeight = painter.height + 8;
      final dx = (point.dx - pillWidth / 2)
          .clamp(4.0, math.max(4.0, size.width - pillWidth - 4))
          .toDouble();
      final preferredY = point.dy - pillHeight - 8;
      final dy = preferredY >= 4
          ? preferredY
          : (point.dy + 10)
              .clamp(4.0, math.max(4.0, size.height - pillHeight - 4))
              .toDouble();
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(dx, dy, pillWidth, pillHeight),
        const Radius.circular(8),
      );
      canvas.drawRRect(rrect, Paint()..color = palette.textPrimary);
      painter.paint(canvas, Offset(dx + 7, dy + 4));
    }
  }

  void _paintScaleLabel(
    Canvas canvas,
    Size size,
    String text,
    double y,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: palette.textMuted.withValues(alpha: .72),
          fontSize: 10,
          fontFeatures: compassTabularFigures,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width * .6);
    painter.paint(
      canvas,
      Offset(math.max(0, size.width - painter.width - 2), y),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassAreaChartPainter oldDelegate) =>
      !listEquals(oldDelegate.values, values) ||
      oldDelegate.markerIndex != markerIndex ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.activeIndex != activeIndex ||
      oldDelegate.showMinMaxLabels != showMinMaxLabels ||
      oldDelegate.palette != palette;
}
