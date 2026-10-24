// The Updater window and its GitHub service, tested with a fake fetcher and
// fake updater. No network, no git push, no rebuild.

import 'dart:convert';
import 'dart:io';

import 'package:exp_desktop/desktop/apps/updater_app.dart';
import 'package:exp_desktop/expa/update_runner.dart';
import 'package:exp_desktop/expa/update_service.dart';
import 'package:exp_desktop/expa/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the updater points at the suptewme mirror by default', () {
    expect(UpdateService().repository, 'suptewme/EXpaDesktop');
  });

  testWidgets('the Check button stays pinned to the right edge', (tester) async {
    final service = _FakeUpdateService(const UpdateCheck(
      current: VersionInfo(1, 4, 2, commit: 'abcdef1'),
    ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 900,
          height: 640,
          child: UpdaterApp(service: service, repoPath: r'C:\repo'),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final button = tester.getRect(find.byKey(const ValueKey('updater-check')));
    final host = tester.getRect(find.byType(UpdaterApp));
    expect(host.right - button.right, lessThan(20));
    expect(button.right, greaterThan(host.right - 20));
  });

  test('the updater refuses a dirty git checkout before closing the app',
      () async {
    final dir = Directory.systemTemp.createTempSync('expa_dirty_repo');
    addTearDown(() => dir.deleteSync(recursive: true));
    await Process.run('git', ['init', dir.path]);
    File('${dir.path}${Platform.pathSeparator}dirty.txt')
        .writeAsStringSync('uncommitted');

    final problem = await UpdateRunner.preflight(dir.path);
    expect(problem, contains('uncommitted changes'));
  });

  test('a missing releases endpoint still returns the latest commit', () async {
    final service = UpdateService(fetcher: (uri) async {
      if (uri.path.contains('/releases')) throw Exception('404');
      return '[{"sha":"abcdef1234567",'
          '"html_url":"https://github.com/x/y/commit/abcdef1",'
          '"commit":{"message":"main",'
          '"author":{"date":"2026-01-01T00:00:00Z"}}}]';
    });

    final result = await service.check(
        const VersionInfo(1, 1, 0, commit: '1111111'));
    expect(result.release, isNull);
    expect(result.commit?.sha, 'abcdef1234567');
    expect(result.commit?.htmlUrl, contains('github.com'));
    expect(result.releases, isEmpty);
    expect(result.commits.length, 1);
    expect(result.commitDiffers, isTrue);
  });

  test('a total GitHub failure is surfaced', () async {
    final service =
        UpdateService(fetcher: (uri) async => throw Exception('offline'));
    await expectLater(
      service.check(const VersionInfo(1, 1, 0)),
      throwsA(isA<Exception>()),
    );
  });

  test('preflight passes a clean checkout and HEAD recognizes ancestors',
      () async {
    final repo = _gitRepo();
    addTearDown(() => repo.deleteSync(recursive: true));
    expect(await UpdateRunner.preflight(repo.path), isNull);

    File('${repo.path}${Platform.pathSeparator}second.txt')
        .writeAsStringSync('two');
    void git(List<String> args) =>
        Process.runSync('git', args, workingDirectory: repo.path);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'Test']);
    git(['add', '.']);
    git(['commit', '-m', 'second']);
    final old = UpdateRunner.localCommit(repo.path);
    expect(UpdateRunner.commitContains(repo.path, old!), isTrue);
  });

  test('the updater reads the live HEAD and recognizes it as current', () {
    final repo = _gitRepo();
    addTearDown(() => repo.deleteSync(recursive: true));
    final head = UpdateRunner.localCommit(repo.path);
    expect(head, isNotNull);
    expect(UpdateRunner.commitContains(repo.path, head!), isTrue);
    expect(UpdateRunner.commitContains(repo.path, 'not-a-commit'), isFalse);
  });

  test('release and commit lists cap the history at ten rows', () {
    final releases = List.generate(
      12,
      (i) => {
        'tag_name': 'v1.$i.0',
        'name': 'Release $i',
        'body': 'body',
        'published_at': '2026-01-01T00:00:00Z',
        'html_url': 'https://github.com/x/y/releases/v1.$i.0',
      },
    );
    final commits = List.generate(
      12,
      (i) => {
        'sha': 'abcdef12345$i',
        'html_url': 'https://github.com/x/y/commit/$i',
        'commit': {
          'message': 'commit $i',
          'author': {'date': '2026-01-01T00:00:00Z'},
        },
      },
    );
    final releaseRows = UpdateService.parseReleaseList(jsonEncode(releases));
    final commitRows = UpdateService.parseCommitList(jsonEncode(commits));
    expect(releaseRows.length, 10);
    expect(commitRows.length, 10);
    expect(releaseRows.first.tag, 'v1.0.0');
    expect(commitRows.first.shortSha, 'abcdef1');
  });

  testWidgets('a checkout already at the latest commit is up to date',
      (tester) async {
    final repo = _gitRepo();
    addTearDown(() => repo.deleteSync(recursive: true));
    final head = UpdateRunner.localCommit(repo.path)!;
    final service = _FakeUpdateService(UpdateCheck(
      current: const VersionInfo(1, 4, 1, commit: 'stale1234'),
      commit: CommitInfo(
        sha: head,
        message: 'latest',
        date: '2026-01-01T00:00:00Z',
      ),
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 700,
          height: 640,
          child: UpdaterApp(service: service, repoPath: repo.path),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('You are up to date'), findsOneWidget);
    expect(find.byKey(const ValueKey('updater-update-commit')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Updater shows the release changelog and starts it',
      (tester) async {
    String? mode;
    String? target;
    final service = _FakeUpdateService(const UpdateCheck(
      current: VersionInfo(1, 0, 0, commit: '1111111'),
      release: ReleaseInfo(
        tag: 'v1.1.0',
        name: 'Spring cleaning',
        body: 'Fixes the music timecode and adds tabs.',
        publishedAt: '2026-04-01T10:00:00Z',
      ),
      commit: CommitInfo(
        sha: 'abcdef1234567',
        message: 'feat: browser tabs',
        date: '2026-04-02T10:00:00Z',
      ),
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 700,
          height: 640,
          child: UpdaterApp(
            current: const VersionInfo(1, 0, 0, commit: '1111111'),
            service: service,
            repoPath: r'C:\repo',
            onUpdate: (m, t, repo) async {
              mode = m;
              target = t;
              return null;
            },
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('v1.0.0 · 1111111'), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Spring cleaning'), findsOneWidget);
    expect(find.textContaining('Fixes the music timecode'), findsOneWidget);
    expect(find.textContaining('feat: browser tabs'), findsOneWidget);
    expect(find.byKey(const ValueKey('updater-update-release')), findsOneWidget);
    expect(find.byKey(const ValueKey('updater-update-commit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('updater-update-release')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(mode, 'release');
    expect(target, 'v1.1.0');

    await tester.tap(find.byKey(const ValueKey('updater-update-commit')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(mode, 'commit');
    expect(target, 'abcdef1234567');
  });

  testWidgets('commit rows stack and open their GitHub page in the shell',
      (tester) async {
    String? opened;
    final service = _FakeUpdateService(const UpdateCheck(
      current: VersionInfo(1, 0, 0, commit: '1111111'),
      commit: CommitInfo(
        sha: 'abcdef1234567',
        message: 'feat: browser tabs',
        date: '2026-01-02T00:00:00Z',
        htmlUrl: 'https://github.com/x/y/commit/abcdef1',
      ),
      commits: [
        CommitInfo(
          sha: 'abcdef1234567',
          message: 'feat: browser tabs\n\nFull commit body',
          date: '2026-01-02T00:00:00Z',
          htmlUrl: 'https://github.com/x/y/commit/abcdef1',
        ),
        CommitInfo(
          sha: 'bbbbbbb2222222',
          message: 'fix: music reset',
          date: '2026-01-01T00:00:00Z',
          htmlUrl: 'https://github.com/x/y/commit/bbbbbbb',
        ),
      ],
    ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 700,
          height: 640,
          child: UpdaterApp(
            service: service,
            repoPath: r'C:\repo',
            onOpenUrl: (url) => opened = url,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('updater-commit-bbbbbbb')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('updater-commit-abcdef1')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('updater-detail')), findsOneWidget);
    expect(find.textContaining('Full commit body'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('updater-open-github')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opened, 'https://github.com/x/y/commit/abcdef1');
  });

  testWidgets('an up-to-date build offers no release button', (tester) async {
    final service = _FakeUpdateService(const UpdateCheck(
      current: VersionInfo(1, 0, 0, commit: 'abcdef1'),
      release: ReleaseInfo(
        tag: 'v1.0.0',
        name: 'Current',
        body: '',
        publishedAt: '2026-01-01T00:00:00Z',
      ),
      commit: CommitInfo(
        sha: 'abcdef1234567',
        message: 'same build',
        date: '2026-01-01T00:00:00Z',
      ),
    ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 700,
          height: 640,
          child: UpdaterApp(service: service, repoPath: r'C:\repo'),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('You are up to date'), findsOneWidget);
    expect(find.text('This is the installed release.'), findsOneWidget);
    expect(find.text('This build is at the latest main commit.'), findsOneWidget);
    expect(find.byKey(const ValueKey('updater-update-release')), findsNothing);
    expect(find.byKey(const ValueKey('updater-update-commit')), findsNothing);
  });
}

Directory _gitRepo() {
  final dir = Directory.systemTemp.createTempSync('expa_update_repo');
  File('${dir.path}${Platform.pathSeparator}file.txt')
      .writeAsStringSync('one');
  void git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: dir.path);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  git(['init']);
  git(['config', 'user.email', 'test@example.com']);
  git(['config', 'user.name', 'Test']);
  git(['add', '.']);
  git(['commit', '-m', 'test commit']);
  return dir;
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.result) : super(fetcher: _neverFetch);

  final UpdateCheck result;

  @override
  Future<UpdateCheck> check(VersionInfo current) async => result;
}

Future<String> _neverFetch(Uri uri) async => '{}';