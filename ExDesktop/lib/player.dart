// player.dart
import 'package:flutter/material.dart';
import 'dart:ui';

class PlayerPanel extends StatefulWidget {
  final bool isPlaying;
  final int selectedTrack;
  final double progress;
  final List<Map<String, String>> tracks;
  final String currentTime;
  final String totalDuration;
  final VoidCallback onTogglePlay;
  final VoidCallback onNextTrack;
  final VoidCallback onPrevTrack;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onSelectTrack;

  const PlayerPanel({
    super.key,
    required this.isPlaying,
    required this.selectedTrack,
    required this.progress,
    required this.tracks,
    required this.currentTime,
    required this.totalDuration,
    required this.onTogglePlay,
    required this.onNextTrack,
    required this.onPrevTrack,
    required this.onSeek,
    required this.onSelectTrack,
  });

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  bool _isTracksHovered = false;
  bool _isSettingsHovered = false;

  String _getAvatar(int index) {
    final avatar = widget.tracks[index]['avatar'];
    if (avatar == null || avatar.isEmpty) {
      return '';
    }
    return avatar;
  }

  String _getTitle(int index) {
    return widget.tracks[index]['title'] ?? '';
  }

  String _getArtist(int index) {
    return widget.tracks[index]['artist'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = _getAvatar(widget.selectedTrack);
    
    return SizedBox(
      width: 600,
      height: 400,
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: ClipRRect(
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
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (avatarPath.isNotEmpty)
                                  Image.asset(
                                    avatarPath,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) => _buildPlaceholder(),
                                  )
                                else
                                  _buildPlaceholder(),
                                BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.3),
                                  ),
                                ),
                                if (avatarPath.isNotEmpty)
                                  Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        avatarPath,
                                        width: 95,
                                        height: 95,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) => Container(),
                                      ),
                                    ),
                                  )
                                else
                                  Center(
                                    child: Icon(
                                      Icons.music_note,
                                      size: 60,
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
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
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: widget.onPrevTrack,
                              icon: const Icon(Icons.skip_previous, color: Colors.white, size: 24),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 35, minHeight: 35),
                            ),
                            IconButton(
                              onPressed: widget.onTogglePlay,
                              icon: Icon(
                                widget.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 30,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            ),
                            IconButton(
                              onPressed: widget.onNextTrack,
                              icon: const Icon(Icons.skip_next, color: Colors.white, size: 24),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 35, minHeight: 35),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: widget.progress.clamp(0.0, 1.0),
                                onChanged: widget.onSeek,
                                activeColor: Colors.white,
                                inactiveColor: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${widget.currentTime} / ${widget.totalDuration}',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                        MouseRegion(
                          onEnter: (event) => setState(() => _isTracksHovered = true),
                          onExit: (event) => setState(() => _isTracksHovered = false),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(_isTracksHovered ? 15 : 25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: _isTracksHovered
                                      ? Colors.white.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(_isTracksHovered ? 15 : 25),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Треки',
                                    style: TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        MouseRegion(
                          onEnter: (event) => setState(() => _isSettingsHovered = true),
                          onExit: (event) => setState(() => _isSettingsHovered = false),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(_isSettingsHovered ? 15 : 25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: _isSettingsHovered
                                      ? Colors.white.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(_isSettingsHovered ? 15 : 25),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Настройки',
                                    style: TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 1,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(5),
              itemCount: widget.tracks.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => widget.onSelectTrack(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.selectedTrack == index
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _getAvatar(index).isNotEmpty
                                  ? Image.asset(
                                      _getAvatar(index),
                                      width: 35,
                                      height: 35,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) => _buildSmallPlaceholder(),
                                    )
                                  : _buildSmallPlaceholder(),
                            ),
                            const SizedBox(width: 8),
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
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.3),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 60,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildSmallPlaceholder() {
    return Container(
      width: 35,
      height: 35,
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