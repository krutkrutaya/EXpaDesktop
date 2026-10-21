// A tiny self-owned heap allocator, so the native modules here need no
// package:ffi dependency.
//
// Everything the FFI code allocates is freed immediately after use, so a
// bump-free malloc/free pair from the CRT is all that is needed. ucrtbase.dll
// ships with every modern Windows and matches the Dart runtime's allocator,
// which keeps the pointers valid across the FFI boundary.

import 'dart:ffi';

typedef _HeapMallocNative = Pointer<Void> Function(IntPtr size);
typedef _HeapMallocDart = Pointer<Void> Function(int size);
typedef _HeapFreeNative = Void Function(Pointer<Void> address);
typedef _HeapFreeDart = void Function(Pointer<Void> address);

class NativeHeap {
  NativeHeap._();

  static _HeapMallocDart? _malloc;
  static _HeapFreeDart? _free;

  static Pointer<T> alloc<T extends NativeType>(int bytes) {
    _malloc ??= DynamicLibrary.open('ucrtbase.dll')
        .lookupFunction<_HeapMallocNative, _HeapMallocDart>('malloc');
    return _malloc!(bytes).cast<T>();
  }

  static void free(Pointer<NativeType> address) {
    if (address.address == 0) return;
    _free ??= DynamicLibrary.open('ucrtbase.dll')
        .lookupFunction<_HeapFreeNative, _HeapFreeDart>('free');
    _free!(address.cast<Void>());
  }
}
