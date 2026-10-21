// The Snip window: captures the shell's own surface, not the Windows desktop.
//
// `ms-screenclip:` starts the Windows snipping overlay, which is a different
// window on top of everything. Here the shell renders itself to an image, so
// the shot is exactly what EXpaDesktop shows, and it never leaves the window.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../apps/browser_model.dart';
import '../../ui/glass.dart';

class SnipApp extends StatefulWidget {
  /// Renders the shell to PNG bytes. Injected by the shell; the tests pass a
  /// fake so they never need a real render tree.
  final Future<Uint8List?> Function()? capture;

  const SnipApp({super.key, this.capture});

  @override
  State<SnipApp> createState() => _SnipAppState();
}

class _SnipAppState extends State<SnipApp> {
  Uint8List? _shot;
  bool _busy = false;
  String _status = 'Take a shot of the desktop';

  Future<void> _capture() async {
    final capture = widget.capture;
    if (capture == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Capturing…';
    });
    final bytes = await capture();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _shot = bytes;
      _status = bytes == null ? 'Nothing to capture' : 'Shot ready';
    });
  }

  Future<void> _save() async {
    final shot = _shot;
    if (shot == null) return;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path =
          '${picturesDirectory()}${Platform.pathSeparator}snip-$stamp.png';
      await File(path).writeAsBytes(shot);
      if (!mounted) return;
      setState(() => _status = 'Saved to Pictures');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not save the shot');
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.capture != null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              PillButton(
                key: const ValueKey('snip-capture'),
                label: _shot == null ? 'Capture' : 'Capture again',
                icon: Icons.photo_camera_outlined,
                active: _busy,
                onTap: available && !_busy ? () => unawaited(_capture()) : null,
              ),
              const SizedBox(width: 6),
              PillButton(
                key: const ValueKey('snip-save'),
                label: 'Save PNG',
                icon: Icons.download_outlined,
                onTap: _shot != null ? () => unawaited(_save()) : null,
              ),
              const Spacer(),
              Caption(_status),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.all(8),
              child: _shot == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 42,
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                          const SizedBox(height: 10),
                          Caption(
                            available
                                ? 'The shot shows EXpaDesktop itself.\n'
                                    'Nothing opens outside the shell.'
                                : 'Screen capture is not available here.',
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _shot!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}