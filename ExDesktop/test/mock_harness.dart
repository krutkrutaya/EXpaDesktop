// The check harness shared by the mock suites.
//
// Every suite is a plain Dart script: no test runner, no Flutter, just
// assertions that print a line each so a failing check is visible in the
// output instead of buried in a stack trace. The counters are global, which
// lets `mock_all.dart` run several suites and still print one total.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

int get passedChecks => _passed;
int get failedChecks => _failed;
List<String> get failureList => List.unmodifiable(_failures);

/// Prints a suite/section title.
void section(String title) {
  print('');
  print(title);
}

/// Records one boolean check.
void check(String name, bool ok) {
  if (ok) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add(name);
    print('  FAIL  $name');
  }
}

/// Records one equality check, printing both sides on failure.
void checkEquals(String name, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add('$name (got $actual, want $expected)');
    print('  FAIL  $name — got $actual, want $expected');
  }
}

/// Records a numeric check with a tolerance.
void checkClose(
  String name,
  double actual,
  double expected, [
  double epsilon = 1e-9,
]) {
  check(name, (actual - expected).abs() <= epsilon);
}

/// Records a substring check.
void checkContains(String name, String haystack, String needle) {
  if (haystack.contains(needle)) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add('$name (missing "$needle")');
    print('  FAIL  $name — "$needle" not found');
  }
}

/// Records a "does not contain" check.
void checkMissing(String name, String haystack, String needle) {
  if (!haystack.contains(needle)) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add('$name (unexpected "$needle")');
    print('  FAIL  $name — "$needle" should not be there');
  }
}

/// Prints the total, lists every failure, and fails the process if any.
void finish(String suite) {
  print('');
  print('passed: $_passed   failed: $_failed');
  if (_failed > 0) {
    print('  !! $suite failures:');
    for (final failure in _failures) {
      print('    - $failure');
    }
    throw StateError('MOCK TESTS FAILED ($suite)');
  }
  print('ALL GREEN — $suite, $_passed checks');
}