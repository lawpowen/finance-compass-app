import 'package:flutter/material.dart';

import '../../core/theme/finance_theme.dart';

class CompassWorkspaceLoading extends StatelessWidget {
  const CompassWorkspaceLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = financePaletteOf(context);
    final skeleton = Color.alphaBlend(
      palette.seed.withValues(alpha: .12),
      palette.surfaceAlt,
    );
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: '正在打开账本',
      liveRegion: true,
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reducedMotion ? 1.0 : 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    builder: (context, phase, child) {
                      final pulse = 1 - (2 * phase - 1).abs();
                      final opacity = reducedMotion
                          ? 1.0
                          : 1 - .55 * Curves.easeInOut.transform(pulse);
                      return Opacity(opacity: opacity, child: child);
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: skeleton,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Container(
                            height: 28,
                            decoration: BoxDecoration(
                              color: skeleton,
                              borderRadius: BorderRadius.circular(9),
                            ),
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
    );
  }
}

class CompassBusyIndicator extends StatelessWidget {
  const CompassBusyIndicator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 18,
        child: MediaQuery.disableAnimationsOf(context)
            ? Icon(Icons.hourglass_top_rounded, size: 18, color: color)
            : CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
    );
  }
}
