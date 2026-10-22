// The player flyout: the quick controls under the waybar art.
//
// The Tracks pill used to be a dead label and the Settings pill opened
// nothing. Now Tracks opens the Musics window and Settings is gone — the
// window has its own chrome and the shell's settings live in their own app.
//
// Everything here listens to the [PlayerController]; the shell itself no
// longer rebuilds when a track plays.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'i18n.dart';
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
        // 9 px top/bottom instead of 10: the schedule of fixed heights in
        // this column was 1 px short, which spilled the SeekRow over the
        // panel's bottom edge.
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(
          children: [
            _banner(track),
            const SizedBox(height: 7),
            Text(
              track?.title ?? Loc.t('Nothing playing', 'Ничего играет'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              track?.artist ?? Loc.t('Pick a track', 'Выбери трек'),
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
              label: Loc.t('Tracks', 'Треки'),
              onTap: widget.onOpenTracks,
            ),
          ],
        ),
      ),
    );
  }

  /// The now-playing banner: blurred cover behind, square rounded avatar in
  /// the middle. The avatar grows a little while the mouse hovers it.
  Widget _banner(Track? track) {
    return SizedBox(
      width: double.infinity,
      height: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: the cover stretched over the whole banner and blurred,
          // so the text below stays readable and the banner looks deeper.
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _BannerBackdrop(
              cover: track?.coverIn(_player.covers),
              avatar: track?.avatar,
            ),
          ),
          // A soft dark veil for contrast over bright covers.
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
          // The avatar itself: square with 15 px rounding, no blur, and it
          // swells slightly on hover.
          Center(
            child: _BannerAvatar(
              cover: track?.coverIn(_player.covers),
              avatar: track?.avatar,
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
/// The blurred background of the banner: the cover stretched edge to edge,
/// then a real gaussian blur (sigma 24). Without art it falls back to the
/// glass-style gradient.
class _BannerBackdrop extends StatelessWidget {
  final Uint8List? cover;

  /// The bundled asset path from the track table, if any.
  final String? avatar;

  const _BannerBackdrop({required this.cover, required this.avatar});

  @override
  Widget build(BuildContext context) {
    Widget? art;
    final bytes = cover;
    if (bytes != null && bytes.isNotEmpty) {
      art = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) => const SizedBox.shrink(),
      );
    } else if (avatar != null && avatar!.isNotEmpty) {
      art = Image.asset(
        avatar!,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => const SizedBox.shrink(),
      );
    }
    // Blur the artwork itself. A BackdropFilter here looked at the layer
    // behind the banner instead of the sibling image, so the cover stayed
    // sharp; ImageFiltered always blurs exactly the pixels it wraps.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (art != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: art,
          ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x29FFFFFF),
                  Color(0x4D000000),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The square avatar over the banner: rounded 15, no blur, scales up a bit
/// when the mouse hovers it.
class _BannerAvatar extends StatefulWidget {
  final Uint8List? cover;
  final String? avatar;

  const _BannerAvatar({required this.cover, required this.avatar});

  @override
  State<_BannerAvatar> createState() => _BannerAvatarState();
}

class _BannerAvatarState extends State<_BannerAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        scale: _hovered ? 1.07 : 1.0,
        child: Container(
          width: 122,
          height: 122,
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TrackArt(
            cover: widget.cover,
            avatar: widget.avatar,
            size: 122,
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}
