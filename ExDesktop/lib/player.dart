// player.dart
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui';

import 'liquid_glass/wave_slider.dart';
import 'liquid_glass/stretch_icon_button.dart';

class PlayerPanel extends StatefulWidget {
  final bool isPlaying;
  final int selectedTrack;
  final double progress;
  final List<Map<String, String>> tracks;

  /// Cover art parsed out of the ID3 tags, keyed by file name.
  final Map<String, Uint8List> covers;
  final String currentTime;
  final String totalDuration;
  final VoidCallback onTogglePlay;
  final VoidCallback onNextTrack;
  final VoidCallback onPrevTrack;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onSelectTrack;

  // Loop the current track forever when on.
  final bool isLooping;
  final VoidCallback onToggleLoop;
  // The three-dot menu options.
  final bool isRepeatPlaylist;
  final ValueChanged<bool> onToggleRepeatPlaylist;
  final bool isShuffle;
  final ValueChanged<bool> onToggleShuffle;

  const PlayerPanel({
    super.key,
    required this.isPlaying,
    required this.selectedTrack,
    required this.progress,
    required this.tracks,
    this.covers = const {},
    required this.currentTime,
    required this.totalDuration,
    required this.onTogglePlay,
    required this.onNextTrack,
    required this.onPrevTrack,
    required this.onSeek,
    required this.onSelectTrack,
    required this.isLooping,
    required this.onToggleLoop,
    required this.isRepeatPlaylist,
    required this.onToggleRepeatPlaylist,
    required this.isShuffle,
    required this.onToggleShuffle,
  });

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  bool _isBannerHovered = false;

  final ScrollController _trackScroll = ScrollController();
  bool _hasAbove = false;
  bool _hasBelow = false;

  final GlobalKey _moreMenuKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _trackScroll.addListener(_onTrackScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTrackScroll());
  }

  @override
  void dispose() {
    _trackScroll.dispose();
    super.dispose();
  }

  void _onTrackScroll() {
    if (!mounted || !_trackScroll.hasClients) return;
    final pos = _trackScroll.position;
    final above = pos.pixels > 4;
    final below = pos.pixels < pos.maxScrollExtent - 4;
    if (above != _hasAbove || below != _hasBelow) {
      setState(() {
        _hasAbove = above;
        _hasBelow = below;
      });
    }
  }

  void _showMoreMenu() {
    final ctx = _moreMenuKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      color: const Color(0xF0141414),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      // Opens above the button so it stays inside the window.
      position: RelativeRect.fromLTRB(
        topLeft.dx - 150,
        topLeft.dy - 104,
        topLeft.dx + box.size.width,
        topLeft.dy,
      ),
      items: [
        _checkItem('repeat', 'Repeat playlist', widget.isRepeatPlaylist),
        _checkItem('shuffle', 'Shuffle order', widget.isShuffle),
      ],
    ).then((v) {
      if (!mounted) return;
      if (v == 'repeat') widget.onToggleRepeatPlaylist(!widget.isRepeatPlaylist);
      if (v == 'shuffle') widget.onToggleShuffle(!widget.isShuffle);
    });
  }

  PopupMenuItem<String> _checkItem(String value, String label, bool checked) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: checked
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.orange)
                : null,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _getAvatar(int index) {
    final avatar = widget.tracks[index]['avatar'];
    if (avatar == null || avatar.isEmpty) {
      return '';
    }
    return avatar;
  }

  /// The cover for a track: the picture inside its ID3 tag first, then the
  /// bundled image from the track table, then a placeholder.
  Uint8List? _embeddedCover(int index) {
    final file = widget.tracks[index]['file'] ?? '';
    return widget.covers[file];
  }

  bool _hasArt(int index) =>
      _embeddedCover(index) != null || _getAvatar(index).isNotEmpty;

  Widget _coverImage(
    int index, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    final bytes = _embeddedCover(index);
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        width == null ? _buildPlaceholder() : _buildSmallPlaceholder();
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: fallback,
      );
    }
    return Image.asset(
      _getAvatar(index),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: fallback,
    );
  }

  String _getTitle(int index) {
    return widget.tracks[index]['title'] ?? '';
  }

  String _getArtist(int index) {
    return widget.tracks[index]['artist'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 600,
      height: 400,
      child: Row(
        children: [
          Expanded(flex: 1, child: _buildLeftPanel()),
          const SizedBox(width: 5),
          Expanded(flex: 1, child: _buildTrackList()),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    final hasArt = _hasArt(widget.selectedTrack);

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                // Banner: the cover art itself grows on hover, the banner stays.
                MouseRegion(
                  onEnter: (event) => setState(() => _isBannerHovered = true),
                  onExit: (event) => setState(() => _isBannerHovered = false),
                  child: Container(
                    width: double.infinity,
                    height: 148,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasArt)
                            _coverImage(widget.selectedTrack)
                          else
                            _buildPlaceholder(),
                          BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.3),
                            ),
                          ),
                          if (hasArt)
                            Center(
                              child: AnimatedScale(
                                scale: _isBannerHovered ? 1.09 : 1.0,
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutBack,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _coverImage(
                                    widget.selectedTrack,
                                    width: 95,
                                    height: 95,
                                  ),
                                ),
                              ),
                            )
                          else
                            const Center(
                              child: Icon(
                                Icons.music_note,
                                size: 60,
                                color: Color(0x80FFFFFF),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _getTitle(widget.selectedTrack),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _getArtist(widget.selectedTrack),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const Spacer(),
                _buildTransportRow(),
                const SizedBox(height: 12),
                _buildSeekRow(),
                const SizedBox(height: 8),
                const _GlassPillButton(label: 'Tracks'),
                const SizedBox(height: 4),
                const _GlassPillButton(label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransportRow() {
    // Sized so the row (260 px) always fits the 277 px the left panel's
    // interior offers — no right overflow, whatever the window width.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Loop the current track.
        StretchIconButton(
          active: widget.isLooping,
          size: 44,
          onTap: widget.onToggleLoop,
          child: Icon(
            Icons.repeat_rounded,
            size: 24,
            color: widget.isLooping ? Colors.orange : Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        StretchIconButton(
          size: 48,
          onTap: widget.onPrevTrack,
          child: const Icon(
            Icons.skip_previous_rounded,
            size: 30,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        StretchIconButton(
          size: 56,
          onTap: widget.onTogglePlay,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: anim, child: child),
            ),
            child: Icon(
              widget.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              key: ValueKey<bool>(widget.isPlaying),
              color: Colors.white,
              size: 42,
            ),
          ),
        ),
        const SizedBox(width: 6),
        StretchIconButton(
          size: 48,
          onTap: widget.onNextTrack,
          child: const Icon(
            Icons.skip_next_rounded,
            size: 30,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        // Three dots: playlist options.
        StretchIconButton(
          key: _moreMenuKey,
          size: 44,
          onTap: _showMoreMenu,
          child: const Icon(
            Icons.more_vert_rounded,
            size: 24,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSeekRow() {
    return Row(
      children: [
        Expanded(
          child: WaveSlider(
            value: widget.progress.clamp(0.0, 1.0),
            onChanged: widget.onSeek,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${widget.currentTime} / ${widget.totalDuration}',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildTrackList() {
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
        itemCount: widget.tracks.length,
        itemBuilder: (context, index) {
          final selected = widget.selectedTrack == index;
          return GestureDetector(
            onTap: () => widget.onSelectTrack(index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _hasArt(index)
                            ? _coverImage(index, width: 38, height: 38)
                            : _buildSmallPlaceholder(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getTitle(index),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _getArtist(index),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        widget.tracks[index]['duration'] ?? '2:00',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.3),
      child: const Center(
        child: Icon(
          Icons.music_note,
          size: 60,
          color: Color(0x80FFFFFF),
        ),
      ),
    );
  }

  Widget _buildSmallPlaceholder() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.music_note,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

/// The «Tracks» / «Settings» pills: on hover the color deepens and the
/// rounding morphs from 25 to 15.
class _GlassPillButton extends StatefulWidget {
  final String label;

  const _GlassPillButton({required this.label});

  @override
  State<_GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<_GlassPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => setState(() => _hovered = true),
      onExit: (event) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: _hovered
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(_hovered ? 15 : 25),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
