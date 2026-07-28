import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/finance_colors.dart';
import '../../core/theme/finance_theme.dart';

const compassPagePadding = EdgeInsets.fromLTRB(20, 16, 20, 28);
const compassHairline = Divider(height: 1, thickness: .7);
bool _compassUseCurrencyCode = true;
bool _compassUseEuropeanSeparators = false;

void setCompassMoneyStyle({
  required bool useCurrencyCode,
  required bool useEuropeanSeparators,
}) {
  _compassUseCurrencyCode = useCurrencyCode;
  _compassUseEuropeanSeparators = useEuropeanSeparators;
}

String compassMoney(double value, {String currency = 'MYR', int decimals = 2}) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(decimals).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => _compassUseEuropeanSeparators ? ' ' : ',',
  );
  final decimalMark = _compassUseEuropeanSeparators ? ',' : '.';
  final fraction = decimals == 0 ? '' : '$decimalMark${parts.last}';
  final prefix = _compassUseCurrencyCode
      ? currency
      : switch (currency.toUpperCase()) {
          'MYR' => 'RM',
          'USD' => 'US\$',
          'CNY' => 'RMB',
          'TWD' => 'NT\$',
          _ => currency,
        };
  return '${negative ? '- ' : ''}$prefix $grouped$fraction';
}

class CompassBackground extends StatelessWidget {
  const CompassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    return DecoratedBox(
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
      child: child,
    );
  }
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
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.cardTint.withValues(alpha: .76),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? palette.border, width: .8),
      ),
      child: child,
    );
    return onTap == null
        ? content
        : InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: content,
          );
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
    this.heroTag,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Object? heroTag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? financePaletteOf(context).seed;
    return SizedBox(
      width: size,
      height: size,
      child: FloatingActionButton(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: resolvedColor,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: const CircleBorder(),
        child: Icon(icon, size: size * .48),
      ),
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
                      ? palette.seed.withValues(alpha: .22)
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
    this.color = FinanceColors.compassOrange,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 21), const SizedBox(width: 8)],
        Text(label),
      ],
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: child,
            )
          : FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: child,
            ),
    );
  }
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
                          style: const TextStyle(
                            color: Colors.white,
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

class CompassAreaChart extends StatelessWidget {
  const CompassAreaChart({
    super.key,
    required this.values,
    this.height = 170,
    this.lineColor,
    this.markerIndex,
    this.markerColor = FinanceColors.compassOrange,
  });

  final List<double> values;
  final double height;
  final Color? lineColor;
  final int? markerIndex;
  final Color markerColor;

  @override
  Widget build(BuildContext context) {
    final resolvedLineColor = lineColor ?? financePaletteOf(context).seed;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: _CompassAreaChartPainter(
          values: values,
          lineColor: resolvedLineColor,
          markerIndex: markerIndex,
          markerColor: markerColor,
        ),
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
  });

  final List<double> values;
  final Color lineColor;
  final int? markerIndex;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1, maxValue - minValue);
    Offset pointAt(int index) => Offset(
          size.width * index / (values.length - 1),
          size.height * (.1 + .72 * (1 - (values[index] - minValue) / range)),
        );
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
            lineColor.withValues(alpha: .34),
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
  }

  @override
  bool shouldRepaint(covariant _CompassAreaChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.markerIndex != markerIndex ||
      oldDelegate.lineColor != lineColor;
}
