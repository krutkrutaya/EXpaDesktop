// System master volume through COM, no extra native library needed.
//
// dart:ffi walks the classic audio chain: CoCreateInstance returns the
// MMDeviceEnumerator, GetDefaultAudioEndpoint picks the playback device, and
// Activate hands back an IAudioEndpointVolume. After that every operation is
// an indexed vtable call on that endpoint.
//
// Designed to fail soft: if COM refuses (an odd Windows install, wrong
// arch), the getter returns the last known value and the setter keeps the
// UI alive — the panel just cannot push a real change.

import 'dart:ffi';
import 'dart:math' as math;

// Small self-owned heap allocator (msvcrt malloc) so this file needs no
// package:ffi dependency — four buffer kinds here, all freed immediately.
typedef _HeapMallocNative = Pointer<Void> Function(IntPtr size);
typedef _HeapMallocDart = Pointer<Void> Function(int size);
typedef _HeapFreeNative = Void Function(Pointer<Void> address);
typedef _HeapFreeDart = void Function(Pointer<Void> address);

_HeapMallocDart? _heapMalloc;
_HeapFreeDart? _heapFree;

Pointer<T> _alloc<T extends NativeType>(int bytes) {
  _heapMalloc ??= DynamicLibrary.open('ucrtbase.dll')
      .lookupFunction<_HeapMallocNative, _HeapMallocDart>('malloc');
  return _heapMalloc!(bytes).cast<T>();
}

void _free(Pointer<NativeType> address) {
  if (address.address == 0) return;
  _heapFree ??= DynamicLibrary.open('ucrtbase.dll')
      .lookupFunction<_HeapFreeNative, _HeapFreeDart>('free');
  _heapFree!(address.cast<Void>());
}

const int _sOk = 0;
const int _rpcEChangedMode = -2147417850; // COM already initialized elsewhere
const int _clsCtxAll = 23; // CLSCTX_ALL
const int _dfdRender = 0; // eRender
const int _roleMultimedia = 1; // eMultimedia
const int _ptrSize = 8; // x64

// GUID layouts: Data1 (LE u32), Data2 (LE u16), Data3 (LE u16), Data4 (8b).
const List<int> _bytesClsidEnumerator = [
  0x95, 0x03, 0xDE, 0xBC, // BCDE0395
  0x2F, 0xE5, // E52F
  0x7C, 0x46, // 467C
  0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E, // C4579291692E
];
const List<int> _bytesIidEnumerator = [
  0xD2, 0x64, 0x56, 0xA9, // A95664D2
  0x14, 0x96, // 9614
  0x35, 0x4F, // 4F35
  0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6, // A746DE8DB63617E6
];
const List<int> _bytesIidEndpointVolume = [
  0x82, 0x2C, 0xDF, 0x5C, // 5CDF2C82
  0x1E, 0x84, // 841E
  0x46, 0x45, // 4546
  0x97, 0x22, 0x0C, 0xF7, 0x40, 0x78, 0x22, 0x9A, // 97220CF74078229A
];

final class _GuidPacked extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

Pointer<_GuidPacked> _guidFromBytes(List<int> bytes) {
  final p = _alloc<_GuidPacked>(16);
  final r = p.ref;
  r.data1 = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  r.data2 = bytes[4] | (bytes[5] << 8);
  r.data3 = bytes[6] | (bytes[7] << 8);
  for (var i = 0; i < 8; i++) {
    r.data4[i] = bytes[8 + i];
  }
  return p;
}

// ---- ole32 entry points ----------------------------------------------------

typedef _CoInitializeExNative = Int32 Function(Pointer<Void> reserved, Uint32 model);
typedef _CoInitializeExDart = int Function(Pointer<Void> reserved, int model);

typedef _CoCreateInstanceNative = Int32 Function(
  Pointer<_GuidPacked> clsid,
  Pointer<Void> outer,
  Uint32 clsContext,
  Pointer<_GuidPacked> iid,
  Pointer<Pointer<Void>> outObject,
);
typedef _CoCreateInstanceDart = int Function(
  Pointer<_GuidPacked> clsid,
  Pointer<Void> outer,
  int clsContext,
  Pointer<_GuidPacked> iid,
  Pointer<Pointer<Void>> outObject,
);

// ---- vtable signatures -----------------------------------------------------

// IMMDeviceEnumerator[4]: GetDefaultAudioEndpoint(self, flow, role, outDevice)
typedef _GetDefaultEndpointNative = Int32 Function(
  Pointer<Void> self,
  Uint32 dataFlow,
  Uint32 role,
  Pointer<Pointer<Void>> outDevice,
);
typedef _GetDefaultEndpointDart = int Function(
  Pointer<Void> self,
  int dataFlow,
  int role,
  Pointer<Pointer<Void>> outDevice,
);

// IMMDevice[3]: Activate(self, riid, clsCtx, activationParams, outInterface)
typedef _ActivateNative = Int32 Function(
  Pointer<Void> self,
  Pointer<_GuidPacked> riid,
  Uint32 clsCtx,
  Pointer<Void> activationParams,
  Pointer<Pointer<Void>> outInterface,
);
typedef _ActivateDart = int Function(
  Pointer<Void> self,
  Pointer<_GuidPacked> riid,
  int clsCtx,
  Pointer<Void> activationParams,
  Pointer<Pointer<Void>> outInterface,
);

// IAudioEndpointVolume[7]: SetMasterVolumeLevelScalar(self, level, ctx)
typedef _SetMasterNative = Int32 Function(
  Pointer<Void> self,
  Float level,
  Pointer<_GuidPacked> ctx,
);
typedef _SetMasterDart = int Function(
  Pointer<Void> self,
  double level,
  Pointer<_GuidPacked> ctx,
);

// IAudioEndpointVolume[9]: GetMasterVolumeLevelScalar(self, outLevel)
typedef _GetMasterNative = Int32 Function(Pointer<Void> self, Pointer<Float> outLevel);
typedef _GetMasterDart = int Function(Pointer<Void> self, Pointer<Float> outLevel);

// IAudioEndpointVolume[14]: SetMute(self, mute, ctx)
typedef _SetMuteNative = Int32 Function(
  Pointer<Void> self,
  Int32 mute,
  Pointer<_GuidPacked> ctx,
);
typedef _SetMuteDart = int Function(
  Pointer<Void> self,
  int mute,
  Pointer<_GuidPacked> ctx,
);

// IAudioEndpointVolume[15]: GetMute(self, outMute)
typedef _GetMuteNative = Int32 Function(Pointer<Void> self, Pointer<Int32> outMute);
typedef _GetMuteDart = int Function(Pointer<Void> self, Pointer<Int32> outMute);

// Resolve vtable[index] for a typed signature: the interface pointer's first
// field holds the vtable address; each slot sits at index * pointer size and
// ITSELF holds the function pointer — so the slot is read first (a plain
// pointer deref), then the value is interpreted as the typed entry point.
_GetDefaultEndpointDart _fnGetDefault(Pointer<Void> self) => Pointer
    .fromAddress(self.cast<IntPtr>().value + 4 * _ptrSize)
    .cast<Pointer<NativeFunction<_GetDefaultEndpointNative>>>()
    .value
    .asFunction<_GetDefaultEndpointDart>();

_ActivateDart _fnActivate(Pointer<Void> self) => Pointer
    .fromAddress(self.cast<IntPtr>().value + 3 * _ptrSize)
    .cast<Pointer<NativeFunction<_ActivateNative>>>()
    .value
    .asFunction<_ActivateDart>();

_SetMasterDart _fnSetMaster(Pointer<Void> self) => Pointer
    .fromAddress(self.cast<IntPtr>().value + 7 * _ptrSize)
    .cast<Pointer<NativeFunction<_SetMasterNative>>>()
    .value
    .asFunction<_SetMasterDart>();

_GetMasterDart _fnGetMaster(Pointer<Void> self) => Pointer
    .fromAddress(self.cast<IntPtr>().value + 9 * _ptrSize)
    .cast<Pointer<NativeFunction<_GetMasterNative>>>()
    .value
    .asFunction<_GetMasterDart>();

_SetMuteDart _fnSetMute(Pointer<Void> self) => Pointer
    .fromAddress(self.cast<IntPtr>().value + 14 * _ptrSize)
    .cast<Pointer<NativeFunction<_SetMuteNative>>>()
    .value
    .asFunction<_SetMuteDart>();

_GetMuteDart _fnGetMute(Pointer<Void> self) => Pointer
    .fromAddress(self.cast<IntPtr>().value + 15 * _ptrSize)
    .cast<Pointer<NativeFunction<_GetMuteNative>>>()
    .value
    .asFunction<_GetMuteDart>();

// ---- public surface ---------------------------------------------------------

class VolumeControl {
  VolumeControl._();

  static final VolumeControl instance = VolumeControl._();

  bool _ready = false;
  double _coarseVolume = 0.5;
  bool _coarseMuted = false;

  Pointer<_GuidPacked>? _clsid;
  Pointer<_GuidPacked>? _iidEnum;
  Pointer<_GuidPacked>? _iidEndpoint;
  Pointer<Void>? _enumerator;
  Pointer<Void>? _device;
  Pointer<Void>? _endpoint;
  _CoInitializeExDart? _coInitialize;
  _CoCreateInstanceDart? _coCreate;

  /// Volume in [0..1]; last known value when COM is unavailable.
  double get volume {
    final e = _ensure();
    if (e == null) return _coarseVolume;
    final out = _alloc<Float>(4);
    try {
      final v = _fnGetMaster(e)(e, out).toDouble();
      if (v >= 0.0 && v <= 1.0) _coarseVolume = v;
      return v;
    } catch (_) {
      return _coarseVolume;
    } finally {
      _free(out);
    }
  }

  /// Whether the default playback device reports itself muted.
  bool get muted {
    final e = _ensure();
    if (e == null) return _coarseMuted;
    final out = _alloc<Int32>(4);
    try {
      final v = _fnGetMute(e)(e, out) != 0;
      _coarseMuted = v;
      return v;
    } catch (_) {
      return _coarseMuted;
    } finally {
      _free(out);
    }
  }

  set volume(double value) {
    final v = value.clamp(0.0, 1.0);
    _coarseVolume = v;
    final e = _ensure();
    if (e == null) return;
    try {
      _fnSetMaster(e)(e, v, nullptr.cast<_GuidPacked>());
    } catch (_) {}
  }

  set muted(bool value) {
    _coarseMuted = value;
    final e = _ensure();
    if (e == null) return;
    try {
      _fnSetMute(e)(e, value ? 1 : 0, nullptr.cast<_GuidPacked>());
    } catch (_) {}
  }

  /// Media-key style fallback so the UI can still move somewhere even if
  /// COM refuses: steps the volume at the keyboard's 2% rate.
  void stepVolume(double direction) {
    _coarseVolume = (_coarseVolume + 0.02 * direction).clamp(0.0, 1.0);
    final e = _ensure();
    if (e == null) return;
    try {
      _fnSetMaster(e)(
          e, math.max(0.0, math.min(1.0, _coarseVolume)), nullptr.cast<_GuidPacked>());
    } catch (_) {}
  }

  // ---- setup ----------------------------------------------------------------

  /// Returns the endpoint volume interface pointer, or null if COM setup
  /// fails. Runs at most once; afterwards it is a plain pointer return.
  Pointer<Void>? _ensure() {
    if (_ready) return _endpoint;
    try {
      final ole32 = DynamicLibrary.open('ole32.dll');
      _coInitialize = ole32
          .lookupFunction<_CoInitializeExNative, _CoInitializeExDart>(
              'CoInitializeEx');
      final hrInit = _coInitialize!(nullptr.cast<Void>(), 0); // MTA
      if (hrInit != _sOk && hrInit != _rpcEChangedMode) return null;

      _coCreate = ole32
          .lookupFunction<_CoCreateInstanceNative, _CoCreateInstanceDart>(
              'CoCreateInstance');
      _clsid = _guidFromBytes(_bytesClsidEnumerator);
      _iidEnum = _guidFromBytes(_bytesIidEnumerator);
      _iidEndpoint = _guidFromBytes(_bytesIidEndpointVolume);

      final enumeratorOut = _alloc<Pointer<Void>>(8);
      final hrEnum = _coCreate!(
        _clsid!,
        nullptr.cast<Void>(),
        _clsCtxAll,
        _iidEnum!,
        enumeratorOut,
      );
      if (hrEnum != _sOk) {
        _free(enumeratorOut);
        return null;
      }
      _enumerator = enumeratorOut.value;
      _free(enumeratorOut);
      if (_enumerator == null || _enumerator!.address == 0) return null;

      final deviceOut = _alloc<Pointer<Void>>(8);
      final hrDevice =
          _fnGetDefault(_enumerator!)(
              _enumerator!, _dfdRender, _roleMultimedia, deviceOut);
      if (hrDevice != _sOk) {
        _free(deviceOut);
        return null;
      }
      _device = deviceOut.value;
      _free(deviceOut);
      if (_device == null || _device!.address == 0) return null;

      final endpointOut = _alloc<Pointer<Void>>(8);
      final hrEndpoint = _fnActivate(_device!)(
        _device!,
        _iidEndpoint!,
        _clsCtxAll,
        nullptr.cast<Void>(),
        endpointOut,
      );
      if (hrEndpoint != _sOk) {
        _free(endpointOut);
        return null;
      }
      _endpoint = endpointOut.value;
      _free(endpointOut);
      if (_endpoint == null || _endpoint!.address == 0) return null;

      _ready = true;
      return _endpoint;
    } catch (_) {
      return null;
    }
  }
}
