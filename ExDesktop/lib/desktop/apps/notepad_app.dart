// The Notepad window: tabs, autosave for the shared note, file-backed tabs and
// Save As. File IO is synchronous because these are small text files and it
// keeps the widget tests deterministic.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../apps/notepad_store.dart';
import '../../ui/glass.dart';

class NotepadApp extends StatefulWidget {
  final NotepadStore? store;

  /// A file the shell wants this window to edit (Files → associations).
  final ValueNotifier<String?>? openPath;

  const NotepadApp({super.key, this.store, this.openPath});

  @override
  State<NotepadApp> createState() => _NotepadAppState();
}

class _NoteTab {
  String title;
  String? path;
  String text;
  bool dirty = false;
  final bool storeBacked;

  _NoteTab({
    required this.title,
    this.path,
    this.text = '',
    this.storeBacked = false,
  });
}

class _NotepadAppState extends State<NotepadApp> {
  late final NotepadStore _store = widget.store ?? NotepadStore();
  final TextEditingController _text = TextEditingController();
  final List<_NoteTab> _tabs = [];
  int _active = 0;
  Timer? _debounce;
  String _status = 'Loading…';
  bool _loaded = false;

  _NoteTab get _doc => _tabs[_active];

  @override
  void initState() {
    super.initState();
    _tabs.add(_NoteTab(title: 'Note', storeBacked: true));
    widget.openPath?.addListener(_onOpenPath);
    unawaited(_load());
    _consumeOpenPath();
  }

  void _onOpenPath() {
    if (mounted) _consumeOpenPath();
  }

  void _consumeOpenPath() {
    final path = widget.openPath?.value;
    if (path == null || path.isEmpty) return;
    widget.openPath?.value = null;
    _openFile(path);
  }

  Future<void> _load() async {
    final content = await _store.load();
    if (!mounted || _loaded) return;
    setState(() {
      _loaded = true;
      _doc.text = content;
      _text.text = content;
      _status = content.isEmpty ? 'Empty note · autosaves' : 'Restored · autosaves';
    });
  }

  void _openFile(String path) {
    final existing = _tabs.indexWhere((tab) => tab.path == path);
    if (existing >= 0) {
      _select(existing);
      return;
    }
    try {
      final content = File(path).readAsStringSync();
      _flushActive();
      setState(() {
        _loaded = true;
        _tabs.add(_NoteTab(
          title: _baseName(path),
          path: path,
          text: content,
        ));
        _active = _tabs.length - 1;
        _text.text = content;
        _status = 'Opened ${_baseName(path)}';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not open the file');
    }
  }

  void _flushActive() {
    if (_tabs.isEmpty) return;
    _debounce?.cancel();
    final doc = _doc;
    doc.text = _text.text;
    if (!doc.dirty) return;
    if (doc.path != null) {
      try {
        File(doc.path!).writeAsStringSync(doc.text, flush: true);
        doc.dirty = false;
      } catch (_) {}
    } else if (doc.storeBacked) {
      unawaited(_store.save(doc.text));
      doc.dirty = false;
    }
  }

  String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  String _defaultSavePath() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final documents = Directory(
      '$home${Platform.pathSeparator}Documents',
    );
    final base = documents.existsSync() ? documents.path : home;
    var candidate = '$base${Platform.pathSeparator}Untitled.txt';
    var index = 2;
    while (File(candidate).existsSync()) {
      candidate = '$base${Platform.pathSeparator}Untitled $index.txt';
      index++;
    }
    return candidate;
  }

  Future<void> _saveAs() async {
    final controller = TextEditingController(text: _defaultSavePath());
    final path = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xF01A1A1A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Save as',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('notepad-save-path'),
                  controller: controller,
                  autofocus: true,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12.5),
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('notepad-save-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      key: const ValueKey('notepad-save-confirm'),
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (path == null || path.trim().isEmpty || !mounted) return;
    try {
      final file = File(path.trim());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(_text.text, flush: true);
      setState(() {
        _doc
          ..path = file.path
          ..title = _baseName(file.path)
          ..dirty = false;
        _status = 'Saved ${_doc.title}';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not save the file');
    }
  }

  void _onChanged(String value) {
    _doc.text = value;
    _debounce?.cancel();
    setState(() {
      _doc.dirty = true;
      _status = _doc.path != null || _doc.storeBacked
          ? 'Saving…'
          : 'Unsaved · use Save As';
    });
    if (_doc.path == null && !_doc.storeBacked) return;
    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc.path == null && !doc.storeBacked) {
      await _saveAs();
      return;
    }
    if (doc.path != null) {
      try {
        File(doc.path!).writeAsStringSync(_text.text, flush: true);
        if (!mounted) return;
        setState(() {
          doc.dirty = false;
          _status = 'Saved ${_clock()}';
        });
        return;
      } catch (_) {
        if (mounted) setState(() => _status = 'Could not save the file');
        return;
      }
    }
    final ok = await _store.save(_text.text);
    if (!mounted || doc != _doc) return;
    setState(() {
      doc.dirty = false;
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
      _doc.text = '';
      _doc.dirty = true;
      _status = 'Cleared';
    });
    if (_doc.path != null || _doc.storeBacked) await _save();
  }

  void _select(int index) {
    if (index < 0 || index >= _tabs.length || index == _active) return;
    _flushActive();
    setState(() {
      _active = index;
      _text.text = _doc.text;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
      _status = _doc.path == null ? 'Untitled' : _doc.title;
    });
  }

  void _newTab() {
    _flushActive();
    setState(() {
      _loaded = true;
      _tabs.add(_NoteTab(title: 'Untitled'));
      _active = _tabs.length - 1;
      _text.clear();
      _status = 'New tab · use Save As';
    });
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      setState(() {
        _text.clear();
        _doc
          ..text = ''
          ..dirty = false;
        _status = 'Cleared';
      });
      return;
    }
    _flushActive();
    final closing = _tabs.removeAt(index);
    if (closing.dirty && closing.path != null) {
      try {
        File(closing.path!).writeAsStringSync(closing.text, flush: true);
      } catch (_) {}
    }
    if (_active >= _tabs.length) _active = _tabs.length - 1;
    if (index < _active) _active--;
    setState(() {
      _text.text = _doc.text;
      _status = _doc.title;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.openPath?.removeListener(_onOpenPath);
    _flushActive();
    final doc = _doc;
    if (doc.dirty) {
      if (doc.path != null) {
        try {
          File(doc.path!).writeAsStringSync(_text.text);
        } catch (_) {}
      } else if (doc.storeBacked) {
        unawaited(_store.save(_text.text));
      }
    }
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text.text;
    final chars = text.characters.length;
    final words =
        text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _doc.path == null ? Icons.edit_note_rounded : Icons.description_outlined,
                size: 15,
                color: Colors.white54,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Caption(_status, maxLines: 1),
              ),
              _action(
                key: 'notepad-new-tab',
                icon: Icons.add_rounded,
                tooltip: 'New tab',
                onTap: _newTab,
              ),
              _action(
                key: 'notepad-save-as',
                icon: Icons.save_as_outlined,
                tooltip: 'Save as',
                onTap: _saveAs,
              ),
              _action(
                key: 'notepad-clear',
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Clear',
                onTap: _loaded ? () => unawaited(_clear()) : null,
              ),
              _action(
                key: 'notepad-save',
                icon: Icons.save_outlined,
                tooltip: 'Save',
                active: _doc.dirty,
                onTap: _loaded ? () => unawaited(_save()) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    itemBuilder: (context, index) {
                      final tab = _tabs[index];
                      final active = index == _active;
                      return GestureDetector(
                        key: ValueKey('notepad-tab-$index'),
                        onTap: () => _select(index),
                        child: Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white.withValues(alpha: 0.13)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (tab.dirty)
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF9AD0FF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 92),
                                child: Text(
                                  tab.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: active
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                              if (_tabs.length > 1)
                                GestureDetector(
                                  key: ValueKey('notepad-tab-close-$index'),
                                  onTap: () => _closeTab(index),
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 5),
                                    child: Icon(Icons.close_rounded,
                                        size: 11, color: Colors.white38),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: GlassPanel(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Caption('$words words · $chars characters',
                    maxLines: 1),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Caption(
                  _doc.path ?? _store.path,
                  size: 9.5,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action({
    required String key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 26,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF9AD0FF).withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 15,
            color: onTap == null
                ? Colors.white24
                : (active ? const Color(0xFF9AD0FF) : Colors.white70),
          ),
        ),
      ),
    );
  }
}