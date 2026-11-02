import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A lightweight poster that automatically becomes a short, muted preview.
/// YouTube uses its animated thumbnail. Direct media intentionally stays on
/// its poster: opening another native decoder for every room/chat card can
/// starve the real player and exhaust signed-stream connection limits.
class MediaPreview extends StatefulWidget {
  const MediaPreview({
    super.key,
    required this.mediaId,
    required this.provider,
    this.thumbnailUrl,
    this.contentLabel,
    this.sensitive = false,
    this.showBadge = true,
    this.enablePreview = true,
  });

  final String mediaId;
  final String provider;
  final String? thumbnailUrl;
  final String? contentLabel;
  final bool sensitive;
  final bool showBadge;
  final bool enablePreview;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview>
    with SingleTickerProviderStateMixin {
  Timer? _youtubeTimer;
  late final AnimationController _thumbnailMotion;
  int _youtubeFrame = 1;
  bool _previewing = true;
  bool _animatedYoutubeFailed = false;

  String get _provider => widget.provider.toUpperCase();
  String? get _youtubeId => youtubeVideoId(widget.mediaId);
  bool get _isYoutube => _provider == 'YOUTUBE' || _youtubeId != null;
  bool get _isSensitive =>
      widget.sensitive ||
      _looksSensitive('${widget.contentLabel ?? ''} ${widget.mediaId}');
  String get _providerLabel {
    if (_isYoutube) return 'YouTube';
    if (_provider == 'WEB' || _provider.startsWith('DIRECT_')) return 'Web';
    if (_provider == 'CRUNCHYROLL') return 'Crunchyroll';
    if (_provider == 'GOOGLE_DRIVE' || _provider == 'DRIVE') return 'Drive';
    if (_provider == 'TWITCH') return 'Twitch';
    if (_provider == 'PHOTOS') return 'Photos';
    final words = _provider.toLowerCase().split('_');
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  bool get _canPreview => widget.enablePreview && _youtubeId != null;

  String? get _posterUrl {
    final supplied = widget.thumbnailUrl?.trim() ?? '';
    if (supplied.isNotEmpty) return supplied;
    final id = _youtubeId;
    return id == null ? null : 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }

  @override
  void initState() {
    super.initState();
    _thumbnailMotion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startYoutubePreview();
    });
  }

  @override
  void didUpdateWidget(covariant MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId ||
        oldWidget.provider != widget.provider) {
      _youtubeTimer?.cancel();
      _youtubeFrame = 1;
      _previewing = true;
      _animatedYoutubeFailed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startYoutubePreview();
      });
    }
  }

  void _startYoutubePreview() {
    _youtubeTimer?.cancel();
    if (!_canPreview || _youtubeId == null) return;
    _youtubeTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted || _animatedYoutubeFailed) return;
      setState(() => _youtubeFrame = (_youtubeFrame % 3) + 1);
    });
  }

  @override
  void dispose() {
    _youtubeTimer?.cancel();
    _thumbnailMotion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final youtubeId = _youtubeId;
    final storyboardUrl = youtubeId == null
        ? null
        : 'https://i.ytimg.com/vi/$youtubeId/$_youtubeFrame.jpg';
    final showYoutubeStoryboard =
        _canPreview &&
        _previewing &&
        storyboardUrl != null &&
        !_animatedYoutubeFailed;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _thumbnailMotion,
          builder: (context, child) {
            final progress = Curves.easeInOut.transform(_thumbnailMotion.value);
            return ClipRect(
              child: Transform.scale(
                scale: 1.035 + (progress * .055),
                alignment: Alignment(
                  -.35 + (progress * .7),
                  -.12 + ((1 - progress) * .24),
                ),
                child: child,
              ),
            );
          },
          child: _Poster(
            url: showYoutubeStoryboard ? storyboardUrl : _posterUrl,
            provider: _provider,
            onPreviewError: showYoutubeStoryboard
                ? () {
                    if (!mounted || _animatedYoutubeFailed) return;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_animatedYoutubeFailed) {
                        setState(() => _animatedYoutubeFailed = true);
                      }
                    });
                  }
                : null,
          ),
        ),
        if (widget.showBadge)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.82,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSensitive) ...[
                      const _PreviewBadge(
                        label: 'NSFW',
                        color: Color(0xFFD63A65),
                      ),
                      const SizedBox(width: 4),
                    ],
                    _PreviewBadge(
                      label: _providerLabel,
                      color: _isYoutube
                          ? const Color(0xFFE94251)
                          : AppColors.lime,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xC90A0710),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: .58)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 7,
        fontWeight: FontWeight.w900,
        letterSpacing: .25,
      ),
    ),
  );
}

bool _looksSensitive(String value) {
  final text = value.toLowerCase();
  return const [
    'nsfw',
    'adult',
    'porn',
    'xxx',
    'xhamster',
    'xvideos',
    'pornhub',
    'femdom',
    'nude',
    'sex',
  ].any(text.contains);
}

class _Poster extends StatelessWidget {
  const _Poster({
    required this.url,
    required this.provider,
    this.onPreviewError,
  });

  final String? url;
  final String provider;
  final VoidCallback? onPreviewError;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4D2868), Color(0xFF173E59)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.startsWith('DIRECT_')
                  ? Icons.movie_filter_rounded
                  : Icons.ondemand_video_rounded,
              size: 34,
              color: const Color(0xFFE9D8FF),
            ),
            const SizedBox(height: 5),
            Text(
              provider.replaceAll('_', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE9D8FF),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
          ],
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                const Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ),
      errorBuilder: (_, __, ___) {
        onPreviewError?.call();
        return fallback;
      },
    );
  }
}

String? youtubeVideoId(String value) {
  final trimmed = value.trim();
  if (RegExp(r'^[\w-]{11}$').hasMatch(trimmed)) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
    final id = uri.pathSegments.first;
    return RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
  }
  if (uri.host.contains('youtube.com')) {
    final id =
        uri.queryParameters['v'] ??
        (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'embed'
            ? uri.pathSegments[1]
            : null);
    return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
  }
  return null;
}
