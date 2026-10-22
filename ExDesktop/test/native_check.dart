// The pure parsers behind the Rust backend. The FFI calls themselves need
// Windows and the DLL; the JSON shapes are checked here, on CI, without
// either. If a field is renamed in Rust this suite fails immediately.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'package:exp_desktop/native/sysctl.dart';

import 'mock_harness.dart';

void runNativeChecks() {
  _audio();
  _wifi();
  _display();
  _timezones();
}

void _audio() {
  section('native audio json');
  final rows = parseAudioSessionsJson(
    '[{"pid":42,"exe":"chrome","volume":0.5,"muted":false},'
    '{"pid":7,"exe":"spotify","volume":0.9,"muted":true},'
    '{"pid":9,"exe":"edge","volume":2.0,"muted":false}]',
  );
  checkEquals('three rows', rows.length, 3);
  check('sorted by exe', rows[0].exe == 'chrome' && rows[2].exe == 'spotify');
  checkEquals('pid survives', rows.first.pid, 42);
  checkClose('volume survives', rows.first.volume, 0.5, 0.0001);
  check('mute survives', rows[2].muted);
  checkClose('volume is clamped', rows[1].volume, 1.0, 0.0001);

  check('junk is empty', parseAudioSessionsJson('nope').isEmpty);
  check('an object is not a list', parseAudioSessionsJson('{}').isEmpty);
  check('a row without a pid is skipped',
      parseAudioSessionsJson('[{"exe":"x"}]').isEmpty);
  check('missing fields are safe',
      parseAudioSessionsJson('[{"pid":1}]').single.exe.isEmpty);
}

void _wifi() {
  section('native wifi json');
  final rows = parseWifiJson(
    '[{"ssid":"Home","signal":82,"secure":true,"known":true,'
    '"connected":false,"auto":true},'
    '{"ssid":"Cafe","signal":31,"secure":false,"known":false,'
    '"connected":false,"auto":false},'
    '{"ssid":"Phone","signal":64,"secure":true,"known":true,'
    '"connected":true,"auto":true}]',
  );
  checkEquals('three networks', rows.length, 3);
  checkEquals('the connected one is pinned first', rows.first.ssid, 'Phone');
  check('the rest is signal-ordered', rows[1].ssid == 'Home' && rows[2].ssid == 'Cafe');
  check('the auto flag survives', rows[1].auto);
  check('a locked network is marked', rows[1].secure);
  check('an open network is marked', !rows[2].secure);
  check('the signal is in range', rows.every((row) => row.signal <= 100));

  final clamped = parseWifiJson(
    '[{"ssid":"Loud","signal":999,"secure":false,"auto":false}]',
  );
  checkEquals('signal is clamped', clamped.single.signal, 100);
  check('a missing auto is false', !clamped.single.auto);
  check('a blank ssid is skipped',
      parseWifiJson('[{"ssid":"  ","signal":10}]').isEmpty);
  check('junk is empty', parseWifiJson('nope').isEmpty);
}

void _display() {
  section('native display json');
  final state = parseDisplayStateJson(
    '{"current":{"width":2560,"height":1440,"hz":144,'
    '"orientation":0,"bits":32},'
    '"resolutions":[[2560,1440],[1920,1080]],'
    '"refresh":[144,60]}',
  );
  check('a current mode is parsed', state.current != null);
  checkEquals('width', state.current!.width, 2560);
  checkEquals('height', state.current!.height, 1440);
  checkEquals('hz', state.current!.hz, 144);
  checkEquals('two resolutions', state.resolutions.length, 2);
  check('resolutions are sorted',
      state.resolutions.first.width == 1920 &&
          state.resolutions.last.width == 2560);
  check('refresh rates are sorted',
      state.refreshRates.first == 60 && state.refreshRates.last == 144);

  final empty = parseDisplayStateJson('nope');
  check('junk gives the empty state', empty.current == null);
  check('the empty state still offers 60 Hz',
      empty.refreshRates.length == 1 && empty.refreshRates.single == 60);

  final missing = parseDisplayStateJson(
    '{"current":{"width":1920,"height":1080,"hz":60}}',
  );
  checkEquals('a missing orientation is 0', missing.current!.orientation, 0);
  checkEquals('a missing refresh list falls back to 60',
      missing.refreshRates.single, 60);
  checkEquals('a missing bit depth is 32', missing.current!.bits, 32);
}

void _timezones() {
  section('native timezone json');
  final rows = parseTimezonesJson(
    '[{"id":"Pacific Standard Time","name":"Pacific Standard Time",'
    '"offset":-480},'
    '{"id":"Russian Standard Time","name":"Moscow Standard Time",'
    '"offset":180}]',
  );
  checkEquals('two zones', rows.length, 2);
  checkEquals('sorted by name', rows.first.id, 'Russian Standard Time');
  checkEquals('the Moscow offset', rows.first.offsetMinutes, 180);
  check('a zone without an id is skipped',
      parseTimezonesJson('[{"name":"Nowhere","offset":0}]').isEmpty);
  check('junk is empty', parseTimezonesJson('nope').isEmpty);
  check('a missing offset is zero',
      parseTimezonesJson('[{"id":"X"}]').single.offsetMinutes == 0);
}

void main() {
  runNativeChecks();
  finish('native');
}