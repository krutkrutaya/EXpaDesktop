// Virtual desktops, the way Windows itself exposes them: the Win+Ctrl key
// chords. There is no documented Win32 call for "switch desktop" that works
// across Windows versions (the COM interfaces behind the task view are
// undocumented and change between builds), but the shortcuts are stable and
// do exactly what the task view buttons do.
//
// The chord table is pure data, so the mock suite asserts the exact keys
// without ever pressing one; only [VirtualDesktopController.perform] touches
// the keyboard, and the widget tests inject a recorder instead.

import 'dart:ffi';
import 'dart:io';

/// The desktop operations the shell offers.
enum VirtualDesktopAction {
  create('Новый'),
  next('Следующий'),
  previous('Предыдущий'),
  close('Закрыть'),
  overview('Обзор');

  const VirtualDesktopAction(this.label);

  /// The Russian caption on the panel button.
  final String label;
}

/// Where a desktop operation goes. The shell uses the real keyboard; the
/// tests use a recorder.
abstract class VirtualDesktopSink {
  void perform(VirtualDesktopAction action);
}

typedef _KeybdEventNative = Void Function(
  Uint8 virtualKey,
  Uint8 scanCode,
  Uint32 flags,
  IntPtr extraInfo,
);
typedef _KeybdEventDart = void Function(
  int virtualKey,
  int scanCode,
  int flags,
  int extraInfo,
);

class VirtualDesktopController implements VirtualDesktopSink {
  VirtualDesktopController._();

  static final VirtualDesktopController instance = VirtualDesktopController._();

  // Virtual-key codes, from WinUser.h.
  static const int vkLeftWin = 0x5B;
  static const int vkControl = 0x11;
  static const int vkLeft = 0x25;
  static const int vkRight = 0x27;
  static const int vkTab = 0x09;
  static const int vkF4 = 0x73;
  static const int vkD = 0x44;

  static const int _keyUp = 0x0002;

  _KeybdEventDart? _keybdEvent;

  /// The keys for [action], in press order. Pure: the tests read this table.
  static List<int> chordFor(VirtualDesktopAction action) => switch (action) {
        VirtualDesktopAction.create => const [vkLeftWin, vkControl, vkD],
        VirtualDesktopAction.next => const [vkLeftWin, vkControl, vkRight],
        VirtualDesktopAction.previous => const [vkLeftWin, vkControl, vkLeft],
        VirtualDesktopAction.close => const [vkLeftWin, vkControl, vkF4],
        VirtualDesktopAction.overview => const [vkLeftWin, vkTab],
      };

  @override
  void perform(VirtualDesktopAction action) {
    sendKeys(chordFor(action));
  }

  /// Presses every key in [keys], then releases them in reverse order.
  ///
  /// `keybd_event` is the simple, still-supported way to synthesise the
  /// chord; SendInput would need the INPUT union laid out by hand.
  void sendKeys(List<int> keys) {
    if (!Platform.isWindows) return;
    try {
      _keybdEvent ??= DynamicLibrary.open('user32.dll')
          .lookupFunction<_KeybdEventNative, _KeybdEventDart>('keybd_event');
      for (final key in keys) {
        _keybdEvent!(key, 0, 0, 0);
      }
      for (final key in keys.reversed) {
        _keybdEvent!(key, 0, _keyUp, 0);
      }
    } catch (_) {
      // No user32 (or a locked-down session): the panel simply does nothing.
    }
  }
}