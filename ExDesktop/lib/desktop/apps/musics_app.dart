// The Musics app: the player as a real window.
//
// The Tracks pill in the player flyout used to be a dead label. Now it opens
// this window: every track and artist as a list, a transport at the bottom,
// and a seek bar that shows the real timecode. The cover does not spin here —
// spinning belongs to the waybar art — it breathes with the beat instead.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../playback/beat.dart';
import '../../playback/player_controller.dart';
import '../../playback/track.dart';
import '../../ui/glass.dart';
import '../../liquid_glass/wave_slider.dart';
import '../../track_art.dart';

class MusicsApp extends StatelessWidget {
  final PlayerController player;

  /// Opens the in-app file picker to add a track to the library.
  final VoidCallback? onAddTrack;

  /// A short "Added: …" line that fades away on its own.
  final ValueListenable<String?>? notice;

  const MusicsApp({
    super.key,
    required this.player,
    this.onAddTrack,
    this.notice,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final track = player.track;
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 236,
                      child: Column(
                        children: [
                          _PulseCover(
                            player: player,
                            playing: player.isPlaying,
                            size: 196,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            track?.title ?? 'Nothing playing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track?.artist ?? 'Pick a track',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Caption(
                            player.isPlaying
                                ? 'Playing · ${player.totalDuration}'
                                : 'Paused',
                          ),
                          const Spacer(),
                          _Transport(player: player),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Tracks',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Caption('${player.tracks.length}'),
                              const Spacer(),
                              PillButton(
                                key: const ValueKey('musics-add'),
                                label: 'Add track',
                                icon: Icons.library_add_outlined,
                                onTap: onAddTrack,
                              ),
                            ],
                          ),
                          if (notice != null)
                            ValueListenableBuilder<String?>(
                              valueListenable: notice!,
                              builder: (context, value, _) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, -0.2),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: value == null
                                    ? const SizedBox(
                                        key: ValueKey('musics-no-notice'),
                                        height: 0,
                                      )
                                    : Padding(
                                        key: const ValueKey('musics-notice'),
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Caption(value),
                                      ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Expanded(child: _TrackList(player: player)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _SeekRow(player: player),
            ],
          ),
        );
      },
    );
  }
}

/// The cover that breathes on the beat.
class _PulseCover extends StatefulWidget {
  final PlayerController player;
  final bool playing;
  final double size;

  const _PulseCover({
    required this.player,
    required this.playing,
    required this.size,
  });

  @override
  State<_PulseCover> createState() => _PulseCoverState();
}

class _PulseCoverState extends State<_PulseCover>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _scale = 1;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant _PulseCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_ticker.isActive) {
      _elapsed = 0;
      _ticker.start();
    } else if (!widget.playing && _ticker.isActive) {
      _ticker.stop();
      setState(() => _scale = 1);
    }
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed.inMicroseconds / 1e6;
    setState(() {
      _scale = BeatPulse.scaleAt(_elapsed, playing: widget.playing);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.player.track;
    return SizedBox(
      width: widget.size + 18,
      height: widget.size + 18,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // A soft glow that breathes with the cover.
            Transform.scale(
              scale: _scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFA59A)
                          .withValues(alpha: 0.16 * (_scale - 1) * 12),
                      blurRadius: 42,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            Transform.scale(
              key: const ValueKey('musics-cover'),
              scale: _scale,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: TrackArt(
                  key: ValueKey<String>(track?.file ?? 'none'),
                  cover: track?.coverIn(widget.player.covers),
                  avatar: track?.avatar,
                  size: widget.size,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  final PlayerController player;

  const _TrackList({required this.player});

  @override
  Widget build(BuildContext context) {
    final tracks = player.tracks;
    if (tracks.isEmpty) {
      return const Center(child: Caption('No tracks in assets/music yet'));
    }
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _TrackRow(
            key: ValueKey('musics-track-$index'),
            index: index,
            track: track,
            cover: track.coverIn(player.covers),
            selected: index == player.index,
            playing: index == player.index && player.isPlaying,
            onTap: () => player.select(index, autoplay: true),
          );
        },
      ),
    );
  }
}

class _TrackRow extends StatefulWidget {
  final int index;
  final Track track;
  final Uint8List? cover;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;

  const _TrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.cover,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: widget.selected ? 0.14 : (_hovered ? 0.08 : 0.03),
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: widget.selected ? 0.22 : 0.05,
              ),
            ),
          ),
          child: Row(
            children: [
              // The artwork was missing from this list entirely; the big cover
              // on the left had it, the rows did not.
              AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: _hovered ? 1.05 : 1.0,
                child: TrackArt(
                  cover: widget.cover,
                  avatar: widget.track.avatar,
                  size: 36,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected ? Colors.white : Colors.white70,
                        fontSize: 12.5,
                        fontWeight:
                            widget.selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    Text(
                      widget.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: widget.playing
                      ? const _Equalizer()
                      : Text(
                          widget.track.duration.isEmpty
                              ? '${widget.index + 1}'
                              : widget.track.duration,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three little bars: the one animation that says "this is playing".
class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) {
    _elapsed = elapsed;
    setState(() {});
  });
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _elapsed.inMilliseconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 3,
            height: 5 + 9 * (0.5 + 0.5 * _wave(t, i)),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA59A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }

  double _wave(int milliseconds, int index) {
    final speed = 3.0 + index * 0.7;
    return (milliseconds / 1000 * speed + index * 1.7).remainder(1.0) * 2 - 1;
  }
}

class _Transport extends StatelessWidget {
  final PlayerController player;

  const _Transport({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        HoverIcon(
          key: const ValueKey('musics-loop'),
          icon: Icons.repeat_rounded,
          tooltip: 'Loop this track',
          active: player.looping,
          activeColor: const Color(0xFFFFA59A),
          onTap: () => player.setLooping(!player.looping),
        ),
        const SizedBox(width: 2),
        HoverIcon(
          key: const ValueKey('musics-prev'),
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous',
          size: 42,
          iconSize: 26,
          onTap: player.previous,
        ),
        const SizedBox(width: 6),
        _PlayButton(player: player),
        const SizedBox(width: 6),
        HoverIcon(
          key: const ValueKey('musics-next'),
          icon: Icons.skip_next_rounded,
          tooltip: 'Next',
          size: 42,
          iconSize: 26,
          onTap: player.next,
        ),
        const SizedBox(width: 2),
        HoverIcon(
          key: const ValueKey('musics-shuffle'),
          icon: Icons.shuffle_rounded,
          tooltip: 'Shuffle',
          active: player.shuffle,
          activeColor: const Color(0xFFFFA59A),
          onTap: () => player.setShuffle(!player.shuffle),
        ),
      ],
    );
  }
}

class _PlayButton extends StatefulWidget {
  final PlayerController player;

  const _PlayButton({required this.player});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: const ValueKey('musics-play'),
        onTap: widget.player.toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.96 : 0.88),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              widget.player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              key: ValueKey<bool>(widget.player.isPlaying),
              color: Colors.black,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekRow extends StatelessWidget {
  final PlayerController player;

  const _SeekRow({required this.player});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: ValueListenableBuilder<String>(
            valueListenable: player.time,
            builder: (context, value, _) => Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 30,
            child: ValueListenableBuilder<double>(
              valueListenable: player.progress,
              builder: (context, value, _) => WaveSlider(
                key: const ValueKey('musics-seek'),
                value: value,
                onChanged: player.seekFraction,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            player.totalDuration,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ],
    );
  }
}