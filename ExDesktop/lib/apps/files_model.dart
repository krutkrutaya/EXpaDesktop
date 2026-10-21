// The Files app: a real directory browser that stays inside the shell.
//
// The lister is injected, so the mock suite walks a fake tree and the window
// walks the disk. Sorting is part of the model: folders first, then names,
// case-insensitively — the order Explorer uses, which is what the eye expects.

class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isImage =>
      const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(extension);
  bool get isText => const [
        'txt',
        'md',
        'json',
        'yaml',
        'yml',
        'dart',
        'log',
        'csv',
        'xml',
        'html',
        'css',
        'js',
        'ts',
        'ps1',
        'bat',
        'ini',
        'toml',
      ].contains(extension);
}

typedef EntryLister = Future<List<FileEntry>> Function(String path);

/// One step of the breadcrumb.
class Crumb {
  final String label;
  final String path;

  const Crumb(this.label, this.path);
}

class FilesModel {
  FilesModel({required EntryLister lister, required String start})
      : _lister = lister,
        _path = start;

  final EntryLister _lister;
  String _path;

  List<FileEntry> _entries = const [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  String get path => _path;
  List<FileEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;
  bool get isRoot => parentOf(_path) == _path;

  /// Loads a folder. A slow listing that finishes after a newer one is
  /// dropped, so double-clicking through folders cannot show the wrong list.
  Future<void> open(String path) async {
    final generation = ++_generation;
    _path = path;
    _loading = true;
    _error = null;
    try {
      final listed = await _lister(path);
      if (generation != _generation) return;
      // A lister may hand back an unmodifiable (const) list; sorting it in
      // place would throw and hide the folder behind an error.
      final entries = List<FileEntry>.from(listed);
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      _entries = List<FileEntry>.unmodifiable(entries);
    } catch (error) {
      if (generation != _generation) return;
      _entries = const [];
      _error = 'Cannot open this folder';
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  Future<void> refresh() => open(_path);

  Future<void> up() => isRoot ? Future<void>.value() : open(parentOf(_path));

  /// The parent path, or the same path at a drive/root.
  static String parentOf(String path) {
    final normalised = path.replaceAll('/', '\\');
    if (normalised.length <= 3) return normalised;
    final trimmed =
        normalised.endsWith('\\') ? normalised.substring(0, normalised.length - 1) : normalised;
    final cut = trimmed.lastIndexOf('\\');
    if (cut <= 0) return trimmed;
    final parent = trimmed.substring(0, cut);
    return parent.isEmpty ? trimmed : parent;
  }

  /// `C:\Users\me\Music` -> `This PC / C: / Users / me / Music`, each with the
  /// path a click should load.
  static List<Crumb> crumbsFor(String path) {
    final normalised = path.replaceAll('/', '\\');
    final driveMatch = RegExp(r'^([A-Za-z]:)').firstMatch(normalised);
    final crumbs = <Crumb>[const Crumb('This PC', '')];
    if (driveMatch == null) return crumbs;

    final drive = driveMatch.group(1)!;
    crumbs.add(Crumb(drive, '$drive\\'));
    final rest = normalised.substring(2).replaceAll(RegExp(r'^\\+'), '');
    if (rest.isEmpty) return crumbs;
    var running = '$drive\\';
    for (final part in rest.split('\\')) {
      if (part.isEmpty) continue;
      running = running.endsWith('\\') ? '$running$part' : '$running\\$part';
      crumbs.add(Crumb(part, running));
    }
    return crumbs;
  }

  /// `1.2 MB`, for the size column.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}