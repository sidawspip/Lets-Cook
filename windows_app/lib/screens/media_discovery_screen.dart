import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../models/models.dart';
import '../services/media_resolver.dart';
import '../services/public_media_links.dart';
import '../state/watch_party_controller.dart';
import '../theme/app_theme.dart';

class MediaDiscoveryScreen extends StatefulWidget {
  const MediaDiscoveryScreen({
    super.key,
    required this.controller,
    this.initialQuery = '',
    this.targetRoomId,
    this.initialProvider,
    this.initialMediaId,
    this.initialSourceUrl,
    this.viewerLoginMode = false,
  });

  final WatchPartyController controller;
  final String initialQuery;
  final String? targetRoomId;
  final String? initialProvider;
  final String? initialMediaId;
  final String? initialSourceUrl;
  final bool viewerLoginMode;

  @override
  State<MediaDiscoveryScreen> createState() => _MediaDiscoveryScreenState();
}

class _MediaDiscoveryScreenState extends State<MediaDiscoveryScreen> {
  static const _providers = <_DesktopProvider>[
    _DesktopProvider(
      'YouTube',
      Icons.play_circle_fill_rounded,
      'https://www.youtube.com/',
    ),
    _DesktopProvider(
      'Google Drive',
      Icons.add_to_drive_rounded,
      'https://drive.google.com/drive/u/0/my-drive',
    ),
    _DesktopProvider(
      'Dropbox',
      Icons.cloud_rounded,
      'https://www.dropbox.com/home',
    ),
    _DesktopProvider(
      'OneDrive',
      Icons.cloud_queue_rounded,
      'https://onedrive.live.com/',
    ),
    _DesktopProvider('Box', Icons.inventory_2_rounded, 'https://app.box.com/'),
    _DesktopProvider(
      'Internet Archive',
      Icons.account_balance_rounded,
      'https://archive.org/details/movies',
    ),
    _DesktopProvider('Twitch', Icons.live_tv_rounded, 'https://www.twitch.tv/'),
    _DesktopProvider(
      'Vimeo',
      Icons.video_library_rounded,
      'https://vimeo.com/watch',
    ),
    _DesktopProvider('X', Icons.alternate_email_rounded, 'https://x.com/home'),
    _DesktopProvider(
      'Google Search',
      Icons.search_rounded,
      'https://www.google.com/',
    ),
    _DesktopProvider(
      'DuckDuckGo',
      Icons.privacy_tip_rounded,
      'https://duckduckgo.com/',
    ),
    _DesktopProvider(
      'Nextcloud',
      Icons.cloud_sync_rounded,
      'https://nextcloud.com/sign-up/',
    ),
    _DesktopProvider(
      'Crunchyroll',
      Icons.animation_rounded,
      'https://www.crunchyroll.com/videos/new',
    ),
    _DesktopProvider(
      'Netflix',
      Icons.movie_rounded,
      'https://www.netflix.com/browse',
    ),
    _DesktopProvider(
      'Prime Video',
      Icons.ondemand_video_rounded,
      'https://www.primevideo.com/',
    ),
  ];

  final browser = WebviewController();
  final address = TextEditingController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  String currentUrl = '';
  String pageTitle = '';
  String? browserError;
  bool browserReady = false;
  bool loading = true;
  bool committing = false;
  bool canGoBack = false;
  bool canGoForward = false;
  _DetectedPageVideo? detectedPageVideo;
  int _pageDetectionGeneration = 0;
  String? _autoQueuedUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeBrowser());
  }

  Future<void> _initializeBrowser() async {
    try {
      final runtime = await WebviewController.getWebViewVersion();
      if (runtime == null) {
        throw PlatformException(
          code: 'webview2_missing',
          message: 'Microsoft Edge WebView2 Runtime is not installed.',
        );
      }
      await browser.initialize();
      await browser.setBackgroundColor(const Color(0xFF080A12));
      await browser.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      subscriptions
        ..add(
          browser.url.listen((value) {
            if (!mounted) return;
            final detectionGeneration = ++_pageDetectionGeneration;
            setState(() {
              currentUrl = value;
              address.text = value;
              detectedPageVideo = null;
            });
            final uri = Uri.tryParse(value);
            if (uri != null && uri.host.isNotEmpty) {
              // WebView2 can publish the final SPA URL after its loaded event.
              // React to the URL itself so a YouTube/provider card click is
              // selected immediately instead of requiring Add to room.
              unawaited(_autoQueuePlayablePage(uri));
              unawaited(_watchForPagePlayer(detectionGeneration));
            }
          }),
        )
        ..add(
          browser.title.listen((value) {
            if (mounted) setState(() => pageTitle = value);
          }),
        )
        ..add(
          browser.loadingState.listen((value) {
            if (mounted) {
              setState(() => loading = value == LoadingState.loading);
            }
            if (value != LoadingState.loading) {
              final uri = Uri.tryParse(currentUrl);
              if (uri != null && uri.host.isNotEmpty) {
                unawaited(_autoQueuePlayablePage(uri));
                unawaited(_watchForPagePlayer(_pageDetectionGeneration));
              }
            }
          }),
        )
        ..add(
          browser.historyChanged.listen((value) {
            if (!mounted) return;
            setState(() {
              canGoBack = value.canGoBack;
              canGoForward = value.canGoForward;
            });
          }),
        );
      final initial = _initialUrl();
      currentUrl = initial;
      address.text = initial;
      await browser.loadUrl(initial);
      if (!mounted) return;
      setState(() {
        browserReady = true;
        browserError = null;
      });
      unawaited(_watchForPagePlayer(_pageDetectionGeneration));
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        browserError = error.code == 'webview2_missing'
            ? 'WebView2 is required for provider browsing on Windows.'
            : 'The Windows browser could not start: ${error.message ?? error.code}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        browserError = 'The Windows browser could not start: $error';
      });
    }
  }

  String _initialUrl() {
    final source = widget.initialSourceUrl?.trim();
    if (source != null && source.isNotEmpty) return source;
    final query = widget.initialQuery.trim();
    if (query.isNotEmpty) {
      return Uri.https('www.youtube.com', '/results', {
        'search_query': query,
      }).toString();
    }
    final provider = widget.initialProvider?.trim().toLowerCase();
    if (provider == 'web') {
      return 'https://www.google.com/';
    }
    return _providers
            .where((item) => item.label.toLowerCase() == provider)
            .map((item) => item.url)
            .firstOrNull ??
        _providers.first.url;
  }

  Future<void> _navigate(String value) async {
    var text = value.trim();
    if (text.isEmpty || !browserReady) return;
    final parsed = Uri.tryParse(text);
    if (parsed == null || parsed.scheme.isEmpty) {
      text = Uri.https('www.google.com', '/search', {'q': text}).toString();
    } else if (!const {'http', 'https'}.contains(parsed.scheme)) {
      _message('Only HTTP and HTTPS addresses can be opened.');
      return;
    }
    FocusScope.of(context).unfocus();
    await browser.loadUrl(text);
  }

  Future<void> _addCurrentPage() async {
    if (committing) return;
    final uri = Uri.tryParse(currentUrl);
    if (uri == null || uri.scheme != 'https') {
      _message('Open a secure video or provider page first.');
      return;
    }
    setState(() => committing = true);
    var title = pageTitle.trim().isEmpty ? uri.host : pageTitle.trim();
    if (_isDrmProviderPage(uri)) {
      setState(() => committing = false);
      _message(
        'This provider uses protected DRM playback. It is intentionally disabled for now.',
      );
      return;
    }
    final youtubeId = _youtubeVideoId(uri);
    if (youtubeId != null) {
      await widget.controller.selectYoutubeVideo(
        VideoSuggestion(
          videoId: youtubeId,
          title: title,
          channelTitle: 'YouTube',
          thumbnailUrl: 'https://i.ytimg.com/vi/$youtubeId/hqdefault.jpg',
          provider: 'YOUTUBE',
        ),
        targetRoomId: widget.targetRoomId,
      );
    } else {
      final publicLink = _publicMediaLink(uri);
      if (publicLink != null && _isPublicSharePage(uri, publicLink)) {
        final normalized = normalizePublicMediaLink(uri, publicLink);
        final playable = await probeDirectMedia(
          normalized,
          sourceType: 'DIRECT_MP4',
        );
        if (!playable) {
          _rejectUnresolvedPage(
            'This shared file did not expose a public playable video. Make the '
            'file viewable by link, then select it again.',
          );
          return;
        }
        await widget.controller.selectDirectVideo(
          normalized.toString(),
          targetRoomId: widget.targetRoomId,
          sourceType: 'DIRECT_MP4',
          title: title,
        );
      } else if (_isDirectMedia(uri)) {
        final sourceType = uri.path.toLowerCase().endsWith('.m3u8')
            ? 'DIRECT_HLS'
            : 'DIRECT_MP4';
        if (!await probeDirectMedia(uri, sourceType: sourceType)) {
          _rejectUnresolvedPage(
            'That address did not return a playable video stream.',
          );
          return;
        }
        await widget.controller.selectDirectVideo(
          uri.toString(),
          targetRoomId: widget.targetRoomId,
          sourceType: sourceType,
          title: title,
        );
      } else {
        final captured = await _capturePlayableMedia();
        if (captured != null) {
          final capturedUri = Uri.parse(captured.url);
          if (!await probeDirectMedia(
            capturedUri,
            sourceType: captured.sourceType,
          )) {
            _rejectUnresolvedPage(
              'This site exposed a temporary or protected stream that the '
              'room player cannot use yet.',
            );
            return;
          }
          title = captured.title.isEmpty ? title : captured.title;
          final providerLabel = _providerLabel(uri);
          await widget.controller.selectDirectVideo(
            captured.url,
            targetRoomId: widget.targetRoomId,
            sourceType: captured.sourceType,
            title: '$title · $providerLabel',
            thumbnailUrl: captured.poster,
          );
        } else {
          _rejectUnresolvedPage(
            'No playable video was found on this page. Start the video or '
            'choose a public MP4/HLS item; the webpage itself will not be '
            'added to the room.',
          );
          return;
        }
      }
    }
    if (!mounted) return;
    if (widget.controller.error == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => committing = false);
    _message(widget.controller.error!);
  }

  void _rejectUnresolvedPage(String message) {
    _autoQueuedUrl = null;
    if (mounted) setState(() => committing = false);
    _message(message);
  }

  Future<void> _autoQueuePlayablePage(Uri uri) async {
    if (!mounted ||
        committing ||
        widget.viewerLoginMode ||
        _autoQueuedUrl == uri.toString()) {
      return;
    }
    if (_isDrmProviderPage(uri)) return;
    if (_youtubeVideoId(uri) != null) {
      _autoQueuedUrl = uri.toString();
      // YouTube publishes the SPA URL before its document title. Give the
      // title stream a brief moment so the queue card keeps the real title.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || currentUrl != uri.toString()) {
        _autoQueuedUrl = null;
        return;
      }
      await _addCurrentPage();
      if (mounted && widget.controller.error != null) {
        _autoQueuedUrl = null;
      }
      return;
    }
    final publicLink = _publicMediaLink(uri);
    final dedicatedProviderSelection =
        (publicLink != null && _isPublicSharePage(uri, publicLink)) ||
        _looksLikeProviderMedia(uri);
    if (dedicatedProviderSelection) {
      _autoQueuedUrl = uri.toString();
      // Provider SPAs publish their detail URL before the video element and
      // metadata exist. Let the page expose its real MP4/HLS stream so the
      // room can use our custom player rather than embedding the whole page.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || currentUrl != uri.toString()) {
        _autoQueuedUrl = null;
        return;
      }
      await _addCurrentPage();
      if (mounted && widget.controller.error != null) {
        _autoQueuedUrl = null;
      }
      return;
    }
    if (_isDirectMedia(uri)) {
      _autoQueuedUrl = uri.toString();
      await _addCurrentPage();
      if (mounted && widget.controller.error != null) {
        _autoQueuedUrl = null;
      }
    }
  }

  Future<void> _watchForPagePlayer(int generation) async {
    if (!browserReady || widget.viewerLoginMode) return;
    final uri = Uri.tryParse(currentUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        _isDrmProviderPage(uri) ||
        _youtubeVideoId(uri) != null) {
      return;
    }
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted || generation != _pageDetectionGeneration) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final result = await browser.executeScript(r'''
          (() => {
            const candidates = Array.from(document.querySelectorAll(
              'video, [data-player], [class*="video-player"], [class*="player-container"], iframe[src*="/embed/"]'
            ));
            const player = candidates.find(element => {
              const box = element.getBoundingClientRect();
              const style = getComputedStyle(element);
              const text = `${element.id || ''} ${element.className || ''}`.toLowerCase();
              return box.width >= 160 && box.height >= 90
                && style.display !== 'none' && style.visibility !== 'hidden'
                && !/(^|[-_ ])ad(s|vert|vertisement)?([-_ ]|$)/.test(text);
            });
            const video = player?.tagName === 'VIDEO'
              ? player
              : player?.querySelector?.('video');
            let poster = video?.poster
              || document.querySelector('meta[property="og:image"]')?.content
              || document.querySelector('meta[name="twitter:image"]')?.content
              || '';
            try { if (poster) poster = new URL(poster, location.href).href; } catch (_) {}
            const title = document.querySelector('meta[property="og:title"]')?.content
              || document.querySelector('meta[name="twitter:title"]')?.content
              || document.title
              || 'Video found on this page';
            return JSON.stringify({found: Boolean(player), poster, title});
          })()
        ''');
        dynamic decoded = jsonDecode(result.toString());
        if (decoded is String) decoded = jsonDecode(decoded);
        if (decoded is Map<String, dynamic> &&
            decoded['found'] == true &&
            mounted &&
            generation == _pageDetectionGeneration) {
          final poster = (decoded['poster'] ?? '').toString().trim();
          final posterUri = Uri.tryParse(poster);
          setState(
            () => detectedPageVideo = _DetectedPageVideo(
              title: (decoded['title'] ?? 'Video found on this page')
                  .toString()
                  .trim(),
              thumbnailUrl:
                  posterUri?.scheme == 'https' &&
                      posterUri?.host.isNotEmpty == true
                  ? poster
                  : null,
            ),
          );
          return;
        }
      } catch (_) {
        // Some sites temporarily block script access while navigating.
      }
    }
  }

  Future<_CapturedPageMedia?> _capturePlayableMedia() async {
    if (!browserReady) return null;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final raw = await browser.executeScript(r'''
          (() => {
            const videos = Array.from(document.querySelectorAll('video'));
            const video = videos.find(v => v.offsetWidth >= 160 && v.offsetHeight >= 90) || videos[0];
            const resources = performance.getEntriesByType('resource')
              .map(entry => entry.name)
              .reverse();
            const candidates = [
              video?.currentSrc,
              video?.src,
              ...Array.from(video?.querySelectorAll('source') || []).map(source => source.src),
              ...resources.filter(url => /(?:\.m3u8|\.mp4)(?:[?#]|$)/i.test(url)),
            ].filter(Boolean);
            const url = candidates.find(value => /^https:\/\//i.test(value) && /(?:\.m3u8|\.mp4)(?:[?#]|$)/i.test(value));
            const title = document.querySelector('meta[property="og:title"]')?.content
              || document.querySelector('meta[name="twitter:title"]')?.content
              || document.title
              || '';
            const poster = video?.poster
              || document.querySelector('meta[property="og:image"]')?.content
              || '';
            return JSON.stringify({url: url || '', title, poster});
          })();
        ''');
        final decoded = jsonDecode(raw.toString());
        if (decoded is Map<String, dynamic>) {
          final value = (decoded['url'] ?? '').toString().trim();
          final mediaUri = Uri.tryParse(value);
          if (mediaUri != null &&
              mediaUri.scheme == 'https' &&
              mediaUri.host.isNotEmpty) {
            final lower = value.toLowerCase();
            final poster = (decoded['poster'] ?? '').toString().trim();
            return _CapturedPageMedia(
              url: value,
              sourceType: lower.contains('.m3u8') ? 'DIRECT_HLS' : 'DIRECT_MP4',
              title: (decoded['title'] ?? '').toString().trim(),
              poster: poster.isEmpty ? null : poster,
            );
          }
        }
      } catch (_) {
        // Cross-origin provider frames can temporarily hide their player.
        // Keep polling until the top page exposes a media resource.
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return null;
    }

    // The page may hide its stream behind player configuration that is not
    // visible to the desktop WebView. Ask the shared scraper to normalize the
    // page into the same direct-media resource used by the room controller.
    final pageUri = Uri.tryParse(currentUrl);
    if (pageUri == null || pageUri.scheme != 'https') return null;
    try {
      final resolved = await widget.controller.api.resolveWebMedia(
        pageUri.toString(),
      );
      final value = (resolved['sourceUrl'] ?? '').toString().trim();
      final sourceType = (resolved['sourceType'] ?? '')
          .toString()
          .toUpperCase();
      final mediaUri = Uri.tryParse(value);
      if (mediaUri == null ||
          mediaUri.scheme != 'https' ||
          mediaUri.host.isEmpty ||
          !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(sourceType)) {
        return null;
      }
      final resolvedTitle = (resolved['title'] ?? '').toString().trim();
      final siteName = (resolved['siteName'] ?? '').toString().trim();
      return _CapturedPageMedia(
        url: value,
        sourceType: sourceType,
        title: resolvedTitle.isEmpty
            ? pageTitle.trim()
            : siteName.isEmpty
            ? resolvedTitle
            : '$resolvedTitle · $siteName',
        poster: detectedPageVideo?.thumbnailUrl,
      );
    } catch (_) {
      // Unsupported, authenticated, or DRM-bound pages remain unselectable.
    }
    return null;
  }

  static String _providerLabel(Uri uri) {
    final code = _providerFor(uri);
    return switch (code) {
      'INTERNET_ARCHIVE' => 'Internet Archive',
      'GOOGLE_DRIVE' => 'Google Drive',
      'PRIME_VIDEO' => 'Prime Video',
      _ => code.toLowerCase().replaceAll('_', ' '),
    };
  }

  static String? _youtubeVideoId(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    if (host.endsWith('youtube.com')) {
      if (uri.path == '/watch') return uri.queryParameters['v'];
      if (uri.pathSegments.length >= 2 &&
          const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
        return uri.pathSegments[1];
      }
    }
    return null;
  }

  static bool _isDirectMedia(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.mp4') || path.endsWith('.m3u8');
  }

  static PublicMediaLinkProvider? _publicMediaLink(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'drive.google.com' || host.endsWith('.drive.google.com')) {
      return PublicMediaLinkProvider.googleDrive;
    }
    if (host == 'dropbox.com' || host.endsWith('.dropbox.com')) {
      return PublicMediaLinkProvider.dropbox;
    }
    if (host == '1drv.ms' || host.endsWith('.onedrive.live.com')) {
      return PublicMediaLinkProvider.oneDrive;
    }
    if (host == 'box.com' || host.endsWith('.box.com')) {
      return PublicMediaLinkProvider.box;
    }
    return null;
  }

  static bool _isPublicSharePage(Uri uri, PublicMediaLinkProvider provider) {
    final normalized = normalizePublicMediaLink(uri, provider);
    if (normalized == uri) return false;
    return switch (provider) {
      PublicMediaLinkProvider.googleDrive =>
        uri.pathSegments.contains('d') || uri.queryParameters.containsKey('id'),
      PublicMediaLinkProvider.dropbox =>
        uri.path.startsWith('/s/') || uri.path.startsWith('/scl/'),
      PublicMediaLinkProvider.oneDrive =>
        uri.host.toLowerCase() == '1drv.ms' ||
            uri.queryParameters.containsKey('resid'),
      PublicMediaLinkProvider.box => uri.path.startsWith('/s/'),
      PublicMediaLinkProvider.nextcloud => false,
    };
  }

  static String _providerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.contains('crunchyroll')) return 'CRUNCHYROLL';
    if (host.contains('netflix')) return 'NETFLIX';
    if (host.contains('primevideo') || host.contains('amazon')) {
      return 'PRIME_VIDEO';
    }
    if (host.contains('twitch')) return 'TWITCH';
    if (host.contains('vimeo')) return 'VIMEO';
    if (host == 'x.com' || host.endsWith('.x.com')) return 'X';
    if (host.contains('archive.org')) return 'INTERNET_ARCHIVE';
    return 'WEB';
  }

  static bool _looksLikeProviderMedia(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    bool hostIs(String value) => host == value || host.endsWith('.$value');
    if (hostIs('archive.org')) return path.contains('/details/');
    if (hostIs('x.com') || hostIs('twitter.com')) {
      return path.contains('/status/');
    }
    if (hostIs('twitch.tv')) {
      return path.contains('/videos/') ||
          (path.length > 1 && !path.startsWith('/directory'));
    }
    if (hostIs('vimeo.com')) {
      return RegExp(r'/(?:video/)?\d+').hasMatch(path);
    }
    return false;
  }

  static bool _isDrmProviderPage(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('netflix.com') ||
        host.contains('primevideo.com') ||
        host.contains('amazon.com') ||
        host.contains('crunchyroll.com');
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    browser.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF070913),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            _providerRail(compact: constraints.maxWidth < 1100),
            const VerticalDivider(width: 1, color: Color(0x24FFFFFF)),
            Expanded(child: _browserPane()),
          ],
        ),
      ),
    ),
  );

  Widget _providerRail({required bool compact}) => SizedBox(
    width: compact ? 196 : 244,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 10),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Choose a provider',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: _providers.length,
            itemBuilder: (context, index) {
              final provider = _providers[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  leading: Icon(provider.icon, color: AppColors.lime),
                  title: Text(provider.label),
                  subtitle: _isDrmLabel(provider.label)
                      ? const Text('Coming later · DRM')
                      : null,
                  onTap: !browserReady
                      ? null
                      : () {
                          if (_isDrmLabel(provider.label)) {
                            _message(
                              '${provider.label} uses protected DRM playback and is deferred for now.',
                            );
                            return;
                          }
                          _navigate(provider.url);
                        },
                ),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Text(
            'Sign in inside this private Windows browser. Passwords and provider cookies are never sent to a room.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
          ),
        ),
      ],
    ),
  );

  Widget _browserPane() => Column(
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: const Color(0xFF101322),
        child: Row(
          children: [
            IconButton(
              onPressed: canGoBack ? browser.goBack : null,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Browser back',
            ),
            IconButton(
              onPressed: canGoForward ? browser.goForward : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: 'Browser forward',
            ),
            IconButton(
              onPressed: browserReady ? browser.reload : null,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload',
            ),
            const Spacer(),
            if (widget.viewerLoginMode) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: browserReady && !committing ? _addCurrentPage : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use this page'),
              ),
            ],
          ],
        ),
      ),
      if (loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: browserError != null
                  ? _browserError()
                  : !browserReady
                  ? const Center(child: CircularProgressIndicator())
                  : Webview(
                      browser,
                      permissionRequested: (_, _, _) async =>
                          WebviewPermissionDecision.deny,
                    ),
            ),
            if (detectedPageVideo case final _DetectedPageVideo preview)
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Material(
                  elevation: 12,
                  color: const Color(0xF2181C2C),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 108,
                            height: 66,
                            child: preview.thumbnailUrl == null
                                ? const ColoredBox(
                                    color: Color(0xFF0B0E18),
                                    child: Icon(
                                      Icons.video_library_rounded,
                                      size: 34,
                                    ),
                                  )
                                : Image.network(
                                    preview.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const ColoredBox(
                                      color: Color(0xFF0B0E18),
                                      child: Icon(
                                        Icons.video_library_rounded,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'VIDEO FOUND',
                                style: TextStyle(
                                  color: AppColors.lime,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                preview.title.isEmpty
                                    ? 'Video found on this page'
                                    : preview.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: committing ? null : _addCurrentPage,
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: Text(
                            widget.targetRoomId == null
                                ? 'Play in room'
                                : widget.controller.watchState == null &&
                                      widget.controller.canControlWatch
                                ? 'Play in this room'
                                : 'Add to room queue',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _browserError() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.web_asset_off_rounded, size: 46),
              const SizedBox(height: 16),
              Text(
                browserError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Install the Microsoft Edge WebView2 Runtime, then reopen Let’s Cook.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  static bool _isDrmLabel(String label) =>
      const {'Crunchyroll', 'Netflix', 'Prime Video'}.contains(label);
}

class _CapturedPageMedia {
  const _CapturedPageMedia({
    required this.url,
    required this.sourceType,
    required this.title,
    this.poster,
  });

  final String url;
  final String sourceType;
  final String title;
  final String? poster;
}

class _DetectedPageVideo {
  const _DetectedPageVideo({required this.title, this.thumbnailUrl});

  final String title;
  final String? thumbnailUrl;
}

class _DesktopProvider {
  const _DesktopProvider(this.label, this.icon, this.url);

  final String label;
  final IconData icon;
  final String url;
}
