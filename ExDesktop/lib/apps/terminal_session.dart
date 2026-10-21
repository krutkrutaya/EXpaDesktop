// The Terminal app: a command line that really runs, inside the window.
//
// The old Terminal action started Windows Terminal, which is a different
// window on top of the shell. This runs `cmd /c <line>` and streams the result
// into the window. The runner is injected: the mock suite gets a recorder, the
// app gets `Process.run`.

import 'dart:io';

class CommandResult {
  const CommandResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;

  bool get ok => exitCode == 0;
}

typedef CommandRunner = Future<CommandResult> Function(String command);

/// The real runner. `runInShell` so `dir`, `echo` and builtins work.
Future<CommandResult> runInCmd(String command) async {
  try {
    final shell = await Process.run('cmd', ['/c', command], runInShell: true);
    final stdout = '${shell.stdout}'.trimRight();
    final stderr = '${shell.stderr}'.trimRight();
    final combined = [
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) '[stderr] $stderr',
    ].join('\n');
    return CommandResult(exitCode: shell.exitCode, output: combined);
  } catch (error) {
    return CommandResult(exitCode: 1, output: '$error');
  }
}

enum TerminalLineKind { command, output, error, info }

class TerminalLine {
  const TerminalLine(this.text, this.kind);

  final String text;
  final TerminalLineKind kind;
}

class TerminalSession {
  TerminalSession({CommandRunner? runner})
      : _runner = runner ?? runInCmd;

  final CommandRunner _runner;
  final List<TerminalLine> _lines = [];
  final List<String> _history = [];
  bool _busy = false;

  List<TerminalLine> get lines => List<TerminalLine>.unmodifiable(_lines);
  List<String> get history => List<String>.unmodifiable(_history);
  bool get busy => _busy;
  String get cwd => Directory.current.path;

  /// Runs one line. The command echo and the result both land in the log.
  Future<void> run(String input) async {
    final command = input.trim();
    if (command.isEmpty || _busy) return;
    _busy = true;
    _history.add(command);
    _lines.add(TerminalLine('> $command', TerminalLineKind.command));
    final result = await _runner(command);
    for (final line in result.output.split('\n')) {
      if (line.trim().isEmpty) continue;
      _lines.add(TerminalLine(
        line,
        result.ok ? TerminalLineKind.output : TerminalLineKind.error,
      ));
    }
    if (result.output.isEmpty) {
      _lines.add(TerminalLine(
        result.ok ? 'Done' : 'Failed with exit code ${result.exitCode}',
        result.ok ? TerminalLineKind.info : TerminalLineKind.error,
      ));
    }
    _busy = false;
    // Keep the log bounded: a runaway command cannot eat the session.
    if (_lines.length > 400) {
      _lines.removeRange(0, _lines.length - 400);
    }
  }

  void clear() => _lines.clear();
}