// EXPA's own configuration: everything the desktop environment lets the user
// tune, in one pure-Dart object. The Settings window and the Configs app edit
// the same fields; the shell persists them as key=value lines in prefs.cfg.
//
// Flutter-free on purpose: the clamping and round-trip logic are checked by
// `dart run test/expa_check.dart`.

class DeConfig {
  final int accentIndex;
  final double windowRadius;
  final double wallpaperDim;
  final double dockIconScale;
  final double animationSpeed;
  final bool animationsEnabled;
  final bool snapEnabled;
  final double snapGap;
  final bool notificationsEnabled;
  final bool clockSeconds;
  final double fontScale;
  final int autoLockMinutes;
  final String lockPin;

  const DeConfig({
    this.accentIndex = 0,
    this.windowRadius = 16,
    this.wallpaperDim = 0,
    this.dockIconScale = 1,
    this.animationSpeed = 1,
    this.animationsEnabled = true,
    this.snapEnabled = true,
    this.snapGap = 5,
    this.notificationsEnabled = true,
    this.clockSeconds = false,
    this.fontScale = 1,
    this.autoLockMinutes = 0,
    this.lockPin = '',
  });

  /// Deliberately few, clearly named accents. Every one is readable on the
  /// dark glass; they are ARGB values so the model stays Flutter-free.
  static const List<int> accents = [
    0xFF8AB4F8, // sky
    0xFFF2A9C4, // rose
    0xFFB7E4C7, // mint
    0xFFFFD6A5, // peach
    0xFFCDB4DB, // lavender
    0xFFFFFFFF, // frost
  ];

  static const DeConfig defaults = DeConfig();

  int get accent => accents[accentIndex.clamp(0, accents.length - 1)];

  DeConfig copyWith({
    int? accentIndex,
    double? windowRadius,
    double? wallpaperDim,
    double? dockIconScale,
    double? animationSpeed,
    bool? animationsEnabled,
    bool? snapEnabled,
    double? snapGap,
    bool? notificationsEnabled,
    bool? clockSeconds,
    double? fontScale,
    int? autoLockMinutes,
    String? lockPin,
  }) {
    return DeConfig(
      accentIndex: accentIndex ?? this.accentIndex,
      windowRadius: windowRadius ?? this.windowRadius,
      wallpaperDim: wallpaperDim ?? this.wallpaperDim,
      dockIconScale: dockIconScale ?? this.dockIconScale,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      snapEnabled: snapEnabled ?? this.snapEnabled,
      snapGap: snapGap ?? this.snapGap,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      clockSeconds: clockSeconds ?? this.clockSeconds,
      fontScale: fontScale ?? this.fontScale,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      lockPin: lockPin ?? this.lockPin,
    );
  }

  /// Reads the prefs map, clamping every value into its safe range. A broken
  /// or missing value falls back to its default; the shell never fails to
  /// start because a config line is garbage.
  static DeConfig fromMap(String Function(String key, [String fallback]) read) {
    double number(String key, double fallback) =>
        double.tryParse(read(key, '$fallback')) ?? fallback;
    int integer(String key, int fallback) =>
        int.tryParse(read(key, '$fallback')) ?? fallback;
    final pin = read('security_pin', '').replaceAll(RegExp(r'[^0-9]'), '');
    final lockPin = pin.length > 8 ? pin.substring(0, 8) : pin;

    return DeConfig(
      accentIndex: integer('ui_accent', defaults.accentIndex)
          .clamp(0, accents.length - 1)
          .toInt(),
      windowRadius:
          number('ui_radius', defaults.windowRadius).clamp(8.0, 26.0).toDouble(),
      wallpaperDim:
          number('ui_dim', defaults.wallpaperDim).clamp(0.0, 0.65).toDouble(),
      dockIconScale: number('ui_dock_scale', defaults.dockIconScale)
          .clamp(0.8, 1.4)
          .toDouble(),
      animationSpeed: number('ui_anim_speed', defaults.animationSpeed)
          .clamp(0.5, 1.6)
          .toDouble(),
      animationsEnabled:
          read('ui_animations', '1') != '0',
      snapEnabled: read('wm_snap', '1') != '0',
      snapGap: number('wm_gap', defaults.snapGap).clamp(0.0, 20.0).toDouble(),
      notificationsEnabled: read('notif_enabled', '1') != '0',
      clockSeconds: read('ui_clock_seconds', '0') == '1',
      fontScale:
          number('ui_font_scale', defaults.fontScale).clamp(0.85, 1.2).toDouble(),
      autoLockMinutes:
          integer('security_auto_lock', defaults.autoLockMinutes)
              .clamp(0, 120)
              .toInt(),
      lockPin: lockPin,
    );
  }

  Map<String, String> toMap() => {
        'ui_accent': '$accentIndex',
        'ui_radius': '$windowRadius',
        'ui_dim': '$wallpaperDim',
        'ui_dock_scale': '$dockIconScale',
        'ui_anim_speed': '$animationSpeed',
        'ui_animations': animationsEnabled ? '1' : '0',
        'wm_snap': snapEnabled ? '1' : '0',
        'wm_gap': '$snapGap',
        'notif_enabled': notificationsEnabled ? '1' : '0',
        'ui_clock_seconds': clockSeconds ? '1' : '0',
        'ui_font_scale': '$fontScale',
        'security_auto_lock': '$autoLockMinutes',
        'security_pin': lockPin,
      };

  @override
  bool operator ==(Object other) =>
      other is DeConfig &&
      other.accentIndex == accentIndex &&
      other.windowRadius == windowRadius &&
      other.wallpaperDim == wallpaperDim &&
      other.dockIconScale == dockIconScale &&
      other.animationSpeed == animationSpeed &&
      other.animationsEnabled == animationsEnabled &&
      other.snapEnabled == snapEnabled &&
      other.snapGap == snapGap &&
      other.notificationsEnabled == notificationsEnabled &&
      other.clockSeconds == clockSeconds &&
      other.fontScale == fontScale &&
      other.autoLockMinutes == autoLockMinutes &&
      other.lockPin == lockPin;

  @override
  int get hashCode => Object.hash(
        accentIndex,
        windowRadius,
        wallpaperDim,
        dockIconScale,
        animationSpeed,
        animationsEnabled,
        snapEnabled,
        snapGap,
        notificationsEnabled,
        clockSeconds,
        fontScale,
        autoLockMinutes,
        lockPin,
      );

  @override
  String toString() => 'DeConfig(accent $accentIndex, radius $windowRadius, '
      'dim $wallpaperDim, dock $dockIconScale, speed $animationSpeed, '
      'snap $snapEnabled/$snapGap, notifications $notificationsEnabled, '
      'font $fontScale)';
}