// EXWM's server: one window manager per in-app workspace, plus the focus,
// snap and lifecycle operations the desktop environment calls.
//
// The server is pure Dart. The DE (EXPA, `lib/expa/`) owns the chrome, the
// panels and the apps; EXWM owns the windows. Keeping the boundary here means
// the whole window model can be tested with `dart run`, no Flutter engine.

import '../desktop/app_catalog.dart';
import 'snap.dart';
import 'window_manager.dart';
import 'workspaces.dart';

class WmServer {
  WmServer({
    required this.workspaces,
    required DesktopArea area,
  }) : _area = area {
    workspaces.addListener(_onWorkspaces);
  }

  final WorkspaceController workspaces;
  DesktopArea _area;
  final Map<int, WindowManager> _managers = {};
  final List<void Function()> _listeners = [];

  DesktopArea get area => _area;

  /// One manager per workspace id, created on first use.
  WindowManager managerFor(int workspaceId) => _managers.putIfAbsent(
        workspaceId,
        () {
          final manager = WindowManager(area: _area);
          manager.configure(snapEnabled: snapEnabled, snapGap: snapGap);
          return manager;
        },
      );

  WindowManager get activeManager => managerFor(workspaces.active.id);

  List<WindowManager> get managers => List.unmodifiable(_managers.values);

  /// Total open windows across every workspace.
  int get windowCount {
    var total = 0;
    for (final manager in _managers.values) {
      total += manager.count;
    }
    return total;
  }

  AppWindow? get activeWindow => activeManager.active;

  // Behaviour knobs owned by the DE (Settings → Windows & multitasking).
  bool snapEnabled = true;
  double snapGap = 5;

  void configure({bool? snapEnabled, double? snapGap}) {
    if (snapEnabled != null) this.snapEnabled = snapEnabled;
    if (snapGap != null) this.snapGap = snapGap.clamp(0.0, 32.0).toDouble();
    for (final manager in _managers.values) {
      manager.configure(
        snapEnabled: this.snapEnabled,
        snapGap: this.snapGap,
      );
    }
  }

  void retarget(DesktopArea area) {
    _area = area;
    for (final manager in _managers.values) {
      manager.retarget(area);
    }
  }

  AppWindow open(ShellApp app) {
    final window = activeManager.open(app);
    _notify();
    return window;
  }

  void focus(int id) {
    activeManager.focus(id);
    _notify();
  }

  void close(int id) {
    activeManager.close(id);
    _notify();
  }

  void minimize(int id) {
    activeManager.minimize(id);
    _notify();
  }

  bool minimizeActive() {
    final changed = activeManager.minimizeActive();
    if (changed) _notify();
    return changed;
  }

  bool snapActive(SnapZone zone) {
    final changed = activeManager.snapActive(zone);
    if (changed) _notify();
    return changed;
  }

  AppWindow? cycleFocus() {
    final window = activeManager.cycleFocus();
    _notify();
    return window;
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  /// Closing a workspace drops its windows; reopening the same id later
  /// starts clean. Wallpaper changes also notify the controller, but they must
  /// not notify the shell here — the wallpaper layer already repaints itself.
  void _onWorkspaces() {
    final alive = workspaces.items.map((workspace) => workspace.id).toSet();
    final before = _managers.length;
    _managers.removeWhere((id, _) => !alive.contains(id));
    if (_managers.length != before) _notify();
  }

  void dispose() {
    workspaces.removeListener(_onWorkspaces);
    _listeners.clear();
    _managers.clear();
  }
}