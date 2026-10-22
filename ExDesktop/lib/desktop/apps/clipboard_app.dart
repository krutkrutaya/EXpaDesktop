// The Clipboard app: watches the Windows clipboard through sysctl.dll and
// keeps a searchable history. Pinned entries survive a clear and the trim.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../expa/clipboard_history.dart';
import '../../expa/clipboard_source.dart';
import '../../expa/clipboard_store.dart';
import '../../i18n.dart';
import '../../ui/glass.dart';

class ClipboardApp extends StatefulWidget {
  final ClipboardSource? source;
  final ClipboardStore? store;
  final Duration pollInterval;

  const ClipboardApp({
    super.key,
    this.source,
    this.store,
    this.pollInterval = const Duration(milliseconds: 900),
  });

  @override
  State<ClipboardApp> createState() => _ClipboardAppState();
}

class _ClipboardAppState extends State<ClipboardApp> {
  late final ClipboardSource _source;
  late final ClipboardStore _store;
  late ClipboardHistory _history;
  Timer? _poll;
  Timer? _statusTimer;
  int _sequence = 0;
  String _query = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? const NativeClipboardSource();
    _store = widget.store ?? ClipboardStore();
    _history = _store.load();
    // Read whatever is already on the clipboard once, then poll.
    _sequence = 0;
    _capture();
    _poll = Timer.periodic(widget.pollInterval, (_) => _capture());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _capture() {
    if (!mounted) return;
    final sequence = _source.sequence;
    if (sequence != 0 && sequence == _sequence) return;
    _sequence = sequence;
    final text = _source.readText();
    if (text == null || text.trim().isEmpty) return;
    setState(() => _history.add(text));
    unawaited(_store.save(_history));
  }

  void _copy(ClipboardEntry entry) {
    final ok = _source.writeText(entry.text);
    _sequence = _source.sequence;
    _showStatus(ok
        ? Loc.t('Copied to the clipboard', 'Скопировано в буфер')
        : Loc.t('The clipboard is busy', 'Буфер обмена занят'));
  }

  void _showStatus(String text) {
    setState(() => _status = text);
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _status = '');
    });
  }

  void _clearWindows() {
    final ok = _source.clear();
    _sequence = _source.sequence;
    _showStatus(ok
        ? Loc.t('Windows clipboard cleared', 'Буфер Windows очищен')
        : Loc.t('Could not clear the clipboard', 'Не удалось очистить буфер'));
  }

  void _clearHistory() {
    setState(_history.clear);
    unawaited(_store.save(_history));
  }

  List<ClipboardEntry> get _visible {
    if (_query.trim().isEmpty) return _history.entries;
    final q = _query.toLowerCase();
    return [
      for (final entry in _history.entries)
        if (entry.text.toLowerCase().contains(q)) entry,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.content_paste_rounded,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                Loc.t('Clipboard', 'Буфер обмена'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Caption('${_history.entries.length}'),
              const Spacer(),
              PillButton(
                key: const ValueKey('clipboard-clear'),
                label: Loc.t('Clear', 'Очистить'),
                icon: Icons.delete_sweep_outlined,
                onTap: _clearHistory,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: Loc.t('Search the history', 'Поиск по истории'),
              hintStyle:
                  const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 16, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 8),
          AppBarlessStatus(status: _status),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.content_copy_rounded,
                            size: 36,
                            color: Colors.white.withValues(alpha: 0.16)),
                        const SizedBox(height: 8),
                        Caption(Loc.t(
                          'Copy something in Windows — it will appear here.',
                          'Скопируй что-нибудь в Windows — это появится здесь.',
                        )),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      final realIndex = _history.entries.indexOf(entry);
                      return _ClipboardRow(
                        key: ValueKey('clipboard-entry-$realIndex'),
                        entry: entry,
                        index: realIndex,
                        onCopy: () => _copy(entry),
                        onPin: () {
                          setState(() => _history.togglePin(entry));
                          unawaited(_store.save(_history));
                        },
                        onDelete: () {
                          setState(() => _history.remove(entry));
                          unawaited(_store.save(_history));
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Caption(Loc.t(
                  'Watching the Windows clipboard',
                  'Слежу за буфером обмена Windows',
                )),
              ),
              PillButton(
                key: const ValueKey('clipboard-clear-windows'),
                label: Loc.t('Clear Windows', 'Очистить Windows'),
                onTap: _clearWindows,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AppBarlessStatus extends StatelessWidget {
  final String status;
  const AppBarlessStatus({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: status.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(status),
              padding: const EdgeInsets.only(bottom: 4),
              child: Caption(status),
            ),
    );
  }
}

class _ClipboardRow extends StatefulWidget {
  final ClipboardEntry entry;
  final int index;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _ClipboardRow({
    super.key,
    required this.entry,
    required this.index,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });

  @override
  State<_ClipboardRow> createState() => _ClipboardRowState();
}

class _ClipboardRowState extends State<_ClipboardRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onCopy,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: _hovered ? 0.45 : 0.30),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: Colors.white
                  .withValues(alpha: entry.pinned ? 0.30 : 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Caption(
                    '${entry.time.hour.toString().padLeft(2, '0')}:'
                    '${entry.time.minute.toString().padLeft(2, '0')}',
                    size: 9.5,
                  ),
                  const Spacer(),
                  _rowAction(
                    key: ValueKey('clipboard-copy-${widget.index}'),
                    icon: Icons.copy_rounded,
                    tooltip: Loc.t('Copy', 'Копировать'),
                    onTap: widget.onCopy,
                  ),
                  _rowAction(
                    key: ValueKey('clipboard-pin-${widget.index}'),
                    icon: entry.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    tooltip: entry.pinned
                        ? Loc.t('Unpin', 'Открепить')
                        : Loc.t('Pin', 'Закрепить'),
                    active: entry.pinned,
                    onTap: widget.onPin,
                  ),
                  _rowAction(
                    key: ValueKey('clipboard-delete-${widget.index}'),
                    icon: Icons.close_rounded,
                    tooltip: Loc.t('Remove', 'Удалить'),
                    onTap: widget.onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowAction({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Icon(
            icon,
            size: 15,
            color: active ? Colors.white : Colors.white38,
          ),
        ),
      ),
    );
  }
}