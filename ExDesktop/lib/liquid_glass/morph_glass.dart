// Renders a panel as liquid glass following a [MorphFrame]: the glass body
// grows from the button capsule to the full panel, the content starts big and
// blurred deep inside the glass and rises to the surface as it opens.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'menu_morph.dart';

class MorphGlass extends StatelessWidget {
  final MorphFrame frame;

  /// The panel's resting content size.
  final double restWidth;
  final double restHeight;

  /// Darkening laid over the whole glass rect. Panels that style their
  /// halves themselves (the player) pass a transparent tint.
  final Color tint;

  /// The panel content, laid out at rest size.
  final Widget child;

  /// Whether the content may be interacted with (false while animating).
  final bool interactive;

  const MorphGlass({
    super.key,
    required this.frame,
    required this.restWidth,
    required this.restHeight,
    required this.child,
    this.tint = const Color(0x99000000),
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = frame.bodyRadius.clamp(0.0, double.infinity);
    final softenBlur = 5.0 * (1.0 - 0.7 * frame.soften.clamp(0.0, 1.0));
    final w = frame.body[2].clamp(0.1, 100000.0);
    final h = frame.body[3].clamp(0.1, 100000.0);

    return Positioned(
      left: frame.body[0],
      top: frame.body[1],
      width: w,
      height: h,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Opacity(
          opacity: frame.glassOpacity.clamp(0.0, 1.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: softenBlur,
                sigmaY: softenBlur,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: restWidth,
                    maxWidth: restWidth,
                    minHeight: restHeight,
                    maxHeight: restHeight,
                    child: _lens(
                      ui.ImageFilter.blur(
                        sigmaX: frame.lens.clamp(0.0, 1.0) * 2.0,
                        sigmaY: frame.lens.clamp(0.0, 1.0) * 2.0,
                      ),
                      Transform.scale(
                        scale: frame.contentScale,
                        child: Opacity(
                          opacity: frame.contentOpacity.clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lens(ui.ImageFilter filter, Widget content) {
    if (frame.lens <= 0.01) return content;
    return ImageFiltered(imageFilter: filter, child: content);
  }
}
