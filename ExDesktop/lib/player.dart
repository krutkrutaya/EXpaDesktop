// The player flyout: the quick controls under the waybar art.
//
// The Tracks pill used to be a dead label and the Settings pill opened
// nothing. Now Tracks opens the Musics window and Settings is gone — the
// window has its own chrome and the shell's settings live in their own app.
//
// Everything here listens to the [PlayerController]; the shell itself no
// longer rebuilds when a track plays.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'liquid_glass/stretch_icon_button.dart';
import 'liquid_glass/wave_slider.dart';
import 'playback/player_controller.dart';
import 'playback/track.dart';
import 'track_art.dart';

class PlayerPanel extends StatefulWidget {
  final PlayerController player;

  /// Opens the Musics app (and closes this flyout).
  final VoidCallback onOpenTracks;

  const PlayerPanel({
    super.key,
    required this.player,
    required this.onOpenTracks,
  });

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  final ScrollController _trackScroll = ScrollController();
  bool _hasAbove = false;
  bool _hasBelow = false;

  PlayerController get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _trackScroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _trackScroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_trackScroll.hasClients) return;
    final position = _trackScroll.position;
    final above = position.pixels > 4;
    final below = position.pixels < position.maxScrollExtent - 4;
    if (above != _hasAbove || below != _hasBelow) {
      setState(() {
        _hasAbove = above;
        _hasBelow = below;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _player,
      builder: (context, _) {
        return SizedBox(
          width: 600,
          height: 400,
          child: Row(
            children: [
              Expanded(child: _leftPanel()),
              const SizedBox(width: 5),
              Expanded(child: _trackList()),
            ],
          ),
        );
      },
    );
  }

  Widget _leftPanel() {
    final track = _player.track;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _banner(track),
            const SizedBox(height: 7),
            Text(
              track?.title ?? 'Nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              track?.artist ?? 'Pick a track',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const Spacer(),
            _transport(),
            const SizedBox(height: 10),
            _seek(),
            const SizedBox(height: 8),
            _GlassPillButton(
              key: const ValueKey('player-tracks'),
              label: 'Tracks',
              onTap: widget.onOpenTracks,
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(Track? track) {
    return Container(
      width: double.infinity,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: TrackArt(
              cover: track?.coverIn(_player.covers),
              avatar: track?.avatar,
              size: 150,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          // A soft dark veil keeps the title readable over bright covers.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transport() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StretchIconButton(
          active: _player.looping,
          size: 42,
          onTap: () => _player.setLooping(!_player.looping),
          child: Icon(
            Icons.repeat_rounded,
            size: 22,
            color: _player.looping ? Colors.orange : Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        StretchIconButton(
          key: const ValueKey('player-prev'),
          size: 46,
          onTap: _player.previous,
          child: const Icon(Icons.skip_previous_rounded,
              size: 28, color: Colors.white),
        ),
        const SizedBox(width: 6),
        StretchIconButton(
          key: const ValueKey('player-play'),
          size: 54,
          onTap: _player.toggle,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Icon(
              _player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey<bool>(_player.isPlaying),
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
        const SizedBox(width: 6),
        StretchIconButton(
          key: const ValueKey('player-next'),
          size: 46,
          onTap: _player.next,
          child: const Icon(Icons.skip_next_rounded,
              size: 28, color: Colors.white),
        ),
        const SizedBox(width: 4),
        StretchIconButton(
          active: _player.shuffle,
          size: 42,
          onTap: () => _player.setShuffle(!_player.shuffle),
          child: Icon(
            Icons.shuffle_rounded,
            size: 20,
            color: _player.shuffle ? Colors.orange : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _seek() {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: _player.progress,
            builder: (context, value, _) => WaveSlider(
              key: const ValueKey('player-seek'),
              value: value,
              onChanged: _player.seekFraction,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<String>(
          valueListenable: _player.time,
          builder: (context, value, _) => Text(
            '$value / ${_player.totalDuration}',
            style: const TextStyle(color: Colors.white, fontSize: 9.5),
          ),
        ),
      ],
    );
  }

  Widget _trackList() {
    final tracks = _player.tracks;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        const fadePx = 44.0;
        final top = _hasAbove ? (fadePx / bounds.height).clamp(0.0, 0.5) : 0.0;
        final bottom =
            _hasBelow ? (fadePx / bounds.height).clamp(0.0, 0.5) : 0.0;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _hasAbove ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            _hasBelow ? Colors.transparent : Colors.white,
          ],
          stops: [0.0, top, 1.0 - bottom, 1.0],
        ).createShader(bounds);
      },
      child: ListView.builder(
        controller: _trackScroll,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(5),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          final selected = _player.index == index;
          return _TrackCard(
            key: ValueKey('player-track-$index'),
            track: track,
            cover: track.coverIn(_player.covers),
            selected: selected,
            onTap: () => _player.select(index, autoplay: true),
          );
        },
      ),
    );
  }
}

class _TrackCard extends StatefulWidget {
  final Track track;
  final Uint8List? cover;
  final bool selected;
  final VoidCallback onTap;

  const _TrackCard({
    super.key,
    required this.track,
    required this.cover,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
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
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            // No per-card BackdropFilter: ten blurred cards over a blurred
            // panel was the most expensive thing the old player did.
            color: widget.selected
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: _hovered ? 0.45 : 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? Colors.white.withValues(alpha: 0.30)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              TrackArt(
                cover: widget.cover,
                avatar: widget.track.avatar,
                size: 38,
                borderRadius: BorderRadius.circular(8),
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
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    Text(
                      widget.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                widget.track.duration,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The «Tracks» pill: a real button now.
class _GlassPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _GlassPillButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<_GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<_GlassPillButton> {
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.25 : 0.10),
            borderRadius: BorderRadius.circular(_hovered ? 15 : 25),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }
}