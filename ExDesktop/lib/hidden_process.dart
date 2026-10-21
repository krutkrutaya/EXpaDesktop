// Runs console tools without a console window and captures what they print.
//
// Dart's Process.start always gives a console program a console of its own,
// so every netsh / powershell call flashes a black window over the desktop.
// This module goes straight to CreateProcessW with CREATE_NO_WINDOW and
// pipes the child's stdout and stderr back, so the shell can ask the system
// questions (radio state, adapter list) without touching the screen.
//
// The whole dance happens in a worker isolate: the pipe reads are blocking
// FFI calls, and the UI thread must never sit in one.

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'native_heap.dart';

/// What a hidden console run produced.
class HiddenResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const HiddenResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// True when the tool reported a successful run.
  bool get ok => exitCode == 0;

  /// stdout split into trimmed, non-empty lines.
  List<String> get lines => stdout
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

typedef _CreatePipeNative = Int32 Function(
  Pointer<Pointer<Void>> readPipe,
  Pointer<Pointer<Void>> writePipe,
  Pointer<_SecurityAttributes> attributes,
  Uint32 size,
);
typedef _CreatePipeDart = int Function(
  Pointer<Pointer<Void>> readPipe,
  Pointer<Pointer<Void>> writePipe,
  Pointer<_SecurityAttributes> attributes,
  int size,
);

typedef _CreateProcessWNative = Int32 Function(
  Pointer<Uint16> applicationName,
  Pointer<Uint16> commandLine,
  Pointer<Void> processAttributes,
  Pointer<Void> threadAttributes,
  Int32 inheritHandles,
  Uint32 creationFlags,
  Pointer<Void> environment,
  Pointer<Uint16> currentDirectory,
  Pointer<_StartupInfo> startupInfo,
  Pointer<_ProcessInformation> processInformation,
);
typedef _CreateProcessWDart = int Function(
  Pointer<Uint16> applicationName,
  Pointer<Uint16> commandLine,
  Pointer<Void> processAttributes,
  Pointer<Void> threadAttributes,
  int inheritHandles,
  int creationFlags,
  Pointer<Void> environment,
  Pointer<Uint16> currentDirectory,
  Pointer<_StartupInfo> startupInfo,
  Pointer<_ProcessInformation> processInformation,
);

typedef _ReadFileNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Uint8> buffer,
  Uint32 bytesToRead,
  Pointer<Uint32> bytesRead,
  Pointer<Void> overlapped,
);
typedef _ReadFileDart = int Function(
  Pointer<Void> handle,
  Pointer<Uint8> buffer,
  int bytesToRead,
  Pointer<Uint32> bytesRead,
  Pointer<Void> overlapped,
);

typedef _PeekNamedPipeNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Uint8> buffer,
  Uint32 bufferSize,
  Pointer<Uint32> bytesRead,
  Pointer<Uint32> totalAvailable,
  Pointer<Uint32> leftThisMessage,
);
typedef _PeekNamedPipeDart = int Function(
  Pointer<Void> handle,
  Pointer<Uint8> buffer,
  int bufferSize,
  Pointer<Uint32> bytesRead,
  Pointer<Uint32> totalAvailable,
  Pointer<Uint32> leftThisMessage,
);

typedef _CloseHandleNative = Int32 Function(Pointer<Void> handle);
typedef _CloseHandleDart = int Function(Pointer<Void> handle);

typedef _WaitForSingleObjectNative = Uint32 Function(
  Pointer<Void> handle,
  Uint32 milliseconds,
);
typedef _WaitForSingleObjectDart = int Function(
  Pointer<Void> handle,
  int milliseconds,
);

typedef _GetExitCodeProcessNative = Int32 Function(
  Pointer<Void> process,
  Pointer<Uint32> exitCode,
);
typedef _GetExitCodeProcessDart = int Function(
  Pointer<Void> process,
  Pointer<Uint32> exitCode,
);

typedef _TerminateProcessNative = Int32 Function(
  Pointer<Void> process,
  Uint32 exitCode,
);
typedef _TerminateProcessDart = int Function(
  Pointer<Void> process,
  int exitCode,
);

typedef _SleepNative = Void Function(Uint32 milliseconds);
typedef _SleepDart = void Function(int milliseconds);

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;
  external Pointer<Void> lpSecurityDescriptor;
  @Int32()
  external int bInheritHandle;
}

// STARTUPINFOW, laid out exactly as the C struct on x64.
final class _StartupInfo extends Struct {
  @Int32()
  external int cb;
  external Pointer<Uint16> lpReserved;
  external Pointer<Uint16> lpDesktop;
  external Pointer<Uint16> lpTitle;
  @Uint32()
  external int dwX;
  @Uint32()
  external int dwY;
  @Uint32()
  external int dwXSize;
  @Uint32()
  external int dwYSize;
  @Uint32()
  external int dwXCountChars;
  @Uint32()
  external int dwYCountChars;
  @Uint32()
  external int dwFillAttribute;
  @Uint32()
  external int dwFlags;
  @Uint16()
  external int wShowWindow;
  @Uint16()
  external int cbReserved2;
  external Pointer<Uint8> lpReserved2;
  external Pointer<Void> hStdInput;
  external Pointer<Void> hStdOutput;
  external Pointer<Void> hStdError;
}

final class _ProcessInformation extends Struct {
  external Pointer<Void> hProcess;
  external Pointer<Void> hThread;
  @Uint32()
  external int dwProcessId;
  @Uint32()
  external int dwThreadId;
}

const int _startfUseStdHandles = 0x00000100;
const int _createNoWindow = 0x08000000;
const int _infinite = 0xFFFFFFFF;
const int _ioBufferSize = 16 * 1024;
const int _pollIntervalMs = 4;

/// Runs [executable] with [arguments] and returns what it printed.
///
/// The child gets no window of its own and no console: on a desktop shell a
/// flashing black rectangle would be the most visible thing on screen.
Future<HiddenResult> runHidden(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 15),
}) {
  return Isolate.run(
    () => _runHiddenSync(executable, arguments, timeout.inMilliseconds),
  );
}

/// Runs a PowerShell script by value: the script text is base64-encoded as
/// UTF-16LE and handed over as -EncodedCommand, so no temporary file and no
/// quoting rules are involved.
Future<HiddenResult> runPowerShell(
  String script, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final encoded = base64.encode(utf8.encode(script).expand(
        (b) => <int>[b, 0],
      ).toList());
  return runHidden(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      encoded,
    ],
    timeout: timeout,
  );
}

HiddenResult _runHiddenSync(
  String executable,
  List<String> arguments,
  int timeoutMs,
) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final createPipe = kernel32
      .lookupFunction<_CreatePipeNative, _CreatePipeDart>('CreatePipe');
  final createProcess = kernel32
      .lookupFunction<_CreateProcessWNative, _CreateProcessWDart>('CreateProcessW');
  final readFile =
      kernel32.lookupFunction<_ReadFileNative, _ReadFileDart>('ReadFile');
  final peekNamedPipe = kernel32
      .lookupFunction<_PeekNamedPipeNative, _PeekNamedPipeDart>('PeekNamedPipe');
  final closeHandle =
      kernel32.lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  final waitForSingleObject = kernel32.lookupFunction<
      _WaitForSingleObjectNative, _WaitForSingleObjectDart>(
    'WaitForSingleObject',
  );
  final getExitCodeProcess = kernel32.lookupFunction<
      _GetExitCodeProcessNative, _GetExitCodeProcessDart>(
    'GetExitCodeProcess',
  );
  final terminateProcess = kernel32.lookupFunction<
      _TerminateProcessNative, _TerminateProcessDart>(
    'TerminateProcess',
  );
  final sleep = kernel32.lookupFunction<_SleepNative, _SleepDart>('Sleep');

  Pointer<Void> stdoutRead = nullptr;
  Pointer<Void> stdoutWrite = nullptr;
  Pointer<Void> stderrRead = nullptr;
  Pointer<Void> stderrWrite = nullptr;

  final attributes =
      NativeHeap.alloc<_SecurityAttributes>(sizeOf<_SecurityAttributes>());
  attributes.ref
    ..nLength = sizeOf<_SecurityAttributes>()
    ..lpSecurityDescriptor = nullptr
    ..bInheritHandle = 1;

  // Out-parameters for CreatePipe: the handles come back through memory.
  final stdoutReadOut = NativeHeap.alloc<Pointer<Void>>(8);
  final stdoutWriteOut = NativeHeap.alloc<Pointer<Void>>(8);
  final stderrReadOut = NativeHeap.alloc<Pointer<Void>>(8);
  final stderrWriteOut = NativeHeap.alloc<Pointer<Void>>(8);

  try {
    if (createPipe(stdoutReadOut, stdoutWriteOut, attributes, 0) == 0) {
      return const HiddenResult(
        exitCode: -1,
        stdout: '',
        stderr: 'CreatePipe failed',
      );
    }
    if (createPipe(stderrReadOut, stderrWriteOut, attributes, 0) == 0) {
      return const HiddenResult(
        exitCode: -1,
        stdout: '',
        stderr: 'CreatePipe failed',
      );
    }
    stdoutRead = stdoutReadOut.value;
    stdoutWrite = stdoutWriteOut.value;
    stderrRead = stderrReadOut.value;
    stderrWrite = stderrWriteOut.value;

    final commandLine = _utf16Ptr(_quote(executable) + _quoteArgs(arguments));
    final startup = _zeroed<_StartupInfo>(sizeOf<_StartupInfo>());
    final info = _zeroed<_ProcessInformation>(sizeOf<_ProcessInformation>());
    try {
      startup.ref
        ..cb = sizeOf<_StartupInfo>()
        ..dwFlags = _startfUseStdHandles
        ..hStdInput = nullptr
        ..hStdOutput = stdoutWrite
        ..hStdError = stderrWrite
        ..wShowWindow = 0;

      final created = createProcess(
        nullptr,
        commandLine,
        nullptr,
        nullptr,
        1, // inherit the pipe ends
        _createNoWindow,
        nullptr,
        nullptr,
        startup,
        info,
      );
      if (created == 0) {
        return const HiddenResult(
          exitCode: -1,
          stdout: '',
          stderr: 'CreateProcess failed',
        );
      }

      // The child holds the write ends now; dropping ours makes the reads
      // below end at EOF once the child is done.
      closeHandle(stdoutWrite);
      stdoutWrite = nullptr;
      closeHandle(stderrWrite);
      stderrWrite = nullptr;

      final out = <int>[];
      final err = <int>[];
      final buffer = NativeHeap.alloc<Uint8>(_ioBufferSize);
      final counter = NativeHeap.alloc<Uint32>(4);
      try {
        var stdoutDone = false;
        var stderrDone = false;
        var timedOut = false;
        final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

        while (!stdoutDone || !stderrDone) {
          stdoutDone = stdoutDone ||
              _drainPipe(
                readFile,
                peekNamedPipe,
                stdoutRead,
                buffer,
                counter,
                out,
              );
          stderrDone = stderrDone ||
              _drainPipe(
                readFile,
                peekNamedPipe,
                stderrRead,
                buffer,
                counter,
                err,
              );
          if (stdoutDone && stderrDone) break;
          if (DateTime.now().isAfter(deadline)) {
            timedOut = true;
            break;
          }
          sleep(_pollIntervalMs);
        }

        if (timedOut) {
          terminateProcess(info.ref.hProcess, 1);
          waitForSingleObject(info.ref.hProcess, _infinite);
        } else {
          waitForSingleObject(info.ref.hProcess, _infinite);
        }

        final code = NativeHeap.alloc<Uint32>(4);
        try {
          getExitCodeProcess(info.ref.hProcess, code);
          return HiddenResult(
            exitCode: timedOut ? -2 : code.value,
            stdout: utf8.decode(out, allowMalformed: true),
            stderr: utf8.decode(err, allowMalformed: true),
          );
        } finally {
          NativeHeap.free(code);
        }
      } finally {
        NativeHeap.free(buffer);
        NativeHeap.free(counter);
      }
    } finally {
      NativeHeap.free(commandLine);
      NativeHeap.free(startup);
      NativeHeap.free(info);
    }
  } catch (e) {
    return HiddenResult(exitCode: -1, stdout: '', stderr: '$e');
  } finally {
    if (stdoutRead.address != 0) closeHandle(stdoutRead);
    if (stdoutWrite.address != 0) closeHandle(stdoutWrite);
    if (stderrRead.address != 0) closeHandle(stderrRead);
    if (stderrWrite.address != 0) closeHandle(stderrWrite);
    NativeHeap.free(attributes);
    NativeHeap.free(stdoutReadOut);
    NativeHeap.free(stdoutWriteOut);
    NativeHeap.free(stderrReadOut);
    NativeHeap.free(stderrWriteOut);
  }
}

/// Moves whatever is waiting in a pipe into [sink]. Returns true once the
/// pipe is closed for good.
bool _drainPipe(
  _ReadFileDart readFile,
  _PeekNamedPipeDart peekNamedPipe,
  Pointer<Void> handle,
  Pointer<Uint8> buffer,
  Pointer<Uint32> counter,
  List<int> sink,
) {
  counter.value = 0;
  final peeked = peekNamedPipe(
    handle,
    buffer,
    _ioBufferSize,
    nullptr,
    counter,
    nullptr,
  );
  if (peeked == 0) {
    // ERROR_BROKEN_PIPE: the child closed its end and drained the pipe.
    return true;
  }
  final available = counter.value;
  if (available <= 0) return false;

  counter.value = 0;
  final read = readFile(handle, buffer, available, counter, nullptr);
  if (read == 0 || counter.value == 0) return true;
  sink.addAll(buffer.asTypedList(counter.value));
  return false;
}

String _quote(String value) {
  if (value.isEmpty) return '""';
  if (!value.contains(RegExp(r'[\s"]'))) return value;
  return '"${value.replaceAll('"', r'\"')}"';
}

String _quoteArgs(List<String> args) {
  if (args.isEmpty) return '';
  return ' ' + args.map(_quote).join(' ');
}

/// UTF-16LE text with a null terminator, allocated on the native heap.
Pointer<Uint16> _utf16Ptr(String text) {
  final units = text.codeUnits;
  final pointer = NativeHeap.alloc<Uint16>((units.length + 1) * 2);
  final view = pointer.asTypedList(units.length + 1);
  view.setRange(0, units.length, units);
  view[units.length] = 0;
  return pointer;
}

/// A zeroed block of native memory for a fixed-size struct.
Pointer<T> _zeroed<T extends NativeType>(int bytes) {
  final pointer = NativeHeap.alloc<T>(bytes);
  final view = pointer.cast<Uint8>().asTypedList(bytes);
  for (var i = 0; i < bytes; i++) {
    view[i] = 0;
  }
  return pointer;
}
