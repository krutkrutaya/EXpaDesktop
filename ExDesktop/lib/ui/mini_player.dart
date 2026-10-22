// The waybar's mini player.
//
// The artwork spins while the track plays and *settles upright* when it
// pauses: the angle comes from [PlayerController]'s spin spring, not from a
// stopped AnimationController, so pausing never leaves the cover crooked.
//
// This widget is the only thing that rebuilds at 60 fps while music plays;
// the shell and the other windows are untouched.

import 'package:flutter/material.dart';

import '../playback/player_controller.dart';
import '../i18n.dart';
import '../track_art.dart';

class MiniPlayer extends StatefulWidget {
  final PlayerController player;
  final VoidCallback onOpen;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.onOpen,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _hovered = false;
  bool _pressed = false;

  PlayerController get _player => widget.player;

  /// The artwork's corner radius. Hover rounds it from a circle to the glass
  /// radius; a press tightens it further, so the button answers the click
  /// while the pointer is still on it.
  double get _artRadius => _pressed ? 7 : (_hovered ? 10 : 19);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: const ValueKey('mini-player'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(_hovered ? 10 : 20),
          ),
          child: AnimatedBuilder(
            animation: _player,
            builder: (context, _) {
              final track = _player.track;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _spinningArt(),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track?.title ?? Loc.t('Nothing playing', 'Ничего играет'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track?.artist ?? Loc.t('Musics', 'Музыка'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _playButton(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _spinningArt() {
    return ValueListenableBuilder<double>(
      valueListenable: _player.angle,
      builder: (context, angle, child) {
        return Transform.rotate(angle: angle, child: child);
      },
      child: AnimatedBuilder(
        animation: _player,
        builder: (context, _) {
          final track = _player.track;
          // The radius is part of this builder, not a side channel: the old
          // version wrote it into a field from a sibling TweenAnimationBuilder
          // that rebuilt a zero-size box, so the artwork never changed.
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 19, end: _artRadius),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, radius, __) {
              return TrackArt(
                cover: track?.coverIn(_player.covers),
                avatar: track?.avatar,
                size: 38,
                borderRadius: BorderRadius.circular(radius),
              );
            },
          );
        },
      ),
    );
  }

  Widget _playButton() {
    return GestureDetector(
      key: const ValueKey('mini-player-toggle'),
      behavior: HitTestBehavior.opaque,
      onTap: _player.toggle,
      child: SizedBox(
        width: 30,
        height: 30,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            _player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(_player.isPlaying),
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}