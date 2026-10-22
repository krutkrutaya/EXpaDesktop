// GitHub release/commit checks for the Updater window.
//
// The HTTP fetcher is injectable, so the JSON parsing and the "is there a
// newer release?" decision are tested without the network. The update itself
// is done by the Rust `updater` binary: this service only plans it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'version.dart';

class ReleaseInfo {
  final String tag;
  final String name;
  final String body;
  final String publishedAt;

  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.body,
    required this.publishedAt,
  });
}

class CommitInfo {
  final String sha;
  final String message;
  final String date;

  const CommitInfo({
    required this.sha,
    required this.message,
    required this.date,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

class UpdateCheck {
  final VersionInfo current;
  final ReleaseInfo? release;
  final CommitInfo? commit;

  const UpdateCheck({
    required this.current,
    this.release,
    this.commit,
  });

  VersionInfo? get releaseVersion =>
      release == null ? null : VersionInfo.parseTag(release!.tag);

  bool get hasNewerRelease {
    final version = releaseVersion;
    return version != null && version.isNewerThan(current);
  }

  bool get commitDiffers =>
      commit != null &&
      current.commit.isNotEmpty &&
      !commit!.sha.startsWith(current.commit) &&
      !current.commit.startsWith(commit!.sha);
}

typedef UpdateFetcher = Future<String> Function(Uri uri);

class UpdateService {
  UpdateService({
    UpdateFetcher? fetcher,
    this.repository = 'krutkrutaya/EXpaDesktop',
  }) : _fetcher = fetcher ?? _httpGet;

  final UpdateFetcher _fetcher;
  final String repository;

  Future<UpdateCheck> check(VersionInfo current) async {
    final base = 'https://api.github.com/repos/$repository';
    final releaseJson = await _fetcher(Uri.parse('$base/releases/latest'));
    final commitJson =
        await _fetcher(Uri.parse('$base/commits/main'));
    return UpdateCheck(
      current: current,
      release: parseRelease(releaseJson),
      commit: parseCommit(commitJson),
    );
  }

  static ReleaseInfo? parseRelease(String json) {
    try {
      final map = jsonDecode(json);
      if (map is! Map) return null;
      final tag = '${map['tag_name'] ?? ''}';
      if (tag.isEmpty) return null;
      return ReleaseInfo(
        tag: tag,
        name: '${map['name'] ?? tag}',
        body: '${map['body'] ?? ''}',
        publishedAt: '${map['published_at'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  static CommitInfo? parseCommit(String json) {
    try {
      final map = jsonDecode(json);
      if (map is! Map) return null;
      final sha = '${map['sha'] ?? ''}';
      if (sha.isEmpty) return null;
      final commit = map['commit'];
      final message = commit is Map ? '${commit['message'] ?? ''}' : '';
      final author = commit is Map ? commit['author'] : null;
      final date = author is Map ? '${author['date'] ?? ''}' : '';
      return CommitInfo(sha: sha, message: message, date: date);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _httpGet(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'EXpaDesktop-Updater')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('GitHub answered ${response.statusCode}', uri: uri);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}