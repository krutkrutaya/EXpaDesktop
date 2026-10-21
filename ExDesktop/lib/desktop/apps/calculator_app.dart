// The Calculator window: a keypad around the pure [Calculator] engine.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../apps/calculator_engine.dart';
import '../../ui/glass.dart';

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({super.key});

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  final Calculator _calc = Calculator();
  final FocusNode _focus = FocusNode(debugLabel: 'calculator');

  static const _operators = {'+': '＋', '-': '−', '*': '×', '/': '÷'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _press(String label) {
    setState(() {
      switch (label) {
        case 'C':
          _calc.clear();
        case 'CE':
          _calc.clearEntry();
        case '⌫':
          _calc.backspace();
        case '±':
          _calc.negate();
        case '%':
          _calc.percent();
        case '=':
          _calc.equals();
        case '.':
          _calc.dot();
        case '＋':
          _calc.operator('+');
        case '−':
          _calc.operator('-');
        case '×':
          _calc.operator('*');
        case '÷':
          _calc.operator('/');
        default:
          _calc.digit(label);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    String? press;
    if (key.keyLabel.length == 1 && '0123456789'.contains(key.keyLabel)) {
      press = key.keyLabel;
    } else if (key == LogicalKeyboardKey.period) {
      press = '.';
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.equal) {
      press = '=';
    } else if (key == LogicalKeyboardKey.backspace) {
      press = '⌫';
    } else if (key == LogicalKeyboardKey.escape) {
      press = 'C';
    } else if (key == LogicalKeyboardKey.numpadAdd || key == LogicalKeyboardKey.add) {
      press = '＋';
    } else if (key == LogicalKeyboardKey.numpadSubtract || key == LogicalKeyboardKey.minus) {
      press = '−';
    } else if (key == LogicalKeyboardKey.numpadMultiply) {
      press = '×';
    } else if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) {
      press = '÷';
    }
    if (press == null) return KeyEventResult.ignored;
    _press(press);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final error = _calc.hasError;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Caption(
                      _calc.pendingOperator.isEmpty
                          ? ' '
                          : _operators[_calc.pendingOperator] ?? '',
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _calc.display,
                        key: const ValueKey('calc-display'),
                        maxLines: 1,
                        style: TextStyle(
                          color: error ? const Color(0xFFFF8A80) : Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _keypad()),
          ],
        ),
      ),
    );
  }

  Widget _keypad() {
    const rows = [
      ['C', 'CE', '⌫', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '＋'],
      ['±', '0', '.', '='],
    ];
    return Column(
      children: [
        for (var row = 0; row < rows.length; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < 4; column++) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Key(
                      label: rows[row][column],
                      isOperator: column == 3,
                      isEquals: rows[row][column] == '=',
                      onTap: () => _press(rows[row][column]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Key extends StatefulWidget {
  final String label;
  final bool isOperator;
  final bool isEquals;
  final VoidCallback onTap;

  const _Key({
    required this.label,
    required this.isOperator,
    required this.isEquals,
    required this.onTap,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.isEquals ? const Color(0xFF9AD0FF) : Colors.white;
    final baseAlpha = widget.isOperator ? 0.13 : 0.06;
    final hoverAlpha = widget.isOperator ? 0.19 : 0.11;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: _hovered ? hoverAlpha : baseAlpha),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: widget.isEquals ? 0.25 : 0.08),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isEquals ? accent : Colors.white,
              fontSize: 18,
              fontWeight: widget.isOperator || widget.isEquals
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}