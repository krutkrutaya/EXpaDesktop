// Runs every mock suite in one process and prints a single total.
//
//   dart run test/mock_all.dart
//
// The suites stay runnable on their own; this entry point is for the "is
// everything still fine" pass before a push.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'apps_check.dart' as apps;
import 'desktop_check.dart' as desktop;
import 'library_check.dart' as musiclib;
import 'liquid_glass_mock_check.dart' as physics;
import 'native_check.dart' as native;
import 'playback_check.dart' as playback;
import 'shell_check.dart' as shell;
import 'system_mock_check.dart' as system;
import 'mock_harness.dart';

Future<void> main() async {
  desktop.runDesktopChecks();
  playback.runPlaybackChecks();
  await apps.runAppsChecks();
  await musiclib.runLibraryChecks();
  native.runNativeChecks();
  physics.runPhysicsChecks();
  shell.runShellChecks();
  await system.runSystemChecks();
  finish('EXpaDesktop');
}