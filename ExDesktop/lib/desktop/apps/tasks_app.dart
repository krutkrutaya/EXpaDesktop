// The Tasks window: a real list that survives closing the window.

import 'package:flutter/material.dart';

import '../../apps/task_board.dart';
import '../../ui/glass.dart';

class TasksApp extends StatefulWidget {
  const TasksApp({super.key});

  @override
  State<TasksApp> createState() => _TasksAppState();
}

class _TasksAppState extends State<TasksApp> {
  final TaskBoard _board = TaskBoard();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'tasks');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final task = _board.add(_input.text);
    if (task == null) return;
    _input.clear();
    setState(() {});
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  radius: 12,
                  child: TextField(
                    key: const ValueKey('tasks-input'),
                    controller: _input,
                    focusNode: _focus,
                    onSubmitted: (_) => _add(),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      hintText: 'What needs doing?',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              HoverIcon(
                key: const ValueKey('tasks-add'),
                icon: Icons.add_rounded,
                onTap: _add,
                tooltip: 'Add task',
                size: 40,
                iconSize: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _board.isEmpty
                ? const Center(
                    child: Caption('Nothing yet. Add the first task above.'),
                  )
                : ListView.builder(
                    itemCount: _board.count,
                    itemBuilder: (context, index) {
                      final task = _board.items[index];
                      return _TaskRow(
                        key: ValueKey('task-${task.id}'),
                        task: task,
                        onToggle: () {
                          _board.toggle(task.id);
                          setState(() {});
                        },
                        onRemove: () {
                          _board.remove(task.id);
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Caption('${_board.openCount} open · ${_board.doneCount} done'),
              const Spacer(),
              if (_board.doneCount > 0)
                PillButton(
                  key: const ValueKey('tasks-clear-done'),
                  label: 'Clear done',
                  icon: Icons.cleaning_services_outlined,
                  onTap: () {
                    _board.clearDone();
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatefulWidget {
  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  const _TaskRow({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final done = widget.task.done;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.09 : 0.05),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: done ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: done ? 0.9 : 0.3),
                  ),
                ),
                child: done
                    ? const Icon(Icons.check, size: 13, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.task.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: done ? Colors.white38 : Colors.white,
                    fontSize: 13,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white38,
                  ),
                ),
              ),
              if (_hovered)
                HoverIcon(
                  key: ValueKey('task-remove-${widget.task.id}'),
                  icon: Icons.close_rounded,
                  size: 26,
                  iconSize: 14,
                  tooltip: 'Remove',
                  onTap: widget.onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}