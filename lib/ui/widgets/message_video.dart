import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app.dart';
import '../../l10n/l10n.dart';
import '../../tdlib/td_client.dart';
import '../../telegram/telegram_service.dart';
import 'message_photo.dart';

/// Animations up to this size are downloaded and played automatically.
const _autoDownloadBytes = 10 * 1024 * 1024;

String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

String formatMegabytes(AppLocalizations l, int bytes) =>
    l.megabytes((bytes / (1024 * 1024)).toStringAsFixed(1));

/// Cover image of a video: its thumbnail, or the blurred minithumbnail.
class VideoCover extends StatelessWidget {
  const VideoCover({super.key, required this.media, this.fit = BoxFit.cover});

  /// A TDLib `video`, `animation` or `videoNote` object.
  final TdObject media;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final thumb = media['thumbnail'] as TdObject?;
    final format = (thumb?['format'] as TdObject?)?['@type'];
    final isImage =
        format == 'thumbnailFormatJpeg' ||
        format == 'thumbnailFormatPng' ||
        format == 'thumbnailFormatWebp';
    final path = isImage ? tg.localPath(thumb!['file'] as TdObject) : null;
    if (path != null) {
      return Image.file(File(path), fit: fit, gaplessPlayback: true);
    }
    final mini = media['minithumbnail'] as TdObject?;
    if (mini != null) {
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Image.memory(
          minithumbnailBytes(mini['data'] as String),
          fit: fit,
          gaplessPlayback: true,
        ),
      );
    }
    return const ColoredBox(color: Color(0xFF222222));
  }
}

/// Video or GIF in a message. Videos show a play button and open
/// [VideoPlayerPage]; small GIFs download and loop silently in place.
class MessageVideo extends StatelessWidget {
  const MessageVideo({
    super.key,
    required this.media,
    required this.size,
    required this.isAnimation,
    this.uploading = false,
  });

  final TdObject media;
  final Size size;
  final bool isAnimation;
  final bool uploading;

  TdObject get _file =>
      (isAnimation ? media['animation'] : media['video']) as TdObject;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final l = context.l10n;
    final file = tg.current(_file);
    final path = tg.downloadedPath(file);
    final bytes = file['size'] as int? ?? 0;
    if (isAnimation && path == null && bytes <= _autoDownloadBytes) {
      tg.download(file);
    }

    final Widget center;
    if (uploading) {
      center = const MediaSpinner();
    } else if (isAnimation && path != null) {
      center = const SizedBox.shrink();
    } else if (path == null && (isAnimation || tg.isDownloading(file))) {
      center = _ProgressButton(progress: tg.downloadProgress(file));
    } else {
      center = const _RoundButton(icon: CupertinoIcons.play_fill);
    }

    final label = isAnimation
        ? l.gif
        : (path == null && bytes > 0
              ? '${formatDuration(media['duration'] as int? ?? 0)}, '
                    '${formatMegabytes(l, bytes)}'
              : formatDuration(media['duration'] as int? ?? 0));

    return GestureDetector(
      onTap: () => openFullscreen(
        context,
        (_) => VideoPlayerPage(
          file: _file,
          cover: VideoCover(media: media),
        ),
      ),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isAnimation && path != null)
              LoopingVideo(path: path)
            else
              VideoCover(media: media),
            Center(child: center),
            Positioned(left: 6, top: 6, child: _Badge(label)),
          ],
        ),
      ),
    );
  }
}

/// Round video message ("video note").
class MessageVideoNote extends StatelessWidget {
  const MessageVideoNote({super.key, required this.note, this.size = 220});

  final TdObject note;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    final file = tg.current(note['video'] as TdObject);
    final path = tg.downloadedPath(file);
    if (path == null && (file['size'] as int? ?? 0) <= _autoDownloadBytes) {
      tg.download(file);
    }
    return GestureDetector(
      onTap: () => openFullscreen(
        context,
        (_) => VideoPlayerPage(
          file: file,
          cover: VideoCover(media: note),
        ),
      ),
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (path != null)
                LoopingVideo(path: path)
              else
                VideoCover(media: note),
              if (path == null)
                Center(
                  child: _ProgressButton(progress: tg.downloadProgress(file)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: _Badge(formatDuration(note['duration'] as int? ?? 0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Silent looping playback, used for GIFs and video notes in the chat.
class LoopingVideo extends StatefulWidget {
  const LoopingVideo({super.key, required this.path});

  final String path;

  @override
  State<LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<LoopingVideo> {
  late final _player = Player();
  late final _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player
      ..setVolume(0)
      ..setPlaylistMode(PlaylistMode.single)
      ..open(Media(Uri.file(widget.path).toString()));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Video(
    controller: _controller,
    controls: NoVideoControls,
    fit: BoxFit.cover,
    fill: const Color(0x00000000),
  );
}

/// Full-screen player. The file is downloaded first if needed.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.file, required this.cover});

  final TdObject file;
  final Widget cover;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  Player? _player;
  VideoController? _controller;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  TelegramService? _tg;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tg ??= AppScope.of(context).tg..download(widget.file, priority: 32);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _player?.dispose();
    // Stop a large download nobody is waiting for any more.
    _tg?.cancelDownload(widget.file);
    super.dispose();
  }

  void _start(String path) {
    if (_player != null) return;
    final player = Player();
    _player = player;
    _controller = VideoController(player);
    player.open(Media(Uri.file(path).toString()));
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_player?.state.playing ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final tg = AppScope.of(context).tg;
    return EscapeToClose(
      onEscape: () => Navigator.of(context).pop(),
      child: ListenableBuilder(
        listenable: tg,
        builder: (context, _) {
          final path = tg.downloadedPath(widget.file);
          if (path != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _player == null) setState(() => _start(path));
            });
          }
          final controller = _controller;
          return ColoredBox(
            color: const Color(0xFF000000),
            child: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: controller == null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              VideoCoverContain(cover: widget.cover),
                              Center(
                                child: _ProgressButton(
                                  progress: tg.downloadProgress(widget.file),
                                ),
                              ),
                            ],
                          )
                        : Video(
                            controller: controller,
                            controls: NoVideoControls,
                            fill: const Color(0xFF000000),
                          ),
                  ),
                  if (_controlsVisible || controller == null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          color: Color(0xFFFFFFFF),
                          size: 26,
                        ),
                      ),
                    ),
                  if (_player != null && _controlsVisible)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PlayerControls(
                        player: _player!,
                        onInteraction: _scheduleHide,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The cover while the video downloads, letterboxed like the video itself.
class VideoCoverContain extends StatelessWidget {
  const VideoCoverContain({super.key, required this.cover});

  final Widget cover;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: 0.6, child: Center(child: cover));
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.player, required this.onInteraction});

  final Player player;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFFFFFFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x99000000)],
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (context, _) {
          final position = player.state.position;
          final duration = player.state.duration;
          final max = math.max(duration.inMilliseconds, 1).toDouble();
          return Row(
            children: [
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, _) => CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () async {
                    if (player.state.completed) {
                      await player.seek(Duration.zero);
                      await player.play();
                    } else {
                      await player.playOrPause();
                    }
                    onInteraction();
                  },
                  child: Icon(
                    player.state.playing
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    color: white,
                    size: 26,
                  ),
                ),
              ),
              Text(
                formatDuration(position.inSeconds),
                style: const TextStyle(color: white, fontSize: 13),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: position.inMilliseconds.clamp(0, max).toDouble(),
                  max: max,
                  activeColor: white,
                  thumbColor: white,
                  onChanged: (v) {
                    player.seek(Duration(milliseconds: v.round()));
                    onInteraction();
                  },
                ),
              ),
              Text(
                formatDuration(duration.inSeconds),
                style: const TextStyle(color: white, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0x80000000),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: const BoxDecoration(
      color: Color(0x80000000),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: const Color(0xFFFFFFFF), size: 24),
  );
}

/// Circular download progress, or a download arrow before it starts.
class _ProgressButton extends StatelessWidget {
  const _ProgressButton({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: const BoxDecoration(
      color: Color(0x80000000),
      shape: BoxShape.circle,
    ),
    child: CustomPaint(
      painter: _RingPainter(progress),
      child: const Icon(
        CupertinoIcons.arrow_down,
        color: Color(0xFFFFFFFF),
        size: 20,
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = (Offset.zero & size).deflate(4);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
