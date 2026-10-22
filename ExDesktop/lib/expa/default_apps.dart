// The DE's own file associations. Double-clicking a file in Files asks this
// table which in-app app should open it; Windows' UserChoice hash makes
// programmatic system defaults unreliable, so the desktop owns its mapping.

class FileAssociations {
  final Map<String, String> byExtension;

  const FileAssociations(this.byExtension);

  static const List<String> builtInApps = [
    'notepad',
    'paint',
    'files',
    'musics',
    'browser',
    'terminal',
  ];

  static const Map<String, String> defaults = {
    'txt': 'notepad',
    'md': 'notepad',
    'log': 'notepad',
    'csv': 'notepad',
    'png': 'paint',
    'jpg': 'paint',
    'jpeg': 'paint',
    'webp': 'paint',
    'bmp': 'paint',
    'mp3': 'musics',
    'wav': 'musics',
    'flac': 'musics',
    'ogg': 'musics',
    'm4a': 'musics',
    'html': 'browser',
    'htm': 'browser',
    'pdf': 'browser',
  };

  /// Every extension the Default apps pane lists. Keep this in sync with
  /// the read loop below: an extension that is written but never read back
  /// would silently reset on the next start.
  static final List<String> editableExtensions = [
    ...defaults.keys,
    'zip',
    '7z',
    'rar',
    'gif',
    'webp',
    'svg',
    'json',
    'xml',
    'yaml',
    'ini',
    'bat',
    'ps1',
    'py',
    'js',
    'css',
    'oga',
    'opus',
    'aiff',
    'aif',
  ];

  static const FileAssociations standard = FileAssociations(defaults);

  static String extensionOf(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String appFor(String path) {
    final ext = extensionOf(path);
    final app = byExtension[ext];
    if (app != null) return app;
    // Unknown types still open in the viewer that is always available.
    return 'files';
  }

  FileAssociations withAssociation(String extension, String app) {
    if (!builtInApps.contains(app)) return this;
    final ext = extension.replaceFirst('.', '').toLowerCase();
    if (ext.isEmpty) return this;
    return FileAssociations({...byExtension, ext: app});
  }

  static FileAssociations fromRead(
      String Function(String key, [String fallback]) read) {
    final map = Map<String, String>.from(defaults);
    for (final key in editableExtensions) {
      final value = read('assoc_$key', '');
      if (value.isNotEmpty && builtInApps.contains(value)) {
        map[key] = value;
      }
    }
    return FileAssociations(map);
  }

  Map<String, String> toMap() => {
        for (final entry in byExtension.entries)
          'assoc_${entry.key}': entry.value,
      };

  @override
  bool operator ==(Object other) =>
      other is FileAssociations &&
      other.byExtension.length == byExtension.length &&
      other.byExtension.entries.every(
        (entry) => byExtension[entry.key] == entry.value,
      );

  @override
  int get hashCode => Object.hashAll(
        byExtension.entries.map((entry) => Object.hash(entry.key, entry.value)),
      );
}