// The Notepad window: autosaving notes, no Save dialog in the way.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../apps/notepad_store.dart';
import '../../ui/glass.dart';

class NotepadApp extends StatefulWidget {
  /// Injectable for the tests; the default writes to %APPDATA%.
  final NotepadStore? store;

  const NotepadApp({super.key, this.store});

  @override
  State<NotepadApp> createState() => _NotepadAppState();
}

class _NotepadAppState extends State<NotepadApp> {
  late final NotepadStore _store = widget.store ?? NotepadStore();
  final TextEditingController _text = TextEditingController();
  Timer? _debounce;
  bool _dirty = false;
  String _status = 'Loading…';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final content = await _store.load();
    if (!mounted) return;
    setState(() {
      _text.text = content;
      _loaded = true;
      _status = content.isEmpty ? 'Empty note · autosaves' : 'Restored · autosaves';
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _dirty = true;
      _status = 'Saving…';
    });
    // 600 ms after the last keystroke: fast enough to feel automatic, slow
    // enough not to hit the disk on every letter.
    _debounce = Timer(const Duration(milliseconds: 600), () => unawaited(_save()));
  }

  Future<void> _save() async {
    final ok = await _store.save(_text.text);
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _status = ok ? 'Saved ${_clock()}' : 'Could not save';
    });
  }

  String _clock() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _clear() async {
    setState(() {
      _text.clear();
      _dirty = true;
      _status = 'Cleared';
    });
    await _save();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Closing the window should not lose the last keystrokes.
    if (_dirty && _loaded) unawaited(_store.save(_text.text));
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = _text.text.characters.length;
    final words = _text.text.trim().isEmpty
        ? 0
        : _text.text.trim().split(RegExp(r'\s+')).length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(child: Caption(_status)),
              PillButton(
                key: const ValueKey('notepad-clear'),
                label: 'Clear',
                icon: Icons.delete_sweep_outlined,
                onTap: _loaded ? () => unawaited(_clear()) : null,
              ),
              const SizedBox(width: 6),
              PillButton(
                key: const ValueKey('notepad-save'),
                label: 'Save',
                icon: Icons.save_outlined,
                active: _dirty,
                onTap: _loaded ? () => unawaited(_save()) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: TextField(
                key: const ValueKey('notepad-field'),
                controller: _text,
                onChanged: _onChanged,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: Colors.white70,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.55,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Start typing…',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Caption(
                  '$words words · $chars characters',
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Caption(_store.path, size: 10, maxLines: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}