// Mouse and keyboard settings behind a seam.
//
// The real source is sysctl.dll / SystemParametersInfoW; the widget tests use
// a recorder so dragging the pointer-speed slider never changes the machine
// running the tests.

import '../native/sysctl.dart';

abstract class InputSource {
  int? get mouseSpeed;
  bool? get mouseSwap;
  int? get wheelLines;
  int? get keyDelay;
  int? get keySpeed;

  void setMouseSpeed(int value);
  void setMouseSwap(bool value);
  void setWheelLines(int value);
  void setKeyDelay(int value);
  void setKeySpeed(int value);
}

class NativeInputSource implements InputSource {
  const NativeInputSource();

  @override
  int? get mouseSpeed => SysCtl.mouseSpeed;
  @override
  bool? get mouseSwap => SysCtl.mouseSwap;
  @override
  int? get wheelLines => SysCtl.wheelLines;
  @override
  int? get keyDelay => SysCtl.keyboardDelay;
  @override
  int? get keySpeed => SysCtl.keyboardSpeed;

  @override
  void setMouseSpeed(int value) => SysCtl.setMouseSpeed(value);
  @override
  void setMouseSwap(bool value) => SysCtl.setMouseSwap(value);
  @override
  void setWheelLines(int value) => SysCtl.setWheelLines(value);
  @override
  void setKeyDelay(int value) => SysCtl.setKeyboardDelay(value);
  @override
  void setKeySpeed(int value) => SysCtl.setKeyboardSpeed(value);
}

class InputSettings {
  InputSettings(this.source);

  final InputSource source;

  int mouseSpeed = 10;
  bool mouseSwap = false;
  int wheelLines = 3;
  int keyDelay = 1;
  int keySpeed = 31;

  void load() {
    mouseSpeed = source.mouseSpeed ?? mouseSpeed;
    mouseSwap = source.mouseSwap ?? mouseSwap;
    wheelLines = source.wheelLines ?? wheelLines;
    keyDelay = source.keyDelay ?? keyDelay;
    keySpeed = source.keySpeed ?? keySpeed;
  }

  void updateMouseSpeed(int value) {
    mouseSpeed = value.clamp(1, 20);
    source.setMouseSpeed(mouseSpeed);
  }

  void updateMouseSwap(bool value) {
    mouseSwap = value;
    source.setMouseSwap(value);
  }

  void updateWheelLines(int value) {
    wheelLines = value.clamp(1, 20);
    source.setWheelLines(wheelLines);
  }

  void updateKeyDelay(int value) {
    keyDelay = value.clamp(0, 3);
    source.setKeyDelay(keyDelay);
  }

  void updateKeySpeed(int value) {
    keySpeed = value.clamp(0, 31);
    source.setKeySpeed(keySpeed);
  }
}