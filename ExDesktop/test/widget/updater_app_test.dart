// The Updater window: the GitHub check is a fake, so the changelog and the
// release/commit actions are tested without the network or a rebuild.

import 'package:exp_desktop/desktop/apps/updater_app.dart';
import 'package:exp_desktop/expa/update_service.dart';
import 'package:exp_desktop/expa/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a missing releases endpoint still returns the latest commit',
      () async {
    final service = UpdateService(fetcher: (uri) async {
      if (uri.path.endsWith('/releases/latest')) {
        throw Exception('404');
      }
      return '{"sha":"abcdef1234567","commit":{"message":"main",'
          '"author":{"date":"2026-01-01T00:00:00Z"}}}';
    });

    final result = await service.check(const VersionInfo(1, 1, 0, commit: '1111111'));
    expect(result.release, isNull);
    expect(result.commit?.sha, 'abcdef1234567');
    expect(result.commitDiffers, isTrue);
  });

  test('a total GitHub failure is surfaced', () async {
    final service = UpdateService(fetcher: (uri) async {
      throw Exception('offline');
    });
    await expectLater(
      service.check(const VersionInfo(1, 1, 0)),
      throwsA(isA<Exception>()),
    );
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
          child: UpdaterApp(
            service: service,
            repoPath: r'C:\repo',
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('This is the installed release.'), findsOneWidget);
    expect(find.text('This build is at the latest main commit.'), findsOneWidget);
    expect(find.byKey(const ValueKey('updater-update-release')), findsNothing);
    expect(find.byKey(const ValueKey('updater-update-commit')), findsNothing);
  });
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.result) : super(fetcher: _neverFetch);

  final UpdateCheck result;

  @override
  Future<UpdateCheck> check(VersionInfo current) async => result;
}

Future<String> _neverFetch(Uri uri) async => '{}';