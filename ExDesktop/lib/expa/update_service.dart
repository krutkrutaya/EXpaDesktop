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
  final String htmlUrl;

  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.body,
    required this.publishedAt,
    this.htmlUrl = '',
  });
}

class CommitInfo {
  final String sha;
  final String message;
  final String date;
  final String htmlUrl;

  const CommitInfo({
    required this.sha,
    required this.message,
    required this.date,
    this.htmlUrl = '',
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

class UpdateCheck {
  final VersionInfo current;
  final ReleaseInfo? release;
  final CommitInfo? commit;
  final List<ReleaseInfo> releases;
  final List<CommitInfo> commits;

  const UpdateCheck({
    required this.current,
    this.release,
    this.commit,
    this.releases = const [],
    this.commits = const [],
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
    this.repository = 'suptewme/EXpaDesktop',
  }) : _fetcher = fetcher ?? _httpGet;

  final UpdateFetcher _fetcher;
  final String repository;

  Future<UpdateCheck> check(VersionInfo current) async {
    final base = 'https://api.github.com/repos/$repository';

    // Lists give both the newest item and the stacked history the Updater
    // shows. A repository with no releases simply returns []; that must not
    // hide the commits.
    Future<Object?> fetchReleases() async {
      try {
        return parseReleaseList(
          await _fetcher(Uri.parse('$base/releases?per_page=10')),
        );
      } catch (error) {
        return error;
      }
    }

    Future<Object?> fetchCommits() async {
      try {
        return parseCommitList(
          await _fetcher(Uri.parse('$base/commits?per_page=10')),
        );
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait<Object?>([
      fetchReleases(),
      fetchCommits(),
    ]);
    var releases = const <ReleaseInfo>[];
    var commits = const <CommitInfo>[];
    Object? firstError;
    for (final result in results) {
      if (result is List<ReleaseInfo>) {
        releases = result;
      } else if (result is List<CommitInfo>) {
        commits = result;
      } else if (result != null) {
        firstError ??= result;
      }
    }
    if (releases.isEmpty && commits.isEmpty && firstError != null) {
      throw firstError;
    }
    return UpdateCheck(
      current: current,
      release: releases.isEmpty ? null : releases.first,
      commit: commits.isEmpty ? null : commits.first,
      releases: releases,
      commits: commits,
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
        htmlUrl: '${map['html_url'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  static List<ReleaseInfo> parseReleaseList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded.take(10))
          if (item is Map)
            if (parseRelease(jsonEncode(item)) case final release?)
              release,
      ];
    } catch (_) {
      return const [];
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
      return CommitInfo(
        sha: sha,
        message: message,
        date: date,
        htmlUrl: '${map['html_url'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  static List<CommitInfo> parseCommitList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded.take(10))
          if (item is Map)
            if (parseCommit(jsonEncode(item)) case final commit?)
              commit,
      ];
    } catch (_) {
      return const [];
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