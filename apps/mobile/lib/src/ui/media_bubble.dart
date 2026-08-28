import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n.dart';
import '../layout.dart';
import '../media_service.dart';
import '../models.dart';
import '../motion.dart';
import '../theme.dart';

/// An attachment inside a message bubble.
///
/// Three states, and all three are real work rather than a spinner standing in
/// for the missing ones:
///
///  - **not downloaded** — the size and a download affordance. On metered data
///    the decision to spend 8MB belongs to the user, so a photo in a chat that
///    has scrolled past does not fetch itself.
///  - **downloading** — progress, with the bubble already at its final size so
///    the conversation does not jump when it lands.
///  - **failed** — the reason and a retry. A failed attachment that vanishes is
///    worse than one that says it failed.
class MediaAttachment extends StatefulWidget {
  const MediaAttachment({
    super.key,
    required this.message,
    required this.media,
  });

  final Message message;
  final MediaService media;

  @override
  State<MediaAttachment> createState() => _MediaAttachmentState();
}

enum _Stage { idle, loading, ready, failed }

class _MediaAttachmentState extends State<MediaAttachment> {
  _Stage _stage = _Stage.idle;
  File? _file;

  @override
  void initState() {
    super.initState();
    _maybeAutoLoad();
  }

  /// Only pictures already on disk render themselves without being asked.
  ///
  /// Anything that would cost bytes waits for a tap. This is the difference
  /// between opening a chat costing nothing and opening a chat costing a
  /// month's data on a family group full of photos.
  Future<void> _maybeAutoLoad() async {
    final key = widget.message.mediaKey;
    if (key == null) return;
    if (widget.message.mediaKind != 'image') return;
    if (!await widget.media.isCached(key)) return;
    if (!mounted) return;
    await _load();
  }

  Future<void> _load() async {
    final key = widget.message.mediaKey;
    if (key == null) return;

    setState(() => _stage = _Stage.loading);

    try {
      final file = await widget.media.localFile(
        chatId: widget.message.chatId,
        key: key,
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _stage = _Stage.ready;
      });
    } catch (err) {
      // The user gets a translated sentence and a retry; the exception goes to
      // the log, because "ClientException: Connection closed" in a chat bubble
      // helps nobody who is not us.
      debugPrint('attachment download failed: $err');
      if (!mounted) return;
      setState(() => _stage = _Stage.failed);
    }
  }

  String get _humanSize {
    final size = widget.message.mediaSize;
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final kind = widget.message.mediaKind;

    // A fixed height while loading, matched to what the content will occupy,
    // so the message list does not reflow when the bytes arrive.
    final tileHeight = kind == 'file' ? 56.0 : (layout.isNarrow ? 160.0 : 200.0);

    Widget frame(Widget child, {VoidCallback? onTap}) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: tileHeight,
                width: double.infinity,
                child: child,
              ),
            ),
          ),
        );

    switch (_stage) {
      case _Stage.loading:
        return frame(
          Container(
            color: palette.line,
            alignment: Alignment.center,
            child: const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );

      case _Stage.failed:
        return frame(
          Container(
            color: palette.line,
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: palette.anor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.t('upload_failed'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(onPressed: _load, child: Text(l10n.t('retry'))),
              ],
            ),
          ),
          onTap: _load,
        );

      case _Stage.ready:
        final file = _file;
        if (file == null) return const SizedBox.shrink();

        if (kind == 'image') {
          return frame(
            Image.file(file, fit: BoxFit.cover),
            onTap: () => _openFullScreen(context, file, kind),
          );
        }
        if (kind == 'video') {
          return frame(
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: Icon(Icons.play_circle_outline, size: 48, color: palette.bubbleTheirs),
            ),
            onTap: () => _openFullScreen(context, file, kind),
          );
        }
        return _fileRow(context, l10n, palette, layout, opened: true);

      case _Stage.idle:
        if (kind == 'file') {
          return _fileRow(context, l10n, palette, layout, opened: false);
        }
        // A photo or video that has not been fetched. The size is on the button
        // so the cost of tapping is visible before it is spent.
        return frame(
          Container(
            color: palette.line,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kind == 'video' ? Icons.play_circle_outline : Icons.image_outlined,
                  size: 30,
                  color: palette.muted,
                ),
                const SizedBox(height: 6),
                Text(
                  _humanSize,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
          onTap: _load,
        );
    }
  }

  Widget _fileRow(
    BuildContext context,
    L10n l10n,
    SakinaPalette palette,
    SakinaLayout layout, {
    required bool opened,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: opened ? null : _load,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                opened ? Icons.check_circle_outline : Icons.insert_drive_file_outlined,
                size: 24,
                color: palette.muted,
              ),
              SizedBox(width: layout.gap / 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.message.mediaName ?? l10n.t('a_file'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      _humanSize,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: palette.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context, File file, String kind) {
    Navigator.of(context).push(
      SakinaPageRoute<void>(
        // A viewer is not somewhere you navigated to, so it rises from the
        // bottom and has no back-swipe — the transition builder branches on
        // this flag, and dismissing is the close button's job.
        fullscreenDialog: true,
        builder: (_) => _MediaViewer(file: file, isVideo: kind == 'video'),
      ),
    );
  }
}

/// Full-screen photo or video.
///
/// Deliberately plain: a black ground, the content, and a close button. This is
/// the one screen where the brand's "quiet chrome so the content can be loud"
/// rule is not a metaphor.
class _MediaViewer extends StatefulWidget {
  const _MediaViewer({required this.file, required this.isVideo});

  final File file;
  final bool isVideo;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      final controller = VideoPlayerController.file(widget.file);
      _controller = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        controller.play();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: widget.isVideo
            ? (controller != null && controller.value.isInitialized
                ? AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(controller),
                        VideoProgressIndicator(controller, allowScrubbing: true),
                      ],
                    ),
                  )
                : const CircularProgressIndicator())
            : InteractiveViewer(
                maxScale: 5,
                child: Image.file(widget.file, fit: BoxFit.contain),
              ),
      ),
      floatingActionButton: widget.isVideo && controller != null
          ? FloatingActionButton(
              onPressed: () => setState(() {
                controller.value.isPlaying ? controller.pause() : controller.play();
              }),
              child: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}
