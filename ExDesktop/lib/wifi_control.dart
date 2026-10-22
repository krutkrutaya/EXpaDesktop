// Wi-Fi through the native WLAN API in sysctl.dll.
//
// The localized netsh parsers are gone from the runtime path. What remains is
// the small model the flyout renders and three calls into Rust: scan, join,
// leave. When the DLL is not built (a fresh clone or CI), the list is simply
// empty and the buttons report failure — the shell never crashes over a
// missing backend.

import 'native/sysctl.dart';

/// One visible network.
class WifiNetwork {
  final String ssid;
  final int signal; // 0..100, 0 when the adapter reported nothing
  final bool secure; // needs a password
  final bool known; // Windows already has a profile for it

  /// The profile's auto-join flag, mirrored from the Windows profile XML.
  final bool auto;

  /// Set by the panel: whether Windows currently uses this network.
  bool connected;

  WifiNetwork({
    required this.ssid,
    required this.signal,
    required this.secure,
    required this.known,
    required this.connected,
    required this.auto,
  });
}

abstract final class WifiControl {
  /// A snapshot of every network in range, best-signal first with the
  /// connected one pinned to the top. The native call also kicks a scan, so
  /// opening the flyout shows fresh results rather than the boot-time list.
  static Future<List<WifiNetwork>> networks() async {
    final rows = await SysCtl.wifiNetworksAsync();
    return [
      for (final row in rows)
        WifiNetwork(
          ssid: row.ssid,
          signal: row.signal,
          secure: row.secure,
          known: row.known,
          connected: row.connected,
          auto: row.auto,
        ),
    ];
  }

  /// Joins [net]. A known profile connects by name; a new password network
  /// first gets a standard WPA2PSK profile written by the native side.
  static Future<bool> connect(
    WifiNetwork net, {
    required String? password,
    required bool autoConnect,
  }) async {
    return SysCtl.wifiConnect(
      net.ssid,
      password: password ?? '',
      autoConnect: autoConnect,
      secure: net.secure,
    );
  }

  /// Parameterless version for known networks.
  static Future<bool> connectKnown(WifiNetwork net) =>
      connect(net, password: null, autoConnect: true);

  static Future<void> disconnect() async {
    SysCtl.wifiDisconnect();
  }
}