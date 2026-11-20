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
  void _selectProvider(_DesktopProvider provider) {
    final nextProvider = provider.label == 'Google Search'
        ? 'web'
        : provider.label;
    if (widget.initialProvider?.toLowerCase() == nextProvider.toLowerCase()) {
      _navigate(provider.url);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MediaDiscoveryScreen(
          controller: widget.controller,
          targetRoomId: widget.targetRoomId,
          initialProvider: nextProvider,
          initialSourceUrl: provider.url,
          viewerLoginMode: widget.viewerLoginMode,
        ),
      ),
    );
  }

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
  bool recoveringBrowser = false;
  _DetectedPageVideo? detectedPageVideo;
  _CapturedPageMedia? _capturedPageMedia;
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
      // Use the same persistent WebView2 profile for every provider, including
      // sites reached through Google Search, so login cookies survive restart.
      await browser.initialize();
      // Provider login cookies remain in the app's existing profile. Avoid
      // stale cached pages and signed media responses during discovery.
      await browser.setCacheDisabled(true);
      await browser.setBackgroundColor(const Color(0xFF080A12));
      await browser.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await browser.addScriptToExecuteOnDocumentCreated(_mediaDetectorScript);
      subscriptions
        ..add(
          browser.url.listen((value) {
            if (!mounted) return;
            // WebView2 may emit the same URL more than once while a provider
            // SPA finishes loading. A duplicate must not cancel the pending
            // video selection for that URL.
            if (currentUrl != value) ++_pageDetectionGeneration;
            setState(() {
              currentUrl = value;
              address.text = value;
              detectedPageVideo = null;
              if (_capturedPageMedia?.pageUrl != value) {
                _capturedPageMedia = null;
              }
            });
            final uri = Uri.tryParse(value);
            if (uri != null && uri.host.isNotEmpty) {
              // WebView2 can publish the final SPA URL after its loaded event.
              // React to the URL itself so a YouTube/provider card click is
              // selected immediately instead of requiring Add to room.
              unawaited(_autoQueuePlayablePage(uri));
            }
          }),
        )
        ..add(browser.webMessage.listen(_handleWebMessage))
        ..add(browser.onLoadError.listen(_handleBrowserLoadError))
        ..add(
          browser.title.listen((value) {
            if (mounted) setState(() => pageTitle = value);
          }),
        )
        ..add(
          browser.loadingState.listen((value) {
            if (mounted) {
              setState(() {
                loading = value == LoadingState.loading;
                if (loading) browserError = null;
              });
            }
            if (value != LoadingState.loading && browserError == null) {
              final uri = Uri.tryParse(currentUrl);
              if (uri != null && uri.host.isNotEmpty) {
                unawaited(_autoQueuePlayablePage(uri));
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
      });
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

  void _handleBrowserLoadError(WebErrorStatus error) {
    if (!mounted || error == WebErrorStatus.WebErrorStatusOperationCanceled) {
      return;
    }
    final host = Uri.tryParse(currentUrl)?.host ?? 'This website';
    final message = switch (error) {
      WebErrorStatus.WebErrorStatusConnectionReset =>
        '$host reset the connection. Retry, or clear cached files and retry.',
      WebErrorStatus.WebErrorStatusHostNameNotResolved =>
        'The address for $host could not be found. Check the website address and your connection.',
      WebErrorStatus.WebErrorStatusDisconnected =>
        'The connection is offline. Reconnect and retry.',
      WebErrorStatus.WebErrorStatusTimeout =>
        '$host took too long to respond. Retry the page.',
      WebErrorStatus.WebErrorStatusValidProxyAuthenticationRequired =>
        'Your network proxy requires sign-in before this page can load.',
      WebErrorStatus.WebErrorStatusCertificateCommonNameIsIncorrect ||
      WebErrorStatus.WebErrorStatusCertificateExpired ||
      WebErrorStatus.WebErrorStatusClientCertificateContainsErrors ||
      WebErrorStatus.WebErrorStatusCertificateRevoked ||
      WebErrorStatus.WebErrorStatusCertificateIsInvalid =>
        'The secure connection to $host could not be verified. Check your device date or try again later.',
      _ => '$host could not load. Retry the page or check your connection.',
    };
    setState(() {
      browserError = message;
      loading = false;
      detectedPageVideo = null;
      _capturedPageMedia = null;
      _pageDetectionGeneration++;
    });
  }

  Future<void> _retryBrowser({bool clearCache = false}) async {
    if (!browserReady || recoveringBrowser) return;
    setState(() {
      recoveringBrowser = true;
      browserError = null;
      detectedPageVideo = null;
      _capturedPageMedia = null;
      _pageDetectionGeneration++;
    });
    final generation = _pageDetectionGeneration;
    final retryUrl = currentUrl;
    try {
      if (clearCache) await browser.clearCache();
      if (!mounted ||
          generation != _pageDetectionGeneration ||
          retryUrl != currentUrl) {
        return;
      }
      await browser.reload();
    } catch (_) {
      if (mounted &&
          generation == _pageDetectionGeneration &&
          retryUrl == currentUrl) {
        setState(() => browserError = 'The page could not restart. Try again.');
      }
    } finally {
      if (mounted) setState(() => recoveringBrowser = false);
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
    final generation = _pageDetectionGeneration;
    bool selectionIsCurrent() {
      if (!mounted) return false;
      if (generation == _pageDetectionGeneration) return true;
      setState(() => committing = false);
      return false;
    }

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
      // WebView2 publishes /watch before YouTube replaces its generic title.
      // Read the selected document after it settles so the room, history, and
      // chat card all receive the actual video name.
      for (var attempt = 0; attempt < 12; attempt++) {
        if (!selectionIsCurrent() || currentUrl != uri.toString()) return;
        try {
          final documentTitle = (await browser.executeScript(
            'document.title',
          ))?.toString().trim();
          if (documentTitle != null &&
              documentTitle.isNotEmpty &&
              documentTitle.toLowerCase() != 'youtube') {
            title = documentTitle.replaceFirst(RegExp(r'\s+-\s+YouTube$'), '');
            break;
          }
        } catch (_) {
          // The page may still be navigating; use its title stream below.
        }
        final streamedTitle = pageTitle.trim();
        if (streamedTitle.isNotEmpty &&
            streamedTitle.toLowerCase() != 'youtube') {
          title = streamedTitle.replaceFirst(RegExp(r'\s+-\s+YouTube$'), '');
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
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
        if (!selectionIsCurrent()) return;
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
        final playable = await probeDirectMedia(uri, sourceType: sourceType);
        if (!selectionIsCurrent()) return;
        if (!playable) {
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
        if (!selectionIsCurrent()) return;
        if (captured != null) {
          final pageUri = Uri.tryParse(captured.pageUrl);
          Uri? capturedUri;
          String? capturedSourceType;
          final candidates = <_CapturedMediaCandidate>[
            _CapturedMediaCandidate(captured.url, captured.sourceType),
            ...captured.candidates,
          ];
          final tested = <String>{};
          for (final candidate in candidates) {
            if (!tested.add(candidate.url)) continue;
            final parsed = Uri.tryParse(candidate.url);
            if (parsed == null ||
                parsed.scheme != 'https' ||
                !_isAllowedCapturedMedia(pageUri, parsed)) {
              continue;
            }
            final resolved = resolveDirectMediaTemplate(parsed);
            if (hasUnresolvedMediaTemplate(resolved)) continue;
            final playable = await probeDirectMedia(
              resolved,
              sourceType: candidate.sourceType,
              sourcePage: pageUri,
            );
            if (!selectionIsCurrent()) return;
            if (playable) {
              capturedUri = resolved;
              capturedSourceType = candidate.sourceType;
              break;
            }
          }
          if (capturedUri == null || capturedSourceType == null) {
            _rejectUnresolvedPage(
              'This site exposed a temporary or protected stream that the '
              'room player cannot use yet.',
            );
            return;
          }
          title = captured.title.isEmpty ? title : captured.title;
          final providerLabel = _providerLabel(uri);
          await widget.controller.selectDirectVideo(
            capturedUri.toString(),
            targetRoomId: widget.targetRoomId,
            sourceType: capturedSourceType,
            title: '$title · $providerLabel',
            thumbnailUrl: captured.poster,
            sourcePageUrl: captured.pageUrl,
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
    // A provider may update its URL while the room API calls are in flight.
    // Once the selected resource has been submitted, that navigation must not
    // keep the user in the provider browser instead of opening the room.
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
    if (publicLink != null && _isPublicSharePage(uri, publicLink)) {
      _autoQueuedUrl = uri.toString();
      // A public cloud share is already an explicit media selection. Ordinary
      // provider detail URLs must wait for a trusted player interaction and a
      // concrete MP4/HLS capture, matching the generic Web flow on Android.
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

  Future<_CapturedPageMedia?> _capturePlayableMedia() async {
    if (!browserReady) return null;
    final generation = _pageDetectionGeneration;
    final capturePageUrl = currentUrl;
    final remembered = _capturedPageMedia;
    if (remembered != null && remembered.pageUrl == currentUrl) {
      return remembered;
    }
    if (detectedPageVideo == null) return null;
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || generation != _pageDetectionGeneration) return null;
      final captured = _capturedPageMedia;
      if (captured != null && captured.pageUrl == capturePageUrl) {
        return captured;
      }
    }

    // The page may hide its stream behind player configuration that is not
    // visible to the desktop WebView. Ask the shared scraper to normalize the
    // page into the same direct-media resource used by the room controller.
    final pageUri = Uri.tryParse(capturePageUrl);
    if (pageUri == null || pageUri.scheme != 'https') return null;
    try {
      final resolved = await widget.controller.api.resolveWebMedia(
        pageUri.toString(),
      );
      if (!mounted || generation != _pageDetectionGeneration) return null;
      final value = (resolved['sourceUrl'] ?? '').toString().trim();
      final sourceType = (resolved['sourceType'] ?? '')
          .toString()
          .toUpperCase();
      final mediaUri = Uri.tryParse(value);
      if (mediaUri == null ||
          mediaUri.scheme != 'https' ||
          mediaUri.host.isEmpty ||
          !_isAllowedCapturedMedia(pageUri, mediaUri) ||
          !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(sourceType)) {
        return null;
      }
      final resolvedTitle = (resolved['title'] ?? '').toString().trim();
      final siteName = (resolved['siteName'] ?? '').toString().trim();
      final posterUri = Uri.tryParse(
        (resolved['thumbnailUrl'] ?? '').toString(),
      );
      return _CapturedPageMedia(
        url: value,
        sourceType: sourceType,
        title: resolvedTitle.isEmpty
            ? pageTitle.trim()
            : siteName.isEmpty
            ? resolvedTitle
            : '$resolvedTitle · $siteName',
        poster:
            detectedPageVideo?.thumbnailUrl ??
            (posterUri?.scheme == 'https' && posterUri!.host.isNotEmpty
                ? posterUri.toString()
                : null),
        pageUrl: pageUri.toString(),
        candidates: (resolved['sources'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (source) => _CapturedMediaCandidate(
                (source['url'] ?? '').toString(),
                (source['sourceType'] ?? '').toString().toUpperCase(),
              ),
            )
            .where((candidate) {
              final uri = Uri.tryParse(candidate.url);
              return uri != null &&
                  _isAllowedCapturedMedia(pageUri, uri) &&
                  const {
                    'DIRECT_MP4',
                    'DIRECT_HLS',
                  }.contains(candidate.sourceType);
            })
            .toList(),
      );
    } catch (_) {
      // Unsupported, authenticated, or DRM-bound pages remain unselectable.
    }
    return null;
  }

  void _handleWebMessage(dynamic raw) {
    if (!mounted) return;
    try {
      dynamic decoded = raw;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      if (map['pageUrl'] != currentUrl ||
          widget.viewerLoginMode ||
          browserError != null) {
        return;
      }
      final pageUri = Uri.tryParse(currentUrl);
      if (pageUri == null ||
          pageUri.scheme != 'https' ||
          pageUri.host.isEmpty ||
          _isDrmProviderPage(pageUri) ||
          _youtubeVideoId(pageUri) != null) {
        return;
      }
      if (map['kind'] == 'lets-cook-player-selected') {
        _capturedPageMedia = null;
        final poster = Uri.tryParse((map['poster'] ?? '').toString());
        setState(
          () => detectedPageVideo = _DetectedPageVideo(
            title: (map['title'] ?? pageTitle).toString(),
            thumbnailUrl: poster?.scheme == 'https' && poster!.host.isNotEmpty
                ? poster.toString()
                : null,
          ),
        );
        return;
      }
      if (map['kind'] != 'lets-cook-media') return;
      final value = (map['url'] ?? '').toString().trim();
      final pageUrl = (map['pageUrl'] ?? currentUrl).toString().trim();
      final mediaUri = Uri.tryParse(value);
      if (mediaUri == null ||
          mediaUri.scheme != 'https' ||
          mediaUri.host.isEmpty ||
          pageUrl != currentUrl ||
          !_isAllowedCapturedMedia(Uri.tryParse(pageUrl), mediaUri)) {
        return;
      }
      final lower = '${map['type'] ?? ''} $value'.toLowerCase();
      var poster = (map['poster'] ?? '').toString().trim();
      final page = Uri.tryParse(pageUrl);
      final posterUri = Uri.tryParse(poster);
      if (poster.isNotEmpty && page != null && posterUri?.hasScheme != true) {
        poster = page.resolve(poster).toString();
      }
      final captured = _CapturedPageMedia(
        url: value,
        sourceType: lower.contains('mpegurl') || lower.contains('.m3u8')
            ? 'DIRECT_HLS'
            : 'DIRECT_MP4',
        title: (map['title'] ?? pageTitle).toString().trim(),
        poster: poster.isEmpty ? null : poster,
        pageUrl: pageUrl,
        candidates: (map['candidates'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) {
              final candidate = Map<String, dynamic>.from(item);
              final url = (candidate['url'] ?? '').toString().trim();
              final type = '${candidate['type'] ?? ''} $url'.toLowerCase();
              return _CapturedMediaCandidate(
                url,
                type.contains('mpegurl') || type.contains('.m3u8')
                    ? 'DIRECT_HLS'
                    : 'DIRECT_MP4',
              );
            })
            .where((item) {
              final uri = Uri.tryParse(item.url);
              return uri != null && _isAllowedCapturedMedia(page, uri);
            })
            .take(8)
            .toList(),
      );
      setState(() {
        _capturedPageMedia = captured;
        detectedPageVideo = _DetectedPageVideo(
          title: captured.title,
          thumbnailUrl: captured.poster,
        );
      });
    } catch (_) {
      // Ignore unrelated provider messages and malformed page data.
    }
  }

  static const String _mediaDetectorScript = r'''
    (() => {
      if (window.__letsCookWindowsMediaDetector) return;
      window.__letsCookWindowsMediaDetector = true;
      const candidates = [];
      let selectedVideo = null;
      const deliver = (payload) => {
        if (window === window.top) {
          window.chrome?.webview?.postMessage(JSON.stringify({...payload, pageUrl: location.href}));
        } else {
          window.parent.postMessage({letsCookFrameSelection: payload}, '*');
        }
      };
      window.addEventListener('message', event => {
        const payload = event.data?.letsCookFrameSelection;
        if (!payload || !['lets-cook-player-selected','lets-cook-media'].includes(payload.kind)) return;
        const frame = Array.from(document.querySelectorAll('iframe')).find(f => f.contentWindow === event.source);
        if (!frame || frame !== document.activeElement || isSearchResultsPage()) return;
        deliver(payload);
      });
      const selectedPlayers = new WeakMap();
      const isAd = (url) => /doubleclick|googlesyndication|adservice|flirtify\.com|\/vast\/|preroll|video-ad/i.test(String(url || ''));
      const isMedia = (url) => {
        const value = String(url || '');
        return /^https:\/\//i.test(value) &&
          (/(?:\.m3u8|\.mp4)(?:[?#]|$)/i.test(value) ||
           /(?:[?&](?:mime|type)=video|format=m3u8)/i.test(value)) &&
          !/\.m4s(?:[?#]|$)|\.ts(?:[?#]|$)|preview/i.test(value) && !isAd(value);
      };
      const remember = (url, type = '', priority = 0) => {
        if (!isMedia(url)) return;
        const value = String(url);
        const existing = candidates.findIndex((item) => item.url === value);
        if (existing >= 0) candidates.splice(existing, 1);
        candidates.push({url: value, type: String(type || ''), priority});
        if (candidates.length > 80) candidates.shift();
      };
      const score = (item) => {
        const value = `${item.type} ${item.url}`.toLowerCase();
        return item.priority * 1000000 +
          (value.includes('avc1') || value.includes('h264') ? 300000 : 0) +
          (value.includes('.m3u8') || value.includes('mpegurl') ? 100000 : 0) -
          (value.includes('av1') || value.includes('hevc') ? 300000 : 0);
      };
      const isAllowedContentCandidate = (url) => {
        try {
          const pageHost = location.hostname.toLowerCase();
          const mediaHost = new URL(String(url), location.href).hostname.toLowerCase();
          if (pageHost.includes('xhamster')) {
            return mediaHost === 'xhamster.com' ||
              mediaHost.endsWith('.xhamster.com') ||
              mediaHost === 'xhcdn.com' || mediaHost.endsWith('.xhcdn.com') ||
              mediaHost === 'xhpingcdn.com' || mediaHost.endsWith('.xhpingcdn.com') ||
              mediaHost === 'xhmediacdn.com' || mediaHost.endsWith('.xhmediacdn.com');
          }
          return true;
        } catch (_) {
          return false;
        }
      };
      const ranked = () => candidates
        .filter((item) => !/_tpl_|\{quality\}|%7bquality%7d/i.test(item.url) &&
          isAllowedContentCandidate(item.url))
        .sort((a, b) => score(b) - score(a));
      const isSearchResultsPage = () => {
        const host = location.hostname.toLowerCase();
        return host === 'google.com' || host.startsWith('www.google.') ||
          host.includes('.google.');
      };
      const selectPlayer = event => {
        if (!event.isTrusted || isSearchResultsPage() || !(event.target instanceof Element)) return;
        const container = event.target.closest('video,[data-player],[class*="video-player"],[class*="player-container"],.video-js,.jwplayer,.plyr');
        const video = (container?.matches('video') ? container : container?.querySelector('video')) ||
          (event.type === 'pointerdown' && Array.from(document.querySelectorAll('video')).find(v => {
            const r = v.getBoundingClientRect();
            return event.clientX >= r.left && event.clientX <= r.right && event.clientY >= r.top && event.clientY <= r.bottom;
          }));
        if (!video) return;
        const rect = video.getBoundingClientRect();
        if (rect.width < 160 || rect.height < 90) return;
        if (selectedVideo !== video || selectedPlayers.get(video) !== location.href) candidates.length = 0;
        selectedVideo = video;
        selectedPlayers.set(video, location.href);
        deliver({kind:'lets-cook-player-selected', title: document.title, poster: video.poster || document.querySelector('meta[property="og:image"]')?.content || ''});
        [0, 250, 1000, 3000].forEach(delay => setTimeout(() => report(video), delay));
      };
      document.addEventListener('pointerdown', selectPlayer, true);
      document.addEventListener('keydown', event => {
        if (['Enter', ' ', 'k'].includes(event.key)) selectPlayer(event);
      }, true);
      const rememberPageSources = () => {
        selectedVideo.querySelectorAll('source[src]').forEach((node) =>
          remember(node.currentSrc || node.src, node.type || '', 220));
        // Match the Android provider adapter: many sites keep the real CDN
        // rendition table in inline player JSON while the <video> element is
        // a blob URL or a download/consent endpoint.
        document.querySelectorAll('script').forEach((script) => {
          const value = script.textContent || '';
          if (value.length > 2000000) return;
          const mediaPattern = /https:\/\/[^"'\s<>{}]+?(?:\.m3u8|\.mp4)(?:\?[^"'\s<>{}]*)?/gi;
          for (const match of value.matchAll(mediaPattern)) {
            const url = match[0]
              .replaceAll('\\u002F', '/')
              .replaceAll('\\/', '/')
              .replaceAll('&amp;', '&');
            remember(url, '', 40);
          }
          const contentPattern = /video_(?:alt_)?url[0-9]*[ \t]*[:=][ \t]*['"](https:[/][/][^'"]+)['"]/gi;
          for (const match of value.matchAll(contentPattern)) {
            const url = match[1]
              .replaceAll('\\u002F', '/')
              .replaceAll('\\/', '/')
              .replaceAll('&amp;', '&');
            remember(url, '', 180);
          }
        });
      };
      try {
        new PerformanceObserver((list) => {
          if (selectedVideo && selectedPlayers.get(selectedVideo) === location.href) {
            list.getEntries().forEach((entry) => remember(entry.name));
          }
        }).observe({type: 'resource'});
      } catch (_) {}
      const originalFetch = window.fetch;
      if (originalFetch) window.fetch = function(input) {
        if (selectedVideo && selectedPlayers.get(selectedVideo) === location.href) remember(typeof input === 'string' ? input : input?.url);
        return originalFetch.apply(this, arguments);
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (selectedVideo && selectedPlayers.get(selectedVideo) === location.href) remember(url);
        return originalOpen.apply(this, arguments);
      };
      const report = (video) => {
        // Landing-page autoplay and search previews are not selections. Only
        // capture a stream immediately after the user interacted with the
        // page/player, as the Android Web adapter does.
        if (isSearchResultsPage() || selectedVideo !== video || selectedPlayers.get(video) !== location.href) return;
        rememberPageSources();
        remember(video.currentSrc || video.src, video.getAttribute('type') || '', 250);
        video.querySelectorAll('source[src]').forEach((source) => remember(source.src, source.type, 220));
        const ordered = ranked();
        const chosen = ordered[0];
        if (!chosen) return;
        let poster = video.poster || document.querySelector('meta[property="og:image"]')?.content || '';
        try { if (poster) poster = new URL(poster, location.href).href; } catch (_) {}
        deliver({
          kind: 'lets-cook-media',
          url: chosen.url,
          type: chosen.type,
          title: document.querySelector('meta[property="og:title"]')?.content || document.title || '',
          poster,
          pageUrl: location.href,
          candidates: ordered.slice(0, 8).map((item) => ({
            url: item.url,
            type: item.type || ''
          }))
        });
      };
      const bind = (video) => {
        if (video.dataset.letsCookWindowsBound) return;
        video.dataset.letsCookWindowsBound = 'true';
        const capture = () => {
          report(video);
          [120, 350, 800, 1600, 3000].forEach((delay) => setTimeout(() => report(video), delay));
        };
        video.addEventListener('play', capture, true);
        video.addEventListener('playing', capture, true);
        video.addEventListener('progress', () => report(video), true);
      };
      const bindAll = () => document.querySelectorAll('video').forEach(bind);
      document.addEventListener('DOMContentLoaded', bindAll, {once: true});
      new MutationObserver(bindAll).observe(document, {childList: true, subtree: true});
    })();
  ''';

  static String _providerLabel(Uri uri) {
    final code = _providerFor(uri);
    return switch (code) {
      'INTERNET_ARCHIVE' => 'Internet Archive',
      'GOOGLE_DRIVE' => 'Google Drive',
      'PRIME_VIDEO' => 'Prime Video',
      _ => code.toLowerCase().replaceAll('_', ' '),
    };
  }

  static bool _isAllowedCapturedMedia(Uri? page, Uri media) {
    if (media.scheme != 'https' ||
        media.host.isEmpty ||
        media.userInfo.isNotEmpty) {
      return false;
    }
    final value = media.toString().toLowerCase();
    if (RegExp(
      r'doubleclick|googlesyndication|adservice|flirtify\.com|/vast/|preroll|video-ad',
    ).hasMatch(value)) {
      return false;
    }
    final pageHost = page?.host.toLowerCase() ?? '';
    if (!pageHost.contains('xhamster')) return true;
    final host = media.host.toLowerCase();
    return host == 'xhamster.com' ||
        host.endsWith('.xhamster.com') ||
        host == 'xhcdn.com' ||
        host.endsWith('.xhcdn.com') ||
        host == 'xhpingcdn.com' ||
        host.endsWith('.xhpingcdn.com') ||
        host == 'xhmediacdn.com' ||
        host.endsWith('.xhmediacdn.com');
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
                          _selectProvider(provider);
                        },
                ),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Text(
            'Provider sign-ins stay in this app’s browser. Web browsing starts in a separate temporary session.',
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
              onPressed: browserReady && !recoveringBrowser
                  ? () => _retryBrowser()
                  : null,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload',
            ),
            IconButton(
              onPressed: browserReady && !recoveringBrowser
                  ? () => _retryBrowser(clearCache: true)
                  : null,
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: 'Clear cached files and reload (keeps sign-ins)',
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

  Future<void> _openAnotherLink() async {
    var input = '';
    String? error;
    final url = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          void open() {
            final uri = Uri.tryParse(input.trim());
            if (uri == null ||
                uri.scheme != 'https' ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty) {
              refresh(
                () => error = 'Enter an HTTPS link with a website address.',
              );
              return;
            }
            Navigator.pop(context, uri.toString());
          }

          return AlertDialog(
            title: const Text('Open another link'),
            content: TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Website link',
                hintText: 'https://',
                errorText: error,
              ),
              onChanged: (value) => input = value,
              onSubmitted: (_) => open(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: open, child: const Text('Open')),
            ],
          );
        },
      ),
    );
    if (mounted && url != null) await _navigate(url);
  }

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
              Text(
                browserReady
                    ? 'You can retry without losing your provider sign-ins.'
                    : 'Check that Microsoft Edge WebView2 Runtime is installed, then reopen Xynk.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              if (browserReady) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: recoveringBrowser
                          ? null
                          : () => _retryBrowser(),
                      child: const Text('Retry'),
                    ),
                    OutlinedButton(
                      onPressed: recoveringBrowser
                          ? null
                          : () => _retryBrowser(clearCache: true),
                      child: const Text('Clear cache and retry'),
                    ),
                    if (widget.initialProvider?.toLowerCase() == 'web')
                      TextButton(
                        onPressed: _openAnotherLink,
                        child: const Text('Open another link'),
                      ),
                  ],
                ),
              ],
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
    required this.pageUrl,
    this.candidates = const [],
  });

  final String url;
  final String sourceType;
  final String title;
  final String? poster;
  final String pageUrl;
  final List<_CapturedMediaCandidate> candidates;
}

class _CapturedMediaCandidate {
  const _CapturedMediaCandidate(this.url, this.sourceType);

  final String url;
  final String sourceType;
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
