// The Updater window: compares this build with GitHub, shows a clear
// up-to-date/update-available state, and lists the last ten releases and
// commits. Tapping an item opens its full changelog/message; that sheet can
// hand the GitHub URL to the in-shell Browser.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../expa/update_runner.dart';
import '../../expa/update_service.dart';
import '../../expa/version.dart';
import '../../i18n.dart';
import '../../ui/glass.dart';

typedef UpdateStarter = Future<String?> Function(
  String mode,
  String target,
  String repo,
);

class UpdaterApp extends StatefulWidget {
  final VersionInfo current;
  final UpdateService? service;
  final String? repoPath;
  final UpdateStarter? onUpdate;
  final ValueChanged<String>? onOpenUrl;

  /// Reads the committed version file from the build assets. The update helper
  /// rewrites that file before building, so the next launch reports the exact
  /// commit it was built from.
  final bool loadVersionAsset;

  const UpdaterApp({
    super.key,
    this.current = appVersion,
    this.service,
    this.repoPath,
    this.onUpdate,
    this.onOpenUrl,
    this.loadVersionAsset = false,
  });

  @override
  State<UpdaterApp> createState() => _UpdaterAppState();
}

class _UpdaterAppState extends State<UpdaterApp> {
  late final UpdateService _service;
  late final TextEditingController _repo;
  UpdateCheck? _check;
  String? _error;
  String _status = '';
  bool _loading = true;
  bool _updating = false;
  late VersionInfo _current;
  bool _repoAtLatest = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UpdateService();
    _repo = TextEditingController(
      text: widget.repoPath ?? UpdateRunner.findRepo() ?? '',
    );
    _current = widget.current;
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (widget.loadVersionAsset) {
      try {
        final content = await rootBundle.loadString(versionAsset);
        final parsed = VersionInfo.fromFile(versionAsset, content);
        if (parsed != null) _current = parsed;
      } catch (_) {
        // The appVersion constant remains the fallback.
      }
    }
    if (!mounted) return;
    setState(() {});
    await _checkNow();
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  Future<void> _checkNow() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final check = await _service.check(_current);
      if (!mounted) return;
      // The version file's commit lags behind a fresh `git pull`; the live
      // HEAD decides. A build whose HEAD already contains the latest remote
      // commit is current even if the bundled version file still says an
      // older commit — that was the false "update available".
      final repo = _repo.text.trim();
      final latest = check.commit?.sha;
      final head = repo.isEmpty ? null : UpdateRunner.localCommit(repo);
      final repoAtLatest = repo.isNotEmpty &&
          latest != null &&
          UpdateRunner.commitContains(repo, latest);
      setState(() {
        _repoAtLatest = repoAtLatest;
        if (head != null) {
          _current = VersionInfo(
            _current.major,
            _current.minor,
            _current.patch,
            commit: head,
          );
        }
        _check = check;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _startUpdate(String mode, String target) async {
    final starter = widget.onUpdate;
    if (starter == null) {
      setState(() => _status = Loc.t(
          'The updater is not wired in this build.',
          'Обновление не подключено в этой сборке.'));
      return;
    }
    final repo = _repo.text.trim();
    if (repo.isEmpty) {
      setState(() => _status = Loc.t('Choose the repository folder first.',
          'Сначала выбери папку репозитория.'));
      return;
    }
    setState(() {
      _updating = true;
      _status = Loc.t('Starting the updater…', 'Запускаю обновление…');
    });
    final error = await starter(mode, target, repo);
    if (!mounted) return;
    setState(() {
      _updating = false;
      _status = error ??
          Loc.t('The app will close, rebuild and come back.',
              'Приложение закроется, соберётся и вернётся.');
    });
  }

  List<ReleaseInfo> get _releases {
    final check = _check;
    if (check == null) return const [];
    if (check.releases.isNotEmpty) return check.releases;
    return check.release == null ? const [] : [check.release!];
  }

  List<CommitInfo> get _commits {
    final check = _check;
    if (check == null) return const [];
    if (check.commits.isNotEmpty) return check.commits;
    return check.commit == null ? const [] : [check.commit!];
  }

  bool get _available =>
      (_check?.hasNewerRelease ?? false) ||
      ((_check?.commitDiffers ?? false) && !_repoAtLatest);

  @override
  Widget build(BuildContext context) {
    final check = _check;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt_rounded,
                  size: 20, color: Colors.white70),
              const SizedBox(width: 9),
              Text(
                Loc.t('Updater', 'Обновления'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Caption(
                  'v${_current.version}'
                  '${_current.commit.isEmpty ? '' : ' · ${_current.commit.substring(0, _current.commit.length.clamp(0, 7))}'}',
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              PillButton(
                key: const ValueKey('updater-check'),
                label: Loc.t('Check', 'Проверить'),
                icon: Icons.refresh_rounded,
                onTap: _loading ? null : _checkNow,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('updater-repo'),
            controller: _repo,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              labelText: Loc.t('Repository folder', 'Папка репозитория'),
              labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
              prefixIcon: const Icon(Icons.folder_outlined,
                  size: 15, color: Colors.white38),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white54),
                ),
              ),
            )
          else if (_error != null)
            GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Loc.t('Could not reach GitHub',
                        'Не удалось связаться с GitHub'),
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Caption(_error!),
                  const SizedBox(height: 6),
                  PillButton(
                    label: Loc.t('Retry', 'Повторить'),
                    onTap: _checkNow,
                  ),
                ],
              ),
            )
          else if (check != null) ...[
            _statusBanner(check),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  _sectionTitle(Loc.t('Releases', 'Релизы')),
                  if (_releases.isEmpty)
                    Caption(Loc.t('No GitHub releases found.',
                        'Релизов на GitHub нет.'))
                  else
                    for (final release in _releases) ...[
                      _releaseRow(release, check),
                      const SizedBox(height: 6),
                    ],
                  const SizedBox(height: 6),
                  _sectionTitle(Loc.t('Commits on main', 'Коммиты main')),
                  for (final commit in _commits) ...[
                    _commitRow(commit, check),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Caption(_updating
                      ? Loc.t('Working…', 'Работаю…')
                      : _status),
                ),
                if (check.hasNewerRelease)
                  PillButton(
                    key: const ValueKey('updater-update-release'),
                    label: Loc.t('Update to ${check.releaseVersion!.version}',
                        'Обновить до ${check.releaseVersion!.version}'),
                    icon: Icons.rocket_launch_outlined,
                    onTap: _updating
                        ? null
                        : () => _startUpdate(
                            'release', check.release!.tag),
                  ),
                if (check.commitDiffers && !_repoAtLatest)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PillButton(
                      key: const ValueKey('updater-update-commit'),
                      label: Loc.t('Update to main', 'Обновить до main'),
                      icon: Icons.commit_rounded,
                      onTap: _updating
                          ? null
                          : () => _startUpdate(
                              'commit', check.commit!.sha),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _statusBanner(UpdateCheck check) {
    final available = _available;
    return GlassPanel(
      key: const ValueKey('updater-status'),
      padding: const EdgeInsets.all(12),
      color: available ? const Color(0x2AFFD39A) : const Color(0x2A9AD0FF),
      borderColor:
          available ? const Color(0x55FFD39A) : const Color(0x559AD0FF),
      child: Row(
        children: [
          Icon(
            available
                ? Icons.arrow_circle_up_rounded
                : Icons.verified_rounded,
            size: 20,
            color: available
                ? const Color(0xFFFFD39A)
                : const Color(0xFF9AD0FF),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available
                      ? Loc.t('Update available', 'Доступно обновление')
                      : Loc.t('You are up to date', 'Установлена актуальная версия'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Caption(
                  check.hasNewerRelease
                      ? '${check.release!.tag} · ${check.release!.name}'
                      : (check.commitDiffers && !_repoAtLatest
                          ? Loc.t('Main has newer commits.',
                              'В main есть новые коммиты.')
                          : Loc.t('No newer release or main commit.',
                              'Новых релизов или коммитов main нет.')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _releaseRow(ReleaseInfo release, UpdateCheck check) {
    final isInstalled = check.release?.tag == release.tag &&
        !check.hasNewerRelease;
    return GestureDetector(
      key: ValueKey('updater-release-${release.tag}'),
      onTap: () => _showRelease(release),
      child: _rowShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Caption(release.tag, size: 9.5),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    release.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12.5),
                  ),
                ),
                Caption(release.publishedAt.split('T').first, size: 9),
              ],
            ),
            if (release.body.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                release.body.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10.5,
                    height: 1.3),
              ),
            ],
            if (isInstalled)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Caption('This is the installed release.', size: 9),
              ),
          ],
        ),
      ),
    );
  }

  Widget _commitRow(CommitInfo commit, UpdateCheck check) {
    final isCurrent = !check.commitDiffers &&
        check.commit?.sha == commit.sha;
    return GestureDetector(
      key: ValueKey('updater-commit-${commit.shortSha}'),
      onTap: () => _showCommit(commit),
      child: _rowShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  commit.shortSha,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Caption(commit.date.split('T').first, size: 9),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              commit.message.split('\n').first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  height: 1.3),
            ),
            if (isCurrent)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Caption(
                    'This build is at the latest main commit.', size: 9),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowShell({required Widget child}) => GlassPanel(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: child),
            const Padding(
              padding: EdgeInsets.only(left: 6, top: 1),
              child: Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.white24),
            ),
          ],
        ),
      );

  void _showRelease(ReleaseInfo release) {
    _showDetail(
      title: '${release.tag} · ${release.name}',
      subtitle: release.publishedAt.split('T').first,
      body: release.body.trim().isEmpty
          ? Loc.t('No changelog in this release.', 'В этом релизе нет списка изменений.')
          : release.body.trim(),
      url: release.htmlUrl,
    );
  }

  void _showCommit(CommitInfo commit) {
    _showDetail(
      title: commit.shortSha,
      subtitle: commit.date.split('T').first,
      body: commit.message.trim().isEmpty
          ? Loc.t('No commit message.', 'У коммита нет сообщения.')
          : commit.message.trim(),
      url: commit.htmlUrl,
    );
  }

  void _showDetail({
    required String title,
    required String subtitle,
    required String body,
    required String url,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: const ValueKey('updater-detail'),
        backgroundColor: const Color(0xF016171C),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Caption(subtitle),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      body,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (url.isNotEmpty)
                      PillButton(
                        key: const ValueKey('updater-open-github'),
                        label: Loc.t('Open on GitHub', 'Открыть на GitHub'),
                        icon: Icons.open_in_new_rounded,
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onOpenUrl?.call(url);
                        },
                      ),
                    const SizedBox(width: 6),
                    PillButton(
                      label: Loc.t('Close', 'Закрыть'),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}