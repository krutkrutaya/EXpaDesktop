// A four-function calculator, as data.
//
// The app window is only a keypad around this: every button calls one of the
// methods below, and the display is whatever `display` says. That keeps the
// arithmetic testable without pumping widgets — including the awkward cases
// (repeat equals, chained operators, divide by zero, a second dot).

abstract final class CalculatorEngine {
  static const int maxDigits = 14;
}

/// The running calculator state.
class Calculator {
  String _display = '0';
  double? _accumulator;
  String? _operator;
  bool _replace = true;
  bool _error = false;
  String? _lastOperator;
  double? _lastOperand;

  String get display => _display;
  bool get hasError => _error;
  String get pendingOperator => _operator ?? '';

  /// The display as a number, or null when it is an error message.
  double? get value => _error ? null : double.tryParse(_display);

  void digit(String digit) {
    if (digit.length != 1 || int.tryParse(digit) == null) return;
    if (_error) clear();
    if (_replace || _display == '0') {
      _display = digit;
      _replace = false;
    } else if (_display.replaceAll('-', '').replaceAll('.', '').length <
        CalculatorEngine.maxDigits) {
      _display += digit;
    }
  }

  void dot() {
    if (_error) clear();
    if (_replace) {
      _display = '0.';
      _replace = false;
      return;
    }
    if (!_display.contains('.')) _display += '.';
  }

  /// `+`, `-`, `*` (shown as x) or `/`.
  void operator(String symbol) {
    if (_error) return;
    if (!const ['+', '-', '*', '/'].contains(symbol)) return;
    final current = double.tryParse(_display);
    if (current == null) return;

    if (_operator != null && !_replace) {
      final result = _apply(_accumulator ?? 0, _operator!, current);
      if (result == null) return;
      _accumulator = result;
      _display = _format(result);
    } else {
      _accumulator = current;
    }
    _operator = symbol;
    _replace = true;
    _lastOperator = null;
    _lastOperand = null;
  }

  void equals() {
    if (_error) return;
    final current = double.tryParse(_display);
    if (current == null) return;

    if (_operator != null) {
      final result = _apply(_accumulator ?? 0, _operator!, current);
      if (result == null) return;
      _lastOperator = _operator;
      _lastOperand = current;
      _operator = null;
      _accumulator = null;
      _display = _format(result);
      _replace = true;
      return;
    }

    // A second press repeats the last operation: 2 + 3 = (5) = (8).
    if (_lastOperator != null && _lastOperand != null) {
      final result = _apply(current, _lastOperator!, _lastOperand!);
      if (result == null) return;
      _display = _format(result);
      _replace = true;
    }
  }

  double? _apply(double left, String op, double right) {
    switch (op) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '*':
        return left * right;
      case '/':
        if (right == 0) {
          _fail('Cannot divide by zero');
          return null;
        }
        return left / right;
    }
    return null;
  }

  void _fail(String message) {
    _display = message;
    _error = true;
    _accumulator = null;
    _operator = null;
    _replace = true;
    _lastOperator = null;
    _lastOperand = null;
  }

  void clear() {
    _display = '0';
    _accumulator = null;
    _operator = null;
    _replace = true;
    _error = false;
    _lastOperator = null;
    _lastOperand = null;
  }

  /// The C/CE pair: CE clears the entry, and after an operator that is all a
  /// person means; with nothing pending it clears everything.
  void clearEntry() {
    if (_error || _operator == null) {
      clear();
      return;
    }
    _display = '0';
    _replace = true;
  }

  void backspace() {
    if (_error) {
      clear();
      return;
    }
    if (_replace) return;
    final next = _display.substring(0, _display.length - 1);
    _display = next.isEmpty || next == '-' ? '0' : next;
    if (_display == '0') _replace = true;
  }

  void percent() {
    if (_error) return;
    final current = double.tryParse(_display);
    if (current == null) return;
    _display = _format(current / 100);
    _replace = false;
  }

  void negate() {
    if (_error) return;
    if (_display == '0') return;
    _display = _display.startsWith('-')
        ? _display.substring(1)
        : '-$_display';
  }

  /// `1234.5` -> `1234.5`, `1234.0` -> `1234`, huge values in exponent form.
  static String _format(double value) {
    if (!value.isFinite) return '0';
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    if (value.abs() >= 1e12 || (value.abs() < 0.000001 && value != 0)) {
      return value.toStringAsExponential(6).replaceAll('e+', 'e');
    }
    var text = value.toStringAsFixed(10);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }
}