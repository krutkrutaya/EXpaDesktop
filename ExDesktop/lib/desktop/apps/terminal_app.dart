// The Terminal window: cmd lines in, glass log out.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../apps/terminal_session.dart';
import '../../ui/glass.dart';

class TerminalApp extends StatefulWidget {
  /// Injectable for the tests.
  final TerminalSession? session;

  const TerminalApp({super.key, this.session});

  @override
  State<TerminalApp> createState() => _TerminalAppState();
}

class _TerminalAppState extends State<TerminalApp> {
  late final TerminalSession _session = widget.session ?? TerminalSession();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'terminal');
  final ScrollController _scroll = ScrollController();
  int _historyCursor = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final command = _input.text;
    if (command.trim().isEmpty) return;
    _input.clear();
    setState(() {});
    await _session.run(command);
    if (!mounted) return;
    _historyCursor = _session.history.length;
    setState(() {});
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _recall(int direction) {
    final history = _session.history;
    if (history.isEmpty) return;
    _historyCursor = (_historyCursor + direction).clamp(0, history.length);
    setState(() {
      _input.text = _historyCursor == history.length
          ? ''
          : history[_historyCursor];
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
    });
  }

  Color _color(TerminalLineKind kind) => switch (kind) {
        TerminalLineKind.command => const Color(0xFF9AD0FF),
        TerminalLineKind.output => Colors.white70,
        TerminalLineKind.error => const Color(0xFFFF9A9A),
        TerminalLineKind.info => Colors.white38,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 15, color: Colors.white54),
              const SizedBox(width: 8),
              const Caption('cmd · this machine'),
              const Spacer(),
              PillButton(
                key: const ValueKey('terminal-clear'),
                label: 'Clear',
                icon: Icons.layers_clear_outlined,
                onTap: () {
                  _session.clear();
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _session.lines.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'Type a command and press Enter.\n'
                        'Try: dir, echo hello, whoami',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.6,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: _session.lines.length,
                      itemBuilder: (context, index) {
                        final line = _session.lines[index];
                        return SelectableText(
                          line.text,
                          style: TextStyle(
                            color: _color(line.kind),
                            fontSize: 12,
                            height: 1.5,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            radius: 11,
            child: Row(
              children: [
                const Text(
                  '>',
                  style: TextStyle(
                    color: Color(0xFF9AFFA5),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _recall(-1);
                        return KeyEventResult.handled;
                      }
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        _recall(1);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      key: const ValueKey('terminal-input'),
                      controller: _input,
                      focusNode: _focus,
                      enabled: !_session.busy,
                      onSubmitted: (_) => unawaited(_run()),
                      cursorColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 11),
                        hintText: _session.busy ? 'Running…' : 'Command',
                        hintStyle: const TextStyle(
                          color: Colors.white24,
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}