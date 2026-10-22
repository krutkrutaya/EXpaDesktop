// The clipboard seam. The app talks to this interface; the real one goes
// through sysctl.dll, the tests through a recorder. Keeping it behind an
// interface is also what makes the polling logic testable without touching
// the machine's real clipboard.

import '../native/sysctl.dart';

abstract class ClipboardSource {
  int get sequence;
  String? readText();
  bool writeText(String text);
  bool clear();
}

class NativeClipboardSource implements ClipboardSource {
  const NativeClipboardSource();

  @override
  int get sequence => SysCtl.clipboardSequence;

  @override
  String? readText() => SysCtl.clipboardText;

  @override
  bool writeText(String text) => SysCtl.setClipboardText(text);

  @override
  bool clear() => SysCtl.clearClipboard();
}