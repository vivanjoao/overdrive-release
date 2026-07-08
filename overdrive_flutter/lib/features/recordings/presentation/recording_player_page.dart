import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/dimensions.dart';

/// Bundle passed via go_router's `extra`. Defined here (rather than in
/// `recordings_page.dart`) so the player has a single source of truth for
/// its input contract — and so other features (live view, surveillance) can
/// reuse the same player with a different URL/title pair.
class PlayerParams {
  const PlayerParams({required this.url, required this.title});
  final String url;
  final String title;
}

/// Fullscreen video player for recordings.
///
/// Uses `package:video_player` (which on iOS uses AVPlayer, on Android uses
/// ExoPlayer, on web uses HTML5 `<video>`). The head unit serves clips over
/// plain HTTP; on iOS-installed PWA, same-origin playback is fine and
/// cross-origin requires the head unit to send CORS headers (deployment
/// concern, not handled here).
class RecordingPlayerPage extends StatefulWidget {
  const RecordingPlayerPage({super.key, required this.params});

  final PlayerParams params;

  @override
  State<RecordingPlayerPage> createState() => _RecordingPlayerPageState();
}

class _RecordingPlayerPageState extends State<RecordingPlayerPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hadError = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.params.url),
    );

    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialized = true;
      });
      controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hadError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  void _seekRelative(int seconds) {
    final c = _controller;
    if (c == null) return;
    final pos = c.value.position + Duration(seconds: seconds);
    c.seekTo(pos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCenter(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context),
          ),
          if (_initialized && !_hadError)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    if (_hadError) {
      return _ErrorView(
        message: 'Could not play this recording.',
        url: widget.params.url,
        onRetry: () {
          setState(() => _hadError = false);
          _initPlayer();
        },
      );
    }
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final c = _controller!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: AppDimensions.durationShort,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space4, vertical: AppDimensions.space4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  widget.params.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final c = _controller!;
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: AppDimensions.durationShort,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space16, vertical: AppDimensions.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFF5DDBB6),
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: AppDimensions.space4),
              Row(
                children: [
                  Text(
                    _fmt(c.value.position),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded,
                        color: Colors.white),
                    onPressed: () => _seekRelative(-10),
                  ),
                  IconButton.filled(
                    icon: Icon(
                      c.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                    ),
                    onPressed: _togglePlay,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded,
                        color: Colors.white),
                    onPressed: () => _seekRelative(10),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(c.value.duration),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.url,
    required this.onRetry,
  });

  final String message;
  final String url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Colors.white70),
            const SizedBox(height: AppDimensions.space12),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.space8),
            Text(
              url,
              style: const TextStyle(
                color: Colors.white54,
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppDimensions.space24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
