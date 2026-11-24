import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/amount_calculator.dart';

/// Amount entry shared by full-page forms and dialogs. The controller always
/// contains a plain decimal amount; keypad digits never go into persistence.
class FinanceAmountField extends StatefulWidget {
  const FinanceAmountField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.title,
    this.showTitle = false,
    this.style,
    this.textAlign = TextAlign.start,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.fieldKey,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final String? title;
  final bool showTitle;
  final TextStyle? style;
  final TextAlign textAlign;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final Key? fieldKey;

  @override
  State<FinanceAmountField> createState() => _FinanceAmountFieldState();
}

class _FinanceAmountFieldState extends State<FinanceAmountField> {
  final _focusNode = FocusNode();
  bool _opening = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening || !widget.enabled || widget.readOnly) return;
    _opening = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final controller = widget.controller;
    final initialText = controller.text;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => _AmountKeyboard(
        initialText: initialText,
        title: widget.title ?? widget.decoration.labelText ?? '金额',
        prefix: widget.decoration.prefixText,
      ),
    );
    if (!mounted) return;
    if (result != null &&
        widget.enabled &&
        !widget.readOnly &&
        identical(controller, widget.controller)) {
      controller.value = TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
      widget.onChanged?.call(result);
    }
    _opening = false;
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.enabled && !widget.readOnly;
    final decoration = widget.decoration;
    final field = Focus(
      onKeyEvent: (_, event) {
        if (editable &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextFormField(
        key: widget.fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        readOnly: true,
        showCursor: false,
        enableInteractiveSelection: false,
        keyboardType: TextInputType.none,
        autofocus: widget.autofocus,
        validator: widget.validator,
        textAlign: widget.textAlign,
        style: widget.style,
        decoration: editable && decoration.suffixIcon == null
            ? decoration.copyWith(
                suffixIcon: IconButton(
                  tooltip: '打开金额键盘',
                  icon: const Icon(Icons.dialpad_rounded),
                  onPressed: _open,
                ),
              )
            : decoration,
        onTap: editable ? _open : null,
      ),
    );
    final title = widget.title;
    if (!widget.showTitle || title == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: editable ? _open : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        field,
      ],
    );
  }
}

class _AmountKeyboard extends StatefulWidget {
  const _AmountKeyboard({
    required this.initialText,
    required this.title,
    this.prefix,
  });

  final String initialText;
  final String title;
  final String? prefix;

  @override
  State<_AmountKeyboard> createState() => _AmountKeyboardState();
}

class _AmountKeyboardState extends State<_AmountKeyboard> {
  late final calculator = AmountCalculator(widget.initialText);
  final _keyboardFocus = FocusNode();
  bool _closing = false;
  bool _allowPop = false;

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    final discard = !calculator.dirty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('放弃本次金额输入？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('继续输入'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('放弃输入'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!mounted) return;
    if (discard) {
      _pop(null);
    } else {
      _closing = false;
      _keyboardFocus.requestFocus();
    }
  }

  void _pop(String? result) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  void _press(String key) {
    if (_closing) return;
    setState(() {
      switch (key) {
        case 'C':
          calculator.clear();
        case '±':
          calculator.toggleSign();
        case '⌫':
          calculator.backspace();
        case '+':
        case '−':
        case '×':
        case '÷':
          calculator.operation(key);
        case '=':
          calculator.evaluate();
        case '完成':
          if (calculator.evaluate()) {
            _closing = true;
            _pop(!calculator.dirty
                ? widget.initialText
                : calculator.isEmpty
                    ? ''
                    : calculator.display);
          }
        default:
          calculator.digit(key);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    final key = switch (event.logicalKey) {
      LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => '完成',
      LogicalKeyboardKey.backspace => '⌫',
      LogicalKeyboardKey.delete => 'C',
      _ => switch (event.character) {
          '*' => '×',
          '/' => '÷',
          '-' => '−',
          final value => value,
        },
    };
    if (key != null &&
        (RegExp(r'^\d$').hasMatch(key) ||
            const ['+', '−', '×', '÷', '=', '完成', '⌫', 'C'].contains(key))) {
      _press(key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final keyHeight =
        math.max(56.0, MediaQuery.textScalerOf(context).scale(24) + 24);
    const rows = [
      ['C', '±', '⌫', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['00', '0', '=', '完成'],
    ];
    return PopScope<String>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Focus(
        focusNode: _keyboardFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            key: const Key('amount-keyboard'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭金额键盘',
                      onPressed: _cancel,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (calculator.expression.isNotEmpty)
                  Text(
                    calculator.expression,
                    key: const Key('amount-expression'),
                    textAlign: TextAlign.end,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                Row(
                  children: [
                    if (widget.prefix?.trim().isNotEmpty ?? false)
                      Text(widget.prefix!.trim(),
                          style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        label: '当前金额',
                        value: calculator.display,
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            calculator.display,
                            key: const Key('amount-display'),
                            style: TextStyle(
                              fontSize: 40,
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (calculator.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(calculator.error!,
                        style: TextStyle(color: colors.error)),
                  ),
                const SizedBox(height: 12),
                for (final row in rows) ...[
                  Row(
                    children: [
                      for (var i = 0; i < row.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: _key(row[i], keyHeight)),
                      ],
                    ],
                  ),
                  if (row != rows.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _key(String key, double height) {
    final colors = Theme.of(context).colorScheme;
    final isOperator = const ['+', '−', '×', '÷', '='].contains(key);
    final label = switch (key) {
      'C' => '清空',
      '±' => '切换正负',
      '⌫' => '退格',
      '+' => '加',
      '−' => '减',
      '×' => '乘',
      '÷' => '除',
      '=' => '计算结果',
      _ => key,
    };
    return SizedBox(
      height: height,
      child: FilledButton(
        key: ValueKey('amount-key-$key'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          backgroundColor: key == '完成'
              ? colors.primary
              : isOperator
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
          foregroundColor: key == '完成'
              ? (colors.primary.computeLuminance() > 0.179
                  ? Colors.black
                  : Colors.white)
              : isOperator
                  ? colors.onPrimaryContainer
                  : colors.onSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => _press(key),
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: key == '⌫'
              ? const Icon(Icons.backspace_outlined)
              : Text(key, style: TextStyle(fontSize: key == '完成' ? 16 : 24)),
        ),
      ),
    );
  }
}
