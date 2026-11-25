import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/finance_theme.dart';
import 'compass_ui.dart'
    show
        CompassHelpHeading,
        compassGlassHighlight,
        compassIsCpuSoftwareWeb,
        compassUsesCardBackdropBlur;

@immutable
class FinanceDonutSlice {
  const FinanceDonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

List<Color> financeDonutSeries(BuildContext context) {
  final palette = financePaletteOf(context);
  if (palette.donutColors case final custom?) {
    return custom;
  }
  if (palette.monochrome) {
    return const [
      Color(0xffdcdcdc),
      Color(0xffaaaaaa),
      Color(0xff777777),
      Color(0xff363636),
    ];
  }
  return Theme.of(context).brightness == Brightness.dark
      ? const [
          Color(0xff63d4c0),
          Color(0xfff4ad79),
          Color(0xffbcb3ef),
          Color(0xff78929a),
        ]
      : const [
          Color(0xff08786b),
          Color(0xffa34a28),
          Color(0xff6551ad),
          Color(0xff7a8b93),
        ];
}

class FinanceDonutPanel extends StatelessWidget {
  const FinanceDonutPanel({
    super.key,
    required this.title,
    required this.totalLabel,
    required this.totalValue,
    required this.slices,
    this.footer,
    this.formatLegendAmount,
    this.titleHelp,
  });

  final String title;
  final String totalLabel;
  final String totalValue;
  final List<FinanceDonutSlice> slices;
  final Widget? footer;
  final String Function(double)? formatLegendAmount;
  final String? titleHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = financePaletteOf(context);
    final mono = palette.monochrome;
    final themedPanel = mono || palette.cardSurface != null;
    final dark = theme.brightness == Brightness.dark;
    final surface = palette.cardSurface ??
        (mono
            ? palette.surface
            : dark
                ? const Color(0xff0b2731)
                : Colors.white);
    final border = themedPanel
        ? palette.border
        : dark
            ? const Color(0xff284852)
            : const Color(0xffccdfe0);
    final text = themedPanel
        ? palette.textPrimary
        : dark
            ? const Color(0xfff0fafa)
            : const Color(0xff182e34);
    final muted = themedPanel
        ? palette.textMuted
        : dark
            ? const Color(0xffa7bfc4)
            : const Color(0xff49626a);
    final amounts = [
      for (final slice in slices)
        slice.value.isFinite && slice.value > 0 ? slice.value : 0.0,
    ];
    final total = amounts.fold(0.0, (sum, amount) => sum + amount);
    final segments = [
      for (var index = 0; index < slices.length; index++)
        if (amounts[index] > 0 && total.isFinite)
          (fraction: amounts[index] / total, color: slices[index].color),
    ];

    final cardRadius = BorderRadius.circular(14);
    final cpuSoftware = compassIsCpuSoftwareWeb;
    final isLiquidGlass = palette.glassHighlightColor != null;
    final usesBackdropBlur =
        compassUsesCardBackdropBlur(context, palette.cardBlurSigma);
    final panelShadows = [
      if (palette.cardShadowColor case final shadow?)
        BoxShadow(
          color: shadow,
          blurRadius: cpuSoftware ? 0 : (isLiquidGlass ? 18 : 10),
          offset: Offset(0, cpuSoftware ? 1 : (isLiquidGlass ? 8 : 2)),
        ),
    ];
    final heading = Semantics(
      container: true,
      header: true,
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
    final panelBody = DecoratedBox(
      decoration: BoxDecoration(
        color: isLiquidGlass ? null : surface,
        gradient: isLiquidGlass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: cpuSoftware
                    ? [
                        Colors.white.withValues(alpha: .84),
                        surface.withValues(alpha: .78),
                        const Color(0xFFEAF5FF).withValues(alpha: .82),
                      ]
                    : [
                        Colors.white.withValues(alpha: .68),
                        surface,
                        const Color(0xFFEAF5FF).withValues(alpha: .56),
                      ],
              )
            : null,
        border: Border.all(
          color: isLiquidGlass ? Colors.white.withValues(alpha: .62) : border,
          width: isLiquidGlass ? 1.0 : 1.0,
        ),
        borderRadius: cardRadius,
        boxShadow: usesBackdropBlur ? const [] : panelShadows,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(
            color: text,
            fontSize: 14,
            height: 1.45,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (titleHelp case final message?)
                CompassHelpHeading(
                    title: heading, label: title, message: message)
              else
                heading,
              const SizedBox(height: 16),
              Center(
                child: SizedBox.square(
                  dimension: 146,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _DonutPainter(
                        segments: segments,
                        track: border,
                        separator: palette.donutSeparatorColor ??
                            (mono ? surface : null),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 29),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  totalLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: muted,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                                Text(
                                  totalValue,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (slices.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (var index = 0; index < slices.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: index == slices.length - 1 ? 0 : 7),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: slices[index].color,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 8),
                        ),
                        const SizedBox(width: 7),
                        Expanded(child: Text(slices[index].label)),
                        const SizedBox(width: 7),
                        if (formatLegendAmount case final format?) ...[
                          SizedBox(
                            width: 82,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                format(amounts[index]),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        SizedBox(
                          width: formatLegendAmount == null ? null : 40,
                          child: Text(
                            _percent(amounts[index], total),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (footer case final summary?) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: border),
                const SizedBox(height: 8),
                DefaultTextStyle.merge(
                    style: TextStyle(color: muted), child: summary),
              ],
            ],
          ),
        ),
      ),
    );
    final highlightedPanel = compassGlassHighlight(
      color: palette.glassHighlightColor,
      borderRadius: cardRadius,
      child: panelBody,
    );
    if (usesBackdropBlur) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: cardRadius,
          boxShadow: panelShadows,
        ),
        child: ClipRRect(
          borderRadius: cardRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: palette.cardBlurSigma,
              sigmaY: palette.cardBlurSigma,
              tileMode: TileMode.clamp,
            ),
            child: highlightedPanel,
          ),
        ),
      );
    }
    return highlightedPanel;
  }

  String _percent(double amount, double total) {
    return total > 0 && total.isFinite
        ? '${(amount / total * 100).round()}%'
        : '0%';
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(
      {required this.segments, required this.track, this.separator});

  final List<({double fraction, Color color})> segments;
  final Color track;
  final Color? separator;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = size.shortestSide;
    final strokeWidth = diameter * .16;
    final center = size.center(Offset.zero);
    final radius = (diameter - strokeWidth) / 2;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    if (segments.isEmpty) {
      canvas.drawCircle(center, radius, fill..color = track);
      return;
    }
    final arc = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final segment in segments) {
      final sweep = segment.fraction * math.pi * 2;
      canvas.drawArc(arc, start, sweep, false, fill..color = segment.color);
      start += sweep;
    }
    if (separator case final color? when segments.length > 1) {
      final divider = Paint()
        ..color = color
        ..strokeWidth = 1;
      var angle = -math.pi / 2;
      for (final segment in segments) {
        final unit = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + unit * (radius - strokeWidth / 2),
          center + unit * (radius + strokeWidth / 2),
          divider,
        );
        angle += segment.fraction * math.pi * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      track != oldDelegate.track ||
      separator != oldDelegate.separator ||
      !listEquals(segments, oldDelegate.segments);
}
