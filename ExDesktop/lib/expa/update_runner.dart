// Locating and launching the Rust updater. The Updater window checks GitHub
// and asks this class to start the rebuild; the binary waits for this process
// to exit, runs git + flutter, and relaunches the app.

import 'dart:io';

abstract final class UpdateRunner {
  /// The updater next to the exe (CMake), or the local cargo build.
  static String? findUpdater() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir${Platform.pathSeparator}updater.exe',
      '${Directory.current.path}${Platform.pathSeparator}updater.exe',
      '${Directory.current.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}rust${Platform.pathSeparator}updater'
          '${Platform.pathSeparator}updater.exe',
      '${Directory.current.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}rust${Platform.pathSeparator}updater'
          '${Platform.pathSeparator}target${Platform.pathSeparator}release'
          '${Platform.pathSeparator}updater.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Walks upward from the exe and the cwd looking for the git checkout.
  static String? findRepo() {
    for (final start in [
      File(Platform.resolvedExecutable).parent.path,
      Directory.current.path,
    ]) {
      var dir = Directory(start);
      for (var depth = 0; depth < 10; depth++) {
        if (Directory('${dir.path}${Platform.pathSeparator}.git').existsSync()) {
          return dir.path;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  /// The commit the checkout actually has. The version file goes stale between
  /// builds, so the Updater compares live HEAD whenever the repo is available.
  static String? localCommit(String repo) {
    try {
      final result = Process.runSync(
        'git',
        ['-C', repo, 'rev-parse', 'HEAD'],
        stdoutEncoding: const SystemEncoding(),
      );
      if (result.exitCode != 0) return null;
      final sha = '${result.stdout}'.trim();
      return sha.isEmpty ? null : sha;
    } catch (_) {
      return null;
    }
  }

  /// True when [latest] is HEAD or an ancestor of HEAD (local is current or
  /// ahead). This is what stops the Updater from claiming "update available"
  /// on a build that is already at the latest commit.
  static bool commitContains(String repo, String latest) {
    if (latest.isEmpty) return false;
    final head = localCommit(repo);
    if (head == null) return false;
    if (head == latest || head.startsWith(latest) || latest.startsWith(head)) {
      return true;
    }
    try {
      final result = Process.runSync(
        'git',
        ['-C', repo, 'merge-base', '--is-ancestor', latest, 'HEAD'],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Flutter is often not on Explorer's PATH; look in the usual places too.\n  static String _findFlutter() {\n    final root = Platform.environment['FLUTTER_ROOT'];\n    if (root != null && root.isNotEmpty) {\n      final path = 'bin'\n          'flutter.bat';\n      if (File(path).existsSync()) return path;\n    }\n    for (final path in const [\n      r'C:\\src\\flutter\\bin\\flutter.bat',\n      r'C:\\flutter\\bin\\flutter.bat',\n    ]) {\n      if (File(path).existsSync()) return path;\n    }\n    try {\n      final where = Process.runSync('where', ['flutter']);\n      if (where.exitCode == 0) {\n        final first = ''.split(RegExp(r'\\r?\\n')).first.trim();\n        if (first.isNotEmpty) return first;\n      }\n    } catch (_) {}\n    return 'flutter';\n  }\n\n  /// Refuses to update a dirty checkout: the Rust helper would abort after
  /// the desktop already closed, which looked like "the updater did nothing".
  static Future<String?> preflight(String repo) async {
    final gitDir = Directory('$repo${Platform.pathSeparator}.git');
    if (!gitDir.existsSync()) {
      return 'That folder is not a git repository.';
    }
    try {
      final status = await Process.run(
        'git',
        ['-C', repo, 'status', '--porcelain'],
        stdoutEncoding: const SystemEncoding(),
      );
      if (status.exitCode != 0) {
        return 'git could not read this repository.';
      }
      if ('${status.stdout}'.trim().isNotEmpty) {
        return 'The repository has uncommitted changes. Commit or stash them first.';
      }
    } catch (error) {
      return 'Could not run git: $error';
    }
    return null;
  }

  /// Starts the updater detached. Returns false when the binary is missing.
  static Future<bool> start({
    required String repo,
    required String mode,
    required String target,
    String? flutter,
    int? pid,
  }) async {
    final updater = findUpdater();
    if (updater == null) return false;
    final flutterPath = flutter ??
        (Platform.environment['FLUTTER_ROOT'] == null
            ? 'flutter'
            : '${Platform.environment['FLUTTER_ROOT']}'
                '${Platform.pathSeparator}bin'
                '${Platform.pathSeparator}flutter.bat');
    final args = [
      '--repo',
      repo,
      '--mode',
      mode,
      '--target',
      target,
      '--flutter',
      flutterPath,
    ];
    if (pid != null) args.addAll(['--pid', '$pid']);
    try {
      await Process.start(
        updater,
        args,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}