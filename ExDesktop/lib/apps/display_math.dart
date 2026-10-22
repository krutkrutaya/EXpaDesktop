// Brightness values cross a native boundary that is not always honest: a
// DDC/CI reader that cannot talk to the panel reports 0, and some backends
// report percent instead of a 0..1 fraction. The UI must show the real panel
// (or the last known value), never a lying 0%.

double? normalizeBrightness(double? raw) {
  if (raw == null || !raw.isFinite || raw < 0) return null;
  var value = raw;
  if (value > 1.5) value /= 100;
  if (value <= 0.01) return null;
  return value.clamp(0.0, 1.0);
}