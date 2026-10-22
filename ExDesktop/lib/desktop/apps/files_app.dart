// The Files window: a directory browser with an in-window preview, so looking
// at a picture or a text file never leaves the shell.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../apps/audio_pick.dart';
import '../../apps/files_model.dart';
import '../../ui/glass.dart';

class FilesApp extends StatefulWidget {
  /// Started somewhere else by the tests.
  final String? startPath;

  /// A fake listing for the tests; the default walks the disk.
  final EntryLister? lister;

  /// Set while Musics wants an audio file: the window then shows a picker
  /// banner and a Use button on audio rows.
  final ValueListenable<AudioPickRequest?>? audioPick;

  /// A path the shell wants this window to open (Settings → Drives).
  final ValueNotifier<String?>? openPath;

  /// Lets the shell route a double-click through the desktop's file
  /// associations. Returning true means the file was handed to another app.
  final bool Function(FileEntry entry)? onOpenDefault;

  const FilesApp({
    super.key,
    this.startPath,
    this.lister,
    this.audioPick,
    this.openPath,
    this.onOpenDefault,
  });

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  late final FilesModel _model;
  FileEntry? _selected;
  String? _previewText;
  bool _loadingPreview = false;

  static String get _home =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;

  @override
  void initState() {
    super.initState();
    final start = widget.startPath ?? _home;
    _model = FilesModel(lister: widget.lister ?? _listDisk, start: start);
    unawaited(_model.open(start).then((_) => _refresh()));
    widget.audioPick?.addListener(_onPickChanged);
    widget.openPath?.addListener(_onOpenPathChanged);
    _consumeOpenPath();
  }

  @override
  void didUpdateWidget(covariant FilesApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPick != widget.audioPick) {
      oldWidget.audioPick?.removeListener(_onPickChanged);
      widget.audioPick?.addListener(_onPickChanged);
    }
    if (oldWidget.openPath != widget.openPath) {
      oldWidget.openPath?.removeListener(_onOpenPathChanged);
      widget.openPath?.addListener(_onOpenPathChanged);
      _consumeOpenPath();
    }
  }

  @override
  void dispose() {
    widget.audioPick?.removeListener(_onPickChanged);
    widget.openPath?.removeListener(_onOpenPathChanged);
    super.dispose();
  }

  void _onPickChanged() {
    if (mounted) setState(() {});
  }

  void _onOpenPathChanged() {
    if (mounted) _consumeOpenPath();
  }

  void _consumeOpenPath() {
    final path = widget.openPath?.value;
    if (path == null || path.isEmpty) return;
    _selected = null;
    _previewText = null;
    unawaited(_model.open(path).then((_) => _refresh()));
    // Consume it so the same path can be requested again later.
    widget.openPath?.value = null;
  }

  AudioPickRequest? get _pickRequest => widget.audioPick?.value;

  void _pick(FileEntry entry) {
    final request = _pickRequest;
    if (request == null || !request.accepts(entry.path)) return;
    request.onPick(entry.path);
  }

  Future<void> _refresh() async {
    if (mounted) setState(() {});
  }

  static Future<List<FileEntry>> _listDisk(String path) async {
    final directory = Directory(path);
    final entries = <FileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        final name = entity.path
            .replaceAll('/', Platform.pathSeparator)
            .split(Platform.pathSeparator)
            .last;
        entries.add(FileEntry(
          name: name,
          path: entity.path,
          isDirectory: stat.type == FileSystemEntityType.directory,
          size: stat.size,
        ));
      } catch (_) {
        // A file that vanished between listing and stat is simply skipped.
      }
      if (entries.length > 3000) break;
    }
    return entries;
  }

  Future<void> _select(FileEntry entry) async {
    setState(() {
      _selected = entry;
      _previewText = null;
      _loadingPreview = !entry.isDirectory && entry.isText;
    });
    if (entry.isDirectory || !entry.isText) return;
    try {
      final file = File(entry.path);
      final size = await file.length();
      // A 200 MB log must not be loaded just to show its first lines.
      if (size > 256 * 1024) {
        if (mounted) {
          setState(() {
            _loadingPreview = false;
            _previewText = 'This file is too large to preview here.';
          });
        }
        return;
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _previewText = text;
        _loadingPreview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewText = 'Cannot read this file as text.';
        _loadingPreview = false;
      });
    }
  }

  Future<void> _open(FileEntry entry) async {
    if (entry.isDirectory) {
      setState(() {
        _selected = null;
        _previewText = null;
      });
      await _model.open(entry.path);
      if (mounted) setState(() {});
      return;
    }
    final request = _pickRequest;
    if (request != null && request.accepts(entry.path)) {
      _pick(entry);
      return;
    }
    if (widget.onOpenDefault?.call(entry) == true) return;
    await _select(entry);
  }

  Widget _audioPickBanner() {
    final request = _pickRequest;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
      ),
      child: request == null
          ? const SizedBox(
              key: ValueKey('no-audio-pick'),
              width: double.infinity,
            )
          : Padding(
              key: const ValueKey('audio-pick-banner'),
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: const Color(0x2A9AD0FF),
                borderColor: const Color(0x559AD0FF),
                child: Row(
                  children: [
                    const Icon(Icons.library_music_outlined,
                        size: 16, color: Color(0xFF9AD0FF)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Choose an audio file to add to Musics',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    PillButton(
                      key: const ValueKey('audio-pick-cancel'),
                      label: 'Cancel',
                      onTap: () => request.onCancel?.call(),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = FilesModel.crumbsFor(_model.path);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              HoverIcon(
                key: const ValueKey('files-up'),
                icon: Icons.arrow_upward_rounded,
                tooltip: 'Up one folder',
                onTap: _model.isRoot
                    ? null
                    : () async {
                        await _model.up();
                        if (mounted) setState(() {});
                      },
              ),
              HoverIcon(
                key: const ValueKey('files-refresh'),
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: () async {
                  await _model.refresh();
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < crumbs.length; i++) ...[
                        if (i > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(Icons.chevron_right,
                                size: 14, color: Colors.white24),
                          ),
                        _CrumbButton(
                          crumb: crumbs[i],
                          current: i == crumbs.length - 1,
                          onTap: crumbs[i].path.isEmpty
                              ? null
                              : () async {
                                  await _model.open(crumbs[i].path);
                                  if (mounted) setState(() {});
                                },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _audioPickBanner(),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: GlassPanel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _model.loading
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: Colors.white38,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _model.entries.length,
                            itemBuilder: (context, index) {
                              final entry = _model.entries[index];
                              return _EntryRow(
                                key: ValueKey('files-entry-${entry.name}'),
                                entry: entry,
                                selected: _selected?.path == entry.path,
                                pickable: _pickRequest != null &&
                                    _pickRequest!.accepts(entry.path),
                                onPick: () => _pick(entry),
                                onTap: () => unawaited(_select(entry)),
                                onOpen: () => unawaited(_open(entry)),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _preview()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Caption(_model.error ?? '${_model.entries.length} items'),
              const Spacer(),
              Caption(_model.path, size: 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final entry = _selected;
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: entry == null
          ? const Center(child: Caption('Select a file to preview it'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      entry.isDirectory
                          ? Icons.folder_outlined
                          : entry.isAudio
                              ? Icons.audiotrack_rounded
                              : entry.isImage
                                  ? Icons.image_outlined
                                  : Icons.description_outlined,
                      size: 16,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Caption(entry.isDirectory
                    ? 'Folder'
                    : entry.isAudio
                        ? 'Audio · ${FilesModel.formatSize(entry.size)}'
                        : FilesModel.formatSize(entry.size)),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                          '${entry.path}-$_loadingPreview'),
                      child: _previewBody(entry),
                    ),
                  ),
                ),
                if (!entry.isDirectory) ...[
                  const SizedBox(height: 8),
                  PillButton(
                    label: 'Open in Windows',
                    icon: Icons.open_in_new,
                    onTap: () => unawaited(_openExternally(entry.path)),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _previewBody(FileEntry entry) {
    if (entry.isDirectory) {
      return const Center(child: Caption('Double-click to open the folder'));
    }
    if (entry.isAudio) {
      final request = _pickRequest;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.audiotrack_rounded,
              size: 42,
              color: const Color(0xFF9AD0FF).withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Caption('${entry.extension.toUpperCase()} audio file'),
            const SizedBox(height: 10),
            if (request != null)
              PillButton(
                key: const ValueKey('preview-pick'),
                label: 'Add to Musics',
                icon: Icons.playlist_add_rounded,
                onTap: () => _pick(entry),
              )
            else
              const Caption('Open Musics → Add track to import it'),
          ],
        ),
      );
    }
    if (_loadingPreview) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white38),
        ),
      );
    }
    if (entry.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(entry.path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) =>
              const Center(child: Caption('Cannot show this image')),
        ),
      );
    }
    final text = _previewText;
    if (text == null) {
      return const Center(child: Caption('No preview for this type'));
    }
    return SingleChildScrollView(
      child: SelectableText(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          height: 1.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Future<void> _openExternally(String path) async {
    try {
      await Process.start('cmd', ['/c', 'start', '', path],
          mode: ProcessStartMode.detached);
    } catch (_) {
      // The preview already shows the content; failing to hand off is not fatal.
    }
  }
}

class _CrumbButton extends StatefulWidget {
  final Crumb crumb;
  final bool current;
  final VoidCallback? onTap;

  const _CrumbButton({
    required this.crumb,
    required this.current,
    this.onTap,
  });

  @override
  State<_CrumbButton> createState() => _CrumbButtonState();
}

class _CrumbButtonState extends State<_CrumbButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: widget.current ? 0.12 : (_hovered ? 0.08 : 0.0),
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            widget.crumb.label,
            style: TextStyle(
              color: widget.current ? Colors.white : Colors.white54,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatefulWidget {
  final FileEntry entry;
  final bool selected;
  final bool pickable;
  final VoidCallback onPick;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _EntryRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.pickable,
    required this.onPick,
    required this.onTap,
    required this.onOpen,
  });

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final content = Row(
      children: [
        Icon(
          entry.isDirectory
              ? Icons.folder_rounded
              : entry.isAudio
                  ? Icons.audiotrack_rounded
                  : entry.isImage
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
          size: 15,
          color: entry.isDirectory
              ? const Color(0xFFFFC98A)
              : entry.isAudio
                  ? const Color(0xFF9AD0FF)
                  : Colors.white38,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(
            alpha: widget.selected ? 0.14 : (_hovered ? 0.07 : 0.0),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // The tap/double-tap area stops before the Use button: an ancestor
            // double-tap recogniser would make the button wait ~300 ms for a
            // second click that is never coming.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onDoubleTap: widget.onOpen,
                child: content,
              ),
            ),
            if (widget.pickable)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: PillButton(
                  key: ValueKey('files-pick-${entry.name}'),
                  label: 'Use',
                  icon: Icons.add_rounded,
                  onTap: widget.onPick,
                ),
              )
            else if (!entry.isDirectory)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Caption(FilesModel.formatSize(entry.size), size: 10),
              ),
          ],
        ),
      ),
    );
  }
}