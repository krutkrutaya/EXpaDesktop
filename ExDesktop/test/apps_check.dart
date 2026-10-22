// The applications' brains, checked without a window.
//
//   dart run test/apps_check.dart
//
// Calculator arithmetic, the task board, notes on disk, the file browser's
// sorting and breadcrumbs, the paint stroke list, the terminal session and the
// address bar. The widgets on top are thin; this is where the behaviour is.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:exp_desktop/apps/display_math.dart';
import 'package:exp_desktop/apps/task_store.dart';

import 'package:exp_desktop/apps/browser_model.dart';
import 'package:exp_desktop/apps/calculator_engine.dart';
import 'package:exp_desktop/apps/files_model.dart';
import 'package:exp_desktop/apps/notepad_store.dart';
import 'package:exp_desktop/apps/paint_board.dart';
import 'package:exp_desktop/apps/task_board.dart';
import 'package:exp_desktop/apps/terminal_session.dart';
import 'mock_harness.dart';

Future<void> runAppsChecks() async {
  _calculator();
  _tasks();
  await _notes();
  await _files();
  _paint();
  await _terminal();
  _browser();
  _display();
}

void _calculator() {
  section('calculator');
  final calc = Calculator();
  checkEquals('starts at zero', calc.display, '0');

  calc.digit('0');
  calc.digit('7');
  checkEquals('a leading zero is replaced', calc.display, '7');
  calc.digit('2');
  checkEquals('digits append', calc.display, '72');

  calc.dot();
  calc.digit('5');
  checkEquals('one dot', calc.display, '72.5');
  calc.dot();
  calc.digit('1');
  checkEquals('a second dot is ignored', calc.display, '72.51');

  calc.clear();
  calc.digit('2');
  calc.operator('+');
  calc.digit('3');
  calc.equals();
  checkEquals('2 + 3', calc.display, '5');

  calc.equals();
  checkEquals('equals repeats the last operation', calc.display, '8');

  calc.clear();
  calc.digit('2');
  calc.operator('+');
  calc.digit('3');
  calc.operator('*');
  checkEquals('chaining shows the running total', calc.display, '5');
  calc.digit('4');
  calc.equals();
  checkEquals('chaining is left to right', calc.display, '20');

  calc.clear();
  calc.digit('5');
  calc.operator('+');
  calc.operator('*');
  calc.digit('3');
  calc.equals();
  checkEquals('a second operator replaces the first', calc.display, '15');

  calc.clear();
  calc.digit('9');
  calc.operator('/');
  calc.digit('0');
  calc.equals();
  checkEquals('divide by zero says so', calc.display, 'Cannot divide by zero');
  check('divide by zero is an error state', calc.hasError);
  calc.digit('4');
  checkEquals('a digit clears the error', calc.display, '4');
  check('the error state is gone', !calc.hasError);

  calc.clear();
  calc.digit('5');
  calc.dot();
  calc.digit('0');
  calc.operator('+');
  calc.digit('2');
  calc.dot();
  calc.digit('5');
  calc.equals();
  checkEquals('decimal arithmetic', calc.display, '7.5');

  calc.clear();
  calc.digit('1');
  calc.digit('2');
  calc.backspace();
  checkEquals('backspace removes a digit', calc.display, '1');
  calc.backspace();
  checkEquals('backspace to zero', calc.display, '0');

  calc.clear();
  calc.digit('5');
  calc.digit('0');
  calc.percent();
  checkEquals('percent divides by a hundred', calc.display, '0.5');

  calc.clear();
  calc.digit('4');
  calc.negate();
  checkEquals('negate', calc.display, '-4');
  calc.negate();
  checkEquals('negate twice', calc.display, '4');

  calc.clear();
  calc.digit('8');
  calc.operator('+');
  calc.digit('2');
  calc.operator('-');
  checkEquals('the operator keeps the running total', calc.display, '10');
  calc.digit('3');
  calc.equals();
  checkEquals('and continues from it', calc.display, '7');

  calc.clear();
  calc.digit('1');
  calc.operator('+');
  calc.digit('2');
  calc.clearEntry();
  checkEquals('CE clears the entry only', calc.display, '0');
  checkEquals('the pending operator survives CE', calc.pendingOperator, '+');
  calc.digit('9');
  calc.equals();
  checkEquals('CE keeps the accumulator', calc.display, '10');

  calc.clear();
  for (var i = 0; i < 20; i++) {
    calc.digit('7');
  }
  check('the display is capped at 14 digits', calc.display.length == 14);

  calc.clear();
  calc.digit('0');
  calc.dot();
  calc.digit('0');
  checkEquals('0.0 stays readable', calc.display, '0.0');
}

void _tasks() {
  section('task board');
  final board = TaskBoard();
  check('starts empty', board.isEmpty);
  check('blank input is rejected', board.add('   ') == null);
  check('empty input is rejected', board.add('') == null);

  final first = board.add('  Write the tests  ');
  checkEquals('the text is trimmed', first?.text, 'Write the tests');
  final second = board.add('Ship the shell');
  checkEquals('two tasks', board.count, 2);
  checkEquals('the newest task is on top', board.items.first.text, 'Ship the shell');
  checkEquals('open count', board.openCount, 2);
  check('not all done', !board.allDone);

  board.toggle(first!.id);
  check('toggle marks done', board.items.last.done);
  checkEquals('done count', board.doneCount, 1);
  checkEquals('open count drops', board.openCount, 1);

  board.toggle(second!.id);
  check('all done is detected', board.allDone);

  check('rename works', board.rename(first.id, 'Write more tests'));
  checkEquals('renamed text', board.items.last.text, 'Write more tests');
  check('renaming to blank is refused', !board.rename(first.id, '  '));
  check('renaming an unknown id is refused', !board.rename(999, 'x'));

  final long = board.add('x' * 400);
  check('a wall of text is clipped', (long?.text.length ?? 0) <= 201);

  checkEquals('clearDone removes the finished', board.clearDone(), 2);
  checkEquals('one task left', board.count, 1);
  check('removing an unknown id is harmless', !board.remove(999));
  final restored = TaskBoard.fromJson(board.toJson());
  checkEquals('the JSON round-trip keeps the count', restored.count, board.count);
  checkEquals('the round-trip keeps the text',
      restored.items.first.text, board.items.first.text);
  check('the round-trip keeps the id', restored.items.first.id == board.items.first.id);

  final dir = Directory.systemTemp.createTempSync('expa_tasks');
  try {
    final store = TaskStore(root: dir.path);
    store.save(board);
    final loaded = store.load();
    checkEquals('the file store round-trips', loaded.count, board.count);
    check('the file store keeps the done flag',
        loaded.items.first.done == board.items.first.done);
  } finally {
    dir.deleteSync(recursive: true);
  }
  board.clear();
  check('clear empties the board', board.isEmpty);
}

Future<void> _notes() async {
  section('notepad store');
  final temp = await Directory.systemTemp.createTemp('exp_notes_');
  final path = '${temp.path}${Platform.pathSeparator}nested'
      '${Platform.pathSeparator}notes.txt';
  final store = NotepadStore(path: path);

  checkEquals('the path is used as given', store.path, path);
  check('a missing note is not an error', !await store.exists());
  checkEquals('a missing note reads empty', await store.load(), '');
  check('save creates the folders', await store.save('first line'));
  check('the file exists now', await store.exists());
  checkEquals('the note round-trips', await store.load(), 'first line');
  await store.save('multi\nline\nnote');
  checkEquals('multi-line notes survive', await store.load(), 'multi\nline\nnote');
  await store.save('');
  checkEquals('an empty note round-trips', await store.load(), '');

  final fallback = NotepadStore();
  check('the default path ends with notes.txt',
      fallback.path.endsWith('notes.txt'));
  check('the default path mentions the app',
      fallback.path.contains('EXpaDesktop'));
  await temp.delete(recursive: true);
}

Future<void> _files() async {
  section('files model');
  final tree = <String, List<FileEntry>>{
    r'C:\Users\me': const [
      FileEntry(name: 'beta.txt', path: r'C:\Users\me\beta.txt', isDirectory: false, size: 2048),
      FileEntry(name: 'Music', path: r'C:\Users\me\Music', isDirectory: true),
      FileEntry(name: 'alpha.png', path: r'C:\Users\me\alpha.png', isDirectory: false, size: 1024),
      FileEntry(name: 'Documents', path: r'C:\Users\me\Documents', isDirectory: true),
    ],
  };
  var calls = 0;
  final model = FilesModel(
    lister: (path) async {
      calls++;
      return tree[path] ?? const [];
    },
    start: r'C:\Users\me',
  );

  await model.open(r'C:\Users\me');
  checkEquals('the folder was listed once', calls, 1);
  check('entries are loaded', model.entries.length == 4);
  check('folders come first', model.entries.first.isDirectory);
  check('then files by name', model.entries[2].name == 'alpha.png');
  check('the second file follows', model.entries[3].name == 'beta.txt');
  check('a loaded folder is not busy', !model.loading);
  check('no error', model.error == null);

  await model.open(r'C:\nowhere');
  check('an unlisted folder is empty', model.entries.isEmpty);
  check('and reports no error because the lister succeeded', model.error == null);

  final broken = FilesModel(
    lister: (path) async => throw const FileSystemException('nope'),
    start: r'C:\x',
  );
  await broken.open(r'C:\x');
  checkEquals('a throwing lister becomes a message', broken.error, 'Cannot open this folder');
  check('and leaves no entries', broken.entries.isEmpty);

  checkEquals('parent of a folder', FilesModel.parentOf(r'C:\Users\me\Music'), r'C:\Users\me');
  checkEquals('parent of a user folder', FilesModel.parentOf(r'C:\Users\me'), r'C:\Users');
  checkEquals('parent of a drive', FilesModel.parentOf(r'C:\'), r'C:\');
  checkEquals('trailing slash is handled', FilesModel.parentOf(r'C:\Users\me\'), r'C:\Users');

  final crumbs = FilesModel.crumbsFor(r'C:\Users\me\Music');
  checkEquals('the breadcrumb starts at This PC', crumbs.first.label, 'This PC');
  checkEquals('then the drive', crumbs[1].label, 'C:');
  checkEquals('the drive level is a valid path', crumbs[1].path, r'C:\');
  checkEquals('then the folders', crumbs.last.label, 'Music');
  checkEquals('the last crumb is the full path', crumbs.last.path, r'C:\Users\me\Music');
  checkEquals('the crumb count', crumbs.length, 5);

  checkEquals('size in bytes', FilesModel.formatSize(512), '512 B');
  checkEquals('size in KB', FilesModel.formatSize(2048), '2 KB');
  checkEquals('size in MB', FilesModel.formatSize(3 * 1024 * 1024), '3.0 MB');
  checkEquals('size in GB', FilesModel.formatSize(2 * 1024 * 1024 * 1024), '2.0 GB');

  const image = FileEntry(name: 'shot.PNG', path: 'x', isDirectory: false);
  check('images are recognised', image.isImage);
  checkEquals('the extension is lowercased', image.extension, 'png');
  const text = FileEntry(name: 'notes.md', path: 'y', isDirectory: false);
  check('text files are recognised', text.isText);
  const binary = FileEntry(name: 'app.exe', path: 'z', isDirectory: false);
  check('binaries are neither', !binary.isText && !binary.isImage);

  // A slow listing must not overwrite a newer one.
  final completers = <String, Completer<List<FileEntry>>>{};
  final racing = FilesModel(
    lister: (path) => (completers[path] = Completer<List<FileEntry>>()).future,
    start: r'C:\a',
  );
  final slow = racing.open(r'C:\a');
  final fast = racing.open(r'C:\b');
  completers[r'C:\b']!.complete(const [
    FileEntry(name: 'b.txt', path: r'C:\b\b.txt', isDirectory: false),
  ]);
  await fast;
  completers[r'C:\a']!.complete(const [
    FileEntry(name: 'a.txt', path: r'C:\a\a.txt', isDirectory: false),
  ]);
  await slow;
  checkEquals('the newer folder wins the race', racing.entries.single.name, 'b.txt');
  checkEquals('the path is the newer one', racing.path, r'C:\b');
}

void _paint() {
  section('paint board');
  final board = PaintBoard();
  check('starts empty', board.strokeCount == 0 && !board.canUndo);
  check('extend without begin is ignored', () {
    board.extend(1, 1);
    return board.strokeCount == 0;
  }());

  board.begin(10, 10, color: 0xFFFFFFFF, width: 4);
  check('drawing starts', board.isDrawing);
  board.extend(10.1, 10.1); // too close: skipped
  board.extend(30, 30);
  board.extend(50, 20);
  board.end();
  check('the stroke is finished', !board.isDrawing);
  checkEquals('one stroke', board.strokeCount, 1);
  checkEquals('duplicate points are skipped', board.strokes.single.points.length, 3);
  check('undo is available', board.canUndo);

  board.begin(1, 1, color: 0xFFFF0000, width: 0.1);
  checkEquals('the brush has a minimum', board.current!.width, PaintBoard.minWidth);
  board.end();
  board.begin(1, 1, color: 0xFFFF0000, width: 999);
  checkEquals('the brush has a maximum', board.current!.width, PaintBoard.maxWidth);
  board.end();
  checkEquals('three strokes', board.strokeCount, 3);

  check('undo removes the last', board.undo());
  checkEquals('two left', board.strokeCount, 2);
  check('undo again', board.undo());
  check('undo a third time', board.undo());
  check('undo on an empty board is false', !board.undo());

  board.begin(5, 5, color: 0xFF00FF00, width: 3);
  board.end();
  check('a single dot is a stroke', board.strokeCount == 1 && board.strokes.single.points.length == 1);
  board.clear();
  check('clear empties everything', board.strokeCount == 0 && !board.canUndo);
}

Future<void> _terminal() async {
  section('terminal session');
  final ran = <String>[];
  final session = TerminalSession(
    runner: (command) async {
      ran.add(command);
      if (command == 'fail') {
        return const CommandResult(exitCode: 2, output: 'bad things');
      }
      if (command == 'quiet') {
        return const CommandResult(exitCode: 0, output: '');
      }
      return const CommandResult(exitCode: 0, output: 'hello\nworld');
    },
  );

  await session.run('  echo hi  ');
  checkEquals('the command is trimmed and sent', ran.single, 'echo hi');
  checkEquals('history keeps it', session.history.single, 'echo hi');
  check('the echo line is in the log', session.lines.first.text == '> echo hi');
  checkEquals('the log has the echo and two lines', session.lines.length, 3);
  check('output is marked as output',
      session.lines[1].kind == TerminalLineKind.output);
  check('the second line too', session.lines[2].text == 'world');

  await session.run('quiet');
  checkEquals('an empty output says Done', session.lines.last.text, 'Done');
  check('as info', session.lines.last.kind == TerminalLineKind.info);

  await session.run('fail');
  checkEquals('a failing command shows its output', session.lines.last.text, 'bad things');

  await session.run('   ');
  checkEquals('a blank line does not run', ran.length, 3);

  final before = session.lines.length;
  session.clear();
  checkEquals('clear empties the log', session.lines.length, 0);
  check('clear keeps the history', session.history.length == 3);
  check('the log had something before', before > 0);

  // busy guard: a second run while the first is in flight is ignored.
  final gate = Completer<void>();
  final gated = TerminalSession(runner: (command) async {
    await gate.future;
    return const CommandResult(exitCode: 0, output: 'ok');
  });
  final first = gated.run('slow');
  check('the session is busy while running', gated.busy);
  await gated.run('second');
  gate.complete();
  await first;
  check('the second call was dropped', gated.history.length == 1);
  check('and the session is free again', !gated.busy);
}

void _browser() {
  section('browser model');
  checkEquals('empty input', BrowserInput.resolve('').uri, 'about:blank');
  checkEquals('an explicit https URL',
      BrowserInput.resolve('https://flutter.dev').uri, 'https://flutter.dev');
  check('not a search',
      !BrowserInput.resolve('https://flutter.dev').isSearch);
  checkEquals('a domain gets https',
      BrowserInput.resolve('example.com').uri, 'https://example.com');
  checkEquals('a domain with a path',
      BrowserInput.resolve('example.com/a?b=1').uri, 'https://example.com/a?b=1');
  checkEquals('localhost keeps its port',
      BrowserInput.resolve('localhost:8080').uri, 'https://localhost:8080');
  checkEquals('an IP address is a host',
      BrowserInput.resolve('127.0.0.1:3000').uri, 'https://127.0.0.1:3000');
  final search = BrowserInput.resolve('hello world');
  check('words are a search', search.isSearch);
  checkContains('the query is encoded', search.uri, 'hello+world');
  checkContains('the search engine is used', search.uri, BrowserInput.searchBase);

  checkEquals('display drops https', BrowserInput.display('https://a.com/'), 'a.com');
  checkEquals('display drops http', BrowserInput.display('http://a.com/x'), 'a.com/x');
  checkEquals('display keeps about:blank', BrowserInput.display('about:blank'), 'about:blank');

  final history = BrowserHistory();
  check('no back on an empty history', !history.canBack && !history.canForward);
  history.push('a');
  history.push('b');
  history.push('c');
  checkEquals('three entries', history.entries.length, 3);
  checkEquals('the current page is the last', history.current, 'c');
  check('back is available', history.canBack);
  checkEquals('back returns b', history.back(), 'b');
  check('forward is available now', history.canForward);
  checkEquals('forward returns c', history.forward(), 'c');
  history.back();
  history.back();
  checkEquals('back stops at the first page', history.current, 'a');
  check('and reports no more back', !history.canBack);
  history.forward();
  history.push('d');
  checkEquals('a new page drops the forward branch', history.entries.length, 3);
  checkEquals('the new page is current', history.current, 'd');
  check('no forward after a push', !history.canForward);
  history.push('d');
  checkEquals('pushing the same page is ignored', history.entries.length, 3);
  history.push('about:blank');
  checkEquals('about:blank is not recorded', history.entries.length, 3);
  history.clear();
  check('clear empties the history', history.entries.isEmpty && history.index == -1);

  final tabs = BrowserTabs(home: 'https://start.example');
  checkEquals('one starting tab', tabs.count, 1);
  check('the last tab cannot be closed', !tabs.canClose);
  final second = tabs.add(url: 'https://second.example');
  checkEquals('a tab was added', tabs.count, 2);
  checkEquals('the new tab is active', tabs.active.id, second.id);
  check('tabs can close once there are two', tabs.canClose);
  tabs.update(title: 'Second');
  checkEquals('the title sticks', tabs.active.title, 'Second');
  tabs.select(tabs.tabs.first.id);
  checkEquals('selecting works', tabs.active.url, 'https://start.example');
  check('closing the inactive tab keeps the active one',
      tabs.close(second.id) == false);
  checkEquals('one tab left', tabs.count, 1);
  check('the last tab is still protected', !tabs.close(tabs.active.id));

  tabs.toggleBookmark('https://start.example');
  check('bookmark added', tabs.isBookmarked('https://start.example'));
  tabs.toggleBookmark('https://start.example');
  check('bookmark removed', !tabs.isBookmarked('https://start.example'));
  tabs.toggleBookmark('https://start.example');
  final session = BrowserTabs.fromJson(tabs.toJson());
  checkEquals('the session keeps its tab', session.count, 1);
  checkEquals('the session keeps the active URL', session.active.url,
      'https://start.example');
  check('the session keeps bookmarks',
      session.isBookmarked('https://start.example'));
}

void _display() {
  section('display math');
  checkClose('a fractional value passes through',
      normalizeBrightness(0.7)!, 0.7, 0.0001);
  checkClose('percent is normalized', normalizeBrightness(70)!, 0.7, 0.0001);
  check('a dead DDC reader returns null', normalizeBrightness(0) == null);
  check('negative is null', normalizeBrightness(-1) == null);
  check('NaN is null', normalizeBrightness(double.nan) == null);
  check('null is null', normalizeBrightness(null) == null);
  checkClose('above one is clamped', normalizeBrightness(1.2)!, 1.0, 0.0001);
}

void main() async {
  await runAppsChecks();
  finish('apps');
}