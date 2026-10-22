// A month of the in-shell Calendar: pure Dart, so the grid and week start are
// checked without a Flutter engine. Monday-first, ISO style.

class CalendarCell {
  final DateTime date;
  final bool inMonth;
  const CalendarCell(this.date, {required this.inMonth});
}

DateTime monthStart(DateTime month) => DateTime(month.year, month.month);

DateTime addMonths(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta);

/// 42 cells (six weeks), starting on the Monday on/before the first day.
List<CalendarCell> monthGrid(DateTime month) {
  final start = monthStart(month);
  final offset = start.weekday - DateTime.monday; // Monday = 1
  final first = start.subtract(Duration(days: offset));
  return [
    for (var i = 0; i < 42; i++)
      CalendarCell(
        DateTime(first.year, first.month, first.day + i),
        inMonth: first.add(Duration(days: i)).month == start.month,
      ),
  ];
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String weekdayName(int weekday) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][weekday - 1];

String monthName(int month) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];