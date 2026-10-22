// The Calendar widget: a real month view, Monday-first, with previous/next/
// today navigation. No events yet — the date grid itself is the feature the
// waybar's calendar button opens.

import 'package:flutter/material.dart';

import '../../expa/calendar_month.dart';
import '../../ui/glass.dart';

class CalendarApp extends StatefulWidget {
  final DateTime? initialMonth;
  final DateTime? now;

  const CalendarApp({super.key, this.initialMonth, this.now});

  @override
  State<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends State<CalendarApp> {
  late DateTime _month;
  late DateTime _selected;

  DateTime get _today => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _month = monthStart(widget.initialMonth ?? _today);
    _selected = _today;
  }

  void _go(int delta) {
    setState(() => _month = addMonths(_month, delta));
  }

  void _goToday() {
    setState(() {
      _month = monthStart(_today);
      _selected = _today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final grid = monthGrid(_month);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                '${monthName(_month.month)} ${_month.year}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _roundButton(
                key: const ValueKey('calendar-prev'),
                icon: Icons.chevron_left_rounded,
                onTap: () => _go(-1),
              ),
              const SizedBox(width: 4),
              _roundButton(
                key: const ValueKey('calendar-today'),
                icon: Icons.today_rounded,
                onTap: _goToday,
              ),
              const SizedBox(width: 4),
              _roundButton(
                key: const ValueKey('calendar-next'),
                icon: Icons.chevron_right_rounded,
                onTap: () => _go(1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final day in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
              ),
              itemCount: grid.length,
              itemBuilder: (context, index) {
                final cell = grid[index];
                final selected = isSameDay(cell.date, _selected);
                final today = isSameDay(cell.date, _today);
                return GestureDetector(
                  key: ValueKey(
                    'calendar-day-${cell.date.year}-'
                    '${cell.date.month}-${cell.date.day}',
                  ),
                  onTap: () => setState(() => _selected = cell.date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : today
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: today && !selected
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.35))
                          : null,
                    ),
                    child: Text(
                      '${cell.date.day}',
                      style: TextStyle(
                        color: selected
                            ? Colors.black
                            : cell.inMonth
                                ? Colors.white
                                : Colors.white24,
                        fontSize: 12.5,
                        fontWeight: selected || today
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Caption(
              '${weekdayName(_selected.weekday)}, ${monthName(_selected.month)} '
              '${_selected.day}, ${_selected.year}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );
  }
}