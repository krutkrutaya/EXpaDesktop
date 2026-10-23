// The machine's logical drives, for the Settings "Drives" pane. The CIM query
// is kept in a tiny service with a pure JSON parser so tests do not spawn
// PowerShell.

import 'dart:convert';
import 'dart:io';

class DriveEntry {
  final String id;
  final String label;
  final int totalBytes;
  final int freeBytes;

  const DriveEntry({
    required this.id,
    required this.label,
    required this.totalBytes,
    required this.freeBytes,
  });

  double get usedFraction =>
      totalBytes <= 0 ? 0 : ((totalBytes - freeBytes) / totalBytes).clamp(0, 1);

  String get sizeText =>
      '${_gb(freeBytes)} free of ${_gb(totalBytes)}';

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

List<DriveEntry> parseDrivesJson(String json) {
  try {
    final decoded = jsonDecode(json);
    final items = decoded is List ? decoded : [decoded];
    final drives = <DriveEntry>[];
    for (final item in items) {
      if (item is! Map) continue;
      final id = '${item['DeviceID'] ?? ''}';
      if (id.isEmpty) continue;
      final label = '${item['VolumeName'] ?? ''}'.trim();
      drives.add(DriveEntry(
        id: id,
        label: label.isEmpty ? id : label,
        totalBytes: (item['Size'] as num?)?.toInt() ?? 0,
        freeBytes: (item['FreeSpace'] as num?)?.toInt() ?? 0,
      ));
    }
    drives.sort((a, b) => a.id.compareTo(b.id));
    return drives;
  } catch (_) {
    return const [];
  }
}

Future<List<DriveEntry>> loadDrives() async {
  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-CimInstance Win32_LogicalDisk | '
            'Select-Object DeviceID,VolumeName,Size,FreeSpace | '
            'ConvertTo-Json -Compress',
      ],
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return const [];
    return parseDrivesJson(result.stdout as String);
  } catch (_) {
    return const [];
  }
}

/// Camera names from PnP. The desktop lists the hardware here; embedding a
/// live camera stream inside the shell is a separate native pipeline.
List<String> parseCamerasJson(String json) {
  try {
    final decoded = jsonDecode(json);
    final items = decoded is List ? decoded : [decoded];
    final cameras = <String>[];
    for (final item in items) {
      if (item is! Map) continue;
      final name = '${item['FriendlyName'] ?? ''}'.trim();
      if (name.isNotEmpty) cameras.add(name);
    }
    return cameras;
  } catch (_) {
    return const [];
  }
}

Future<List<String>> loadCameras() async {
  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-PnpDevice -Class Camera -Status OK | '
            'Select-Object FriendlyName | ConvertTo-Json -Compress',
      ],
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return const [];
    return parseCamerasJson(result.stdout as String);
  } catch (_) {
    return const [];
  }
}