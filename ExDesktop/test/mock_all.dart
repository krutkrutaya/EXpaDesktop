// Runs every mock suite in one process and prints a single total.
//
//   dart run test/mock_all.dart
//
// The suites stay runnable on their own; this entry point is for the "is
// everything still fine" pass before a push.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'liquid_glass_mock_check.dart' as physics;
import 'shell_check.dart' as shell;
import 'system_mock_check.dart' as system;
import 'mock_harness.dart';

Future<void> main() async {
  physics.runPhysicsChecks();
  shell.runShellChecks();
  await system.runSystemChecks();
  finish('EXpaDesktop');
}