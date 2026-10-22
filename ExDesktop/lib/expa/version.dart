// The build's version, shared by the Updater window and the version file.
//
// File name: version_x.y.z.txt (x = release, y = large change, z = patch).
// The content carries the commit the build came from, so the Updater can show
// exactly what is running and compare it with GitHub.

class VersionInfo {
  final int major;
  final int minor;
  final int patch;
  final String commit;

  const VersionInfo(this.major, this.minor, this.patch, {this.commit = ''});

  String get version => '$major.$minor.$patch';

  static final RegExp _filePattern =
      RegExp(r'^version_(\d+)\.(\d+)\.(\d+)\.txt$');

  /// Parses `version_1.4.2.txt` plus the file body (`commit=abc`).
  static VersionInfo? fromFile(String fileName, String content) {
    final match = _filePattern.firstMatch(fileName);
    if (match == null) return null;
    final commit = RegExp(r'^\s*commit\s*=\s*(\S+)', multiLine: true)
        .firstMatch(content)
        ?.group(1) ??
        '';
    return VersionInfo(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      commit: commit,
    );
  }

  static VersionInfo? parseTag(String tag) {
    final cleaned = tag.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(cleaned);
    if (match == null) return null;
    return VersionInfo(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// -1 when this is older, 0 when equal, 1 when newer.
  int compareTo(VersionInfo other) {
    if (major != other.major) return major < other.major ? -1 : 1;
    if (minor != other.minor) return minor < other.minor ? -1 : 1;
    if (patch != other.patch) return patch < other.patch ? -1 : 1;
    return 0;
  }

  bool isNewerThan(VersionInfo other) => compareTo(other) > 0;

  @override
  String toString() => commit.isEmpty ? version : '$version ($commit)';
}

/// The file name is part of the release process: bumping the version renames
/// this file and updates this constant.
const String versionAsset = 'version_1.0.0.txt';

/// Mirrors version_1.0.0.txt. The asset is the source of truth for the
/// Updater window (it is loaded at runtime); this constant is the fallback
/// and what tests compare against.
const VersionInfo appVersion = VersionInfo(1, 0, 0, commit: '8b7cde7');