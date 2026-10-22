// The Updater window: compares the running version with the latest GitHub
// release and the latest main commit, shows both changelogs, and can hand the
// chosen target to the Rust updater (git + flutter build + relaunch).

import 'package:flutter/material.dart';

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

  const UpdaterApp({
    super.key,
    this.current = appVersion,
    this.service,
    this.repoPath,
    this.onUpdate,
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

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UpdateService();
    _repo = TextEditingController(
      text: widget.repoPath ?? UpdateRunner.findRepo() ?? '',
    );
    _checkNow();
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
      final check = await _service.check(widget.current);
      if (!mounted) return;
      setState(() {
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
      setState(() => _status =
          Loc.t('Choose the repository folder first.', 'Сначала выбери папку репозитория.'));
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
          Loc.t(
            'The app will close, rebuild and come back.',
            'Приложение закроется, соберётся и вернётся.',
          );
    });
  }

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
              Caption('v${widget.current.version}'
                  '${widget.current.commit.isEmpty ? '' : ' · ${widget.current.commit}'}'),
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
                    Loc.t('Could not reach GitHub', 'Не удалось связаться с GitHub'),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
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
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _releaseCard(check),
                    const SizedBox(height: 10),
                    _commitCard(check),
                  ],
                ),
              ),
            ),
          ],
          if (check != null) ...[
            const SizedBox(height: 8),
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
                    label: Loc.t(
                      'Update to ${check.releaseVersion!.version}',
                      'Обновить до ${check.releaseVersion!.version}',
                    ),
                    icon: Icons.rocket_launch_outlined,
                    onTap: _updating
                        ? null
                        : () => _startUpdate(
                            'release', check.release!.tag),
                  ),
                if (check.commitDiffers)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PillButton(
                      key: const ValueKey('updater-update-commit'),
                      label: Loc.t('Update to main', 'Обновить до main'),
                      icon: Icons.commit_rounded,
                      onTap: _updating
                          ? null
                          : () => _startUpdate('commit', check.commit!.sha),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _releaseCard(UpdateCheck check) {
    final release = check.release;
    if (release == null) {
      return GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Caption(Loc.t(
          'No GitHub release found; the latest commit is available below.',
          'Релизов на GitHub нет; ниже доступен последний коммит.',
        )),
      );
    }
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: check.hasNewerRelease
                      ? const Color(0xFF8AB4F8)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  check.hasNewerRelease
                      ? Loc.t('NEW RELEASE', 'НОВЫЙ РЕЛИЗ')
                      : Loc.t('RELEASE', 'РЕЛИЗ'),
                  style: TextStyle(
                    color: check.hasNewerRelease
                        ? Colors.black
                        : Colors.white60,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                release.tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  release.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Caption(release.publishedAt.split('T').first),
          const SizedBox(height: 8),
          Text(
            release.body.trim().isEmpty
                ? Loc.t('No changelog in this release.',
                    'В этом релизе нет списка изменений.')
                : release.body.trim(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          if (!check.hasNewerRelease) ...[
            const SizedBox(height: 8),
            Caption(Loc.t('This is the installed release.',
                'Это установленный релиз.')),
          ],
        ],
      ),
    );
  }

  Widget _commitCard(UpdateCheck check) {
    final commit = check.commit;
    if (commit == null) {
      return const SizedBox.shrink();
    }
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Caption('main', size: 10),
              const SizedBox(width: 8),
              Text(
                commit.shortSha,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Caption(commit.date.split('T').first),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            commit.message.split('\n').first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Caption(check.commitDiffers
              ? Loc.t('The latest main commit differs from this build.',
                  'Последний коммит main отличается от этой сборки.')
              : Loc.t('This build is at the latest main commit.',
                  'Эта сборка на последнем коммите main.')),
        ],
      ),
    );
  }
}