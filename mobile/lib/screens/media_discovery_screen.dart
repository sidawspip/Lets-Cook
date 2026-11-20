import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/models.dart';
import '../services/media_resolver.dart';
import '../services/browser_recovery.dart';
import '../services/public_media_links.dart';
import '../state/watch_party_controller.dart';
import '../widgets/media_preview.dart';
import '../widgets/screen_share_confirmation.dart';

enum _DiscoverySource { youtube, web, crunchyroll }

enum _WebEngine {
  google,
  directLink,
  googleDrive,
  dropbox,
  oneDrive,
  box,
  nextcloud,
  archive,
  x,
  twitch,
  vimeo,
  netflix,
  primeVideo,
}

enum _DirectCommitOrigin { pastedUrlButton, webPreviewButton }

class _ProviderPortal {
  const _ProviderPortal({
    required this.label,
    required this.home,
    this.provider = false,
    this.shareLinkOnly = false,
  });

  final String label;
  final Uri home;
  final bool provider;
  final bool shareLinkOnly;
}

class _PendingWebMedia {
  const _PendingWebMedia({
    required this.uri,
    required this.pageUri,
    required this.sourceType,
    required this.title,
    required this.siteName,
    required this.selectedAt,
    this.posterUrl,
    this.quality,
  });

  final Uri uri;
  final Uri pageUri;
  final String sourceType;
  final String title;
  final String siteName;
  final DateTime selectedAt;
  final String? posterUrl;
  final String? quality;
}

class _PendingCrunchyrollMedia {
  const _PendingCrunchyrollMedia({
    required this.uri,
    required this.title,
    this.posterUrl,
    this.nextEpisodes = const [],
  });

  final Uri uri;
  final String title;
  final String? posterUrl;
  final List<_PendingCrunchyrollMedia> nextEpisodes;
}

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
  late final TextEditingController search;
  late final WebViewController browser;
  Timer? debounce;
  Timer? webScrapeDebounce;
  _DiscoverySource? source;
  _WebEngine? webEngine;
  bool loading = false;
  bool recoveringBrowser = false;
  String? browserError;
  bool committing = false;
  bool resolvingPage = false;
  bool webPlayerPresent = false;
  bool preparingWebVideo = false;
  int webPageGeneration = 0;
  Uri? currentUri;
  String? selectedPageTitle;
  Uri? readyWebPage;
  DateTime? readyWebPageAt;
  String? webPlayIntentHost;
  DateTime? webPlayIntentAt;
  String? lastWebScrapeIdentity;
  _PendingWebMedia? pendingWebMedia;
  _PendingCrunchyrollMedia? pendingCrunchyrollMedia;
  bool ignoreInitialMediaSelection = false;

  _ProviderPortal _providerPortal(_WebEngine engine) => switch (engine) {
    _WebEngine.google => _ProviderPortal(
      label: 'Google',
      home: Uri.parse('https://www.google.com/'),
    ),
    _WebEngine.directLink => _ProviderPortal(
      label: 'Public video URL',
      home: Uri.parse('https://example.com/'),
      provider: true,
      shareLinkOnly: true,
    ),
    _WebEngine.googleDrive => _ProviderPortal(
      label: 'Google Drive',
      home: Uri.parse('https://drive.google.com/drive/u/0/my-drive'),
      provider: true,
    ),
    _WebEngine.dropbox => _ProviderPortal(
      label: 'Dropbox',
      home: Uri.parse('https://www.dropbox.com/home'),
      provider: true,
    ),
    _WebEngine.oneDrive => _ProviderPortal(
      label: 'OneDrive',
      home: Uri.parse('https://onedrive.live.com/'),
      provider: true,
    ),
    _WebEngine.box => _ProviderPortal(
      label: 'Box',
      home: Uri.parse('https://app.box.com/'),
      provider: true,
    ),
    _WebEngine.nextcloud => _ProviderPortal(
      label: 'Nextcloud',
      home: Uri.parse('https://nextcloud.com/'),
      provider: true,
      shareLinkOnly: true,
    ),
    _WebEngine.archive => _ProviderPortal(
      label: 'Internet Archive',
      home: Uri.parse('https://archive.org/details/movies'),
      provider: true,
    ),
    _WebEngine.x => _ProviderPortal(
      label: 'X',
      home: Uri.parse('https://x.com/home'),
      provider: true,
    ),
    _WebEngine.twitch => _ProviderPortal(
      label: 'Twitch',
      home: Uri.parse('https://m.twitch.tv/'),
      provider: true,
    ),
    _WebEngine.vimeo => _ProviderPortal(
      label: 'Vimeo',
      home: Uri.parse('https://vimeo.com/watch'),
      provider: true,
    ),
    _WebEngine.netflix => _ProviderPortal(
      label: 'Netflix',
      home: Uri.parse('https://www.netflix.com/browse'),
      provider: true,
    ),
    _WebEngine.primeVideo => _ProviderPortal(
      label: 'Prime Video',
      home: Uri.parse('https://www.primevideo.com/'),
      provider: true,
    ),
  };

  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: widget.initialQuery);
    browser = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F0F0F))
      ..addJavaScriptChannel(
        'YoutubeDetector',
        onMessageReceived: (message) {
          if (source != _DiscoverySource.youtube) return;
          final id = _youtubeVideoId(Uri.tryParse(message.message));
          if (id != null &&
              !(ignoreInitialMediaSelection && id == widget.initialMediaId)) {
            _chooseYoutube(id);
          }
        },
      )
      ..addJavaScriptChannel(
        'MediaDetector',
        onMessageReceived: (message) => _handleDetectedMedia(message.message),
      )
      ..addJavaScriptChannel(
        'MediaIntent',
        onMessageReceived: (message) => _handleMediaIntent(message.message),
      )
      ..addJavaScriptChannel(
        'WebSelection',
        onMessageReceived: (message) => _handleWebSelection(message.message),
      )
      ..addJavaScriptChannel(
        'CrunchyrollSelection',
        onMessageReceived: (message) =>
            _handleCrunchyrollSelection(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            webPageGeneration++;
            if (mounted) {
              setState(() {
                loading = true;
                browserError = null;
                if (source == _DiscoverySource.web) {
                  currentUri = Uri.tryParse(url);
                  resolvingPage = false;
                  readyWebPage = null;
                  readyWebPageAt = null;
                  webPlayIntentHost = null;
                  webPlayIntentAt = null;
                  pendingWebMedia = null;
                  webPlayerPresent = false;
                  preparingWebVideo = false;
                }
                if (source == _DiscoverySource.crunchyroll) {
                  pendingCrunchyrollMedia = null;
                }
              });
            }
          },
          onPageFinished: (url) async {
            final finishedUri = Uri.tryParse(url);
            if (source == _DiscoverySource.web) {
              if (!mounted ||
                  browserError != null ||
                  finishedUri == null ||
                  (currentUri != null &&
                      finishedUri.replace(fragment: '') !=
                          currentUri!.replace(fragment: ''))) {
                return;
              }
              // Publish the completed main-frame URL immediately. JavaScript
              // bridge installation can take a moment (or fail on a hostile
              // page), but that must not hide the explicit Play in room
              // action from the user.
              setState(() {
                currentUri = finishedUri;
                loading = false;
              });
            }
            if (source == _DiscoverySource.youtube) {
              await _prepareYoutubePage();
            } else if (source == _DiscoverySource.web) {
              readyWebPage = finishedUri;
              readyWebPageAt = DateTime.now();
              // Server scraping is the primary Rave-style path. Some sites
              // publish the real stream only after a trusted tap starts their
              // player, so install the complementary browser capture bridge.
              // It ignores links, autoplay previews and ads; only an armed,
              // content-sized <video> can emit a candidate for validation.
              // These scripts are idempotent and independent. Do not await
              // any platform call: some WebViews execute a timer-based
              // bridge successfully but never complete its method channel
              // response, which previously prevented the detector from ever
              // being installed.
              unawaited(_installAdCleaner());
              unawaited(_installMediaDetector());
              unawaited(_installWebNavigationBridge());
              final engine = webEngine;
              final provider = _browserProviderCode(engine);
              if (!ignoreInitialMediaSelection &&
                  engine != null &&
                  provider != null &&
                  finishedUri != null &&
                  _looksLikeSelectedProviderMedia(engine, finishedUri) &&
                  _publicLinkProvider(engine) != null) {
                await _selectCurrentWebPage();
                return;
              }
              if (finishedUri != null) {
                _scheduleRaveStyleWebScrape(finishedUri);
              }
            } else if (source == _DiscoverySource.crunchyroll) {
              await _installCrunchyrollSelectionBridge();
              await _captureCrunchyrollEpisodePage();
            }
            if (mounted) setState(() => loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            if (error.description.toUpperCase().contains('ERR_ABORTED')) return;
            final failedPage = Uri.tryParse(error.url ?? '');
            if (failedPage != null &&
                failedPage.hasAuthority &&
                currentUri != null &&
                failedPage.replace(fragment: '') !=
                    currentUri!.replace(fragment: '')) {
              return;
            }
            webScrapeDebounce?.cancel();
            setState(() {
              webPageGeneration++;
              loading = false;
              resolvingPage = false;
              preparingWebVideo = false;
              pendingWebMedia = null;
              pendingCrunchyrollMedia = null;
              readyWebPage = null;
              readyWebPageAt = null;
              browserError = browserFailureMessage(error.description);
            });
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            // Android WebView can emit an empty URL change after the main
            // frame has completed. Keep the last valid URL so the room action
            // does not disappear even though the page is visibly loaded.
            if (uri != null &&
                uri.host.isNotEmpty &&
                const {'http', 'https'}.contains(uri.scheme)) {
              currentUri = uri;
              if (source == _DiscoverySource.web && mounted) {
                setState(() {});
              }
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (source == _DiscoverySource.web && _isKnownAdUri(uri)) {
              return NavigationDecision.prevent;
            }
            if (source == _DiscoverySource.youtube) {
              if (_isYoutubeShort(uri)) {
                _showMessage(
                  'YouTube Shorts are not supported. Choose a regular video.',
                );
                return NavigationDecision.prevent;
              }
              // A normal watch URL may also carry a `list` parameter. Prefer
              // its concrete video id; only playlist-only URLs stay in the
              // browser for the user to choose an item.
              final id = _youtubeVideoId(uri);
              if (id != null) {
                if (ignoreInitialMediaSelection &&
                    id == widget.initialMediaId) {
                  return NavigationDecision.navigate;
                }
                _chooseYoutube(id);
                return NavigationDecision.prevent;
              }
              if (_isYoutubePlaylist(uri)) {
                return NavigationDecision.navigate;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    final initialProvider = widget.initialProvider?.trim().toUpperCase();
    if (initialProvider != null && initialProvider.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openInitialProvider(initialProvider);
      });
    } else if (widget.initialQuery.trim().isNotEmpty) {
      source = _DiscoverySource.youtube;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadYoutube());
    }
  }

  @override
  void dispose() {
    webPageGeneration++;
    debounce?.cancel();
    webScrapeDebounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: source == null && !committing,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && source != null && !committing) {
        await _handleDiscoveryBack();
      }
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF0A0B16),
      body: Stack(
        children: [
          const Positioned.fill(child: _DiscoveryBackdrop()),
          SafeArea(
            child: source == null
                ? _buildSourceGallery()
                : source == _DiscoverySource.youtube
                ? _buildYoutube()
                : source == _DiscoverySource.crunchyroll
                ? _buildCrunchyroll()
                : _buildWeb(),
          ),
          if (widget.viewerLoginMode && source != null && !committing)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: SafeArea(
                top: false,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xF21A1D29),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x88000000),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Use only your own provider account. Your password and cookies stay on this device.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFC8D2E2),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.verified_user_rounded),
                            label: const Text("I've signed in — continue"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (committing)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xCC070910),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 18),
                      Text(
                        'Preparing your room…',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildSourceGallery() => Column(
    children: [
      _DiscoveryHeader(
        title: "XYNK",
        onBack: () => Navigator.pop(context),
      ),
      Expanded(
        child: GridView.count(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          crossAxisCount: 2,
          childAspectRatio: 1.72,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          children: [
            _SourceCard(
              name: 'Screen sharing',
              icon: Icons.screen_share_rounded,
              accent: const Color(0xFF79F2C0),
              onTap: _startScreenSharing,
            ),
            _SourceCard(
              name: 'YouTube',
              icon: Icons.play_arrow_rounded,
              accent: const Color(0xFFFF1538),
              onTap: _openYoutube,
            ),
            _SourceCard(
              name: 'Web',
              icon: Icons.language_rounded,
              accent: const Color(0xFF53B6FF),
              onTap: _openWeb,
            ),
            _SourceCard(
              name: 'Public video URL',
              icon: Icons.link_rounded,
              accent: const Color(0xFF7DD3FC),
              onTap: () => _openProviderPortal(_WebEngine.directLink),
            ),
            _SourceCard(
              name: 'Google Drive',
              icon: Icons.cloud_rounded,
              accent: const Color(0xFF34A853),
              onTap: () => _openProviderPortal(_WebEngine.googleDrive),
            ),
            _SourceCard(
              name: 'Dropbox',
              icon: Icons.inventory_2_rounded,
              accent: const Color(0xFF3984FF),
              onTap: () => _openProviderPortal(_WebEngine.dropbox),
            ),
            _SourceCard(
              name: 'OneDrive',
              icon: Icons.cloud_queue_rounded,
              accent: const Color(0xFF0078D4),
              onTap: () => _openProviderPortal(_WebEngine.oneDrive),
            ),
            _SourceCard(
              name: 'Box',
              icon: Icons.folder_shared_rounded,
              accent: const Color(0xFF0061D5),
              onTap: () => _openProviderPortal(_WebEngine.box),
            ),
            _SourceCard(
              name: 'Nextcloud',
              icon: Icons.cloud_circle_rounded,
              accent: const Color(0xFF0082C9),
              onTap: () => _openProviderPortal(_WebEngine.nextcloud),
            ),
            _SourceCard(
              name: 'Internet Archive',
              icon: Icons.account_balance_rounded,
              accent: const Color(0xFFE9D5A1),
              onTap: () => _openProviderPortal(_WebEngine.archive),
            ),
            _SourceCard(
              name: 'X',
              icon: Icons.alternate_email_rounded,
              accent: Colors.white,
              onTap: () => _openProviderPortal(_WebEngine.x),
            ),
            _SourceCard(
              name: 'Twitch',
              icon: Icons.live_tv_rounded,
              accent: const Color(0xFF9146FF),
              onTap: () => _openProviderPortal(_WebEngine.twitch),
            ),
            _SourceCard(
              name: 'Vimeo',
              icon: Icons.video_library_rounded,
              accent: const Color(0xFF1AB7EA),
              onTap: () => _openProviderPortal(_WebEngine.vimeo),
            ),
            _SourceCard(
              name: 'History',
              icon: Icons.history_rounded,
              accent: const Color(0xFFB88CFF),
              onTap: _openHistory,
            ),
            _SourceCard(
              name: 'Like',
              icon: Icons.favorite_rounded,
              accent: const Color(0xFFFF86B7),
              onTap: _openLikes,
            ),
            _SourceCard(
              name: 'Crunchyroll',
              icon: Icons.ondemand_video_rounded,
              accent: const Color(0xFFF47521),
              onTap: () => _openInitialProvider('CRUNCHYROLL'),
            ),
            _SourceCard(
              name: 'Netflix\nDRM later',
              icon: Icons.movie_filter_rounded,
              accent: const Color(0xFFE50914),
              badge: 'DRM LATER',
            ),
            _SourceCard(
              name: 'Prime Video\nDRM later',
              icon: Icons.live_tv_rounded,
              accent: const Color(0xFF00A8E1),
              badge: 'DRM LATER',
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _startScreenSharing() async {
    try {
      if (!await confirmScreenShare(context)) return;
      await widget.controller.startScreenSharing(
        targetRoomId: widget.targetRoomId,
      );
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.voice.error ??
                exception.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Widget _buildYoutube() => Column(
    children: [
      _DiscoveryHeader(
        title: 'YouTube',
        icon: Icons.play_arrow_rounded,
        accent: const Color(0xFFFF1538),
        onBack: _handleDiscoveryBack,
        onHistory: _openHistory,
        onLike: _openLikes,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
        child: TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onChanged: _searchYoutubeWhileTyping,
          onSubmitted: (_) => _loadYoutube(),
          decoration: InputDecoration(
            hintText: 'Search YouTube',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              onPressed: _loadYoutube,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(15, 0, 15, 7),
        child: Text(
          'Tap a regular video to play it in your synchronized room.',
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ),
      Expanded(child: _browserSurface()),
    ],
  );

  Widget _buildWeb() {
    if (webEngine == null) {
      return Column(
        children: [
          _DiscoveryHeader(
            title: 'Browse the web',
            onBack: _handleDiscoveryBack,
            onHistory: _openHistory,
            onLike: _openLikes,
          ),
          const Spacer(),
          const Icon(Icons.language_rounded, size: 74, color: Colors.white70),
          const SizedBox(height: 18),
          const Text(
            'Search the web with Google',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 34),
            child: Text(
              'Web playback works only when a page exposes a public HTTPS MP4 or HLS stream.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _EngineCard(
              name: 'Google',
              letter: 'G',
              colors: const [
                Color(0xFF4285F4),
                Color(0xFFEA4335),
                Color(0xFFFBBC05),
                Color(0xFF34A853),
              ],
              onTap: () => _chooseEngine(_WebEngine.google),
            ),
          ),
          const Spacer(flex: 2),
        ],
      );
    }
    final directReady =
        currentUri != null &&
        (_isDirect(currentUri!) || _isCloudDownloadCandidate(currentUri!));
    final providerPageReady =
        currentUri != null &&
        webEngine != null &&
        _browserProviderCode(webEngine) != null &&
        _looksLikeSelectedProviderMedia(webEngine!, currentUri!);
    final portal = _providerPortal(webEngine!);
    return Column(
      children: [
        _DiscoveryHeader(
          title: portal.label,
          onBrowserRecovery: _showBrowserRecovery,
          onBack: _handleDiscoveryBack,
          onHistory: _openHistory,
          onLike: _openLikes,
        ),
        if (portal.provider)
          Container(
            width: double.infinity,
            color: const Color(0xFF111827),
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
            child: Text(
              webEngine == _WebEngine.directLink
                  ? 'No ads. Paste a public direct MP4 or HLS link. It is verified before joining a room.'
                  : portal.shareLinkOnly
                  ? 'No ads. Open ${portal.label}, copy a shared video link, and paste it below.'
                  : "Xynk adds no ads. Sign in with your own account if needed, open a video, then add that page to the room. "
                        'Every viewer uses their own provider access.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB9C7DB),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        // Google already provides its own search field inside
        // the page. Keep our URL input only for provider/share-link flows that
        // cannot reliably expose a native picker in the embedded browser.
        if (portal.provider)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
            child: TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchWeb(),
              decoration: InputDecoration(
                hintText:
                    'Paste an official ${portal.label} video or shared-file URL',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  onPressed: _searchWeb,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
          ),
        Expanded(
          child: portal.shareLinkOnly && currentUri == null
              ? _buildShareLinkLanding(portal)
              : _browserSurface(),
        ),
        if ((resolvingPage || preparingWebVideo) && !directReady)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 9, 16, 2),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Checking the selected page for a playable video…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: directReady || providerPageReady
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: directReady
                          ? _chooseDirect
                          : _selectCurrentWebPage,
                      icon: const Icon(Icons.add_to_queue_rounded),
                      label: Text(
                        widget.targetRoomId == null
                            ? 'Play in room'
                            : 'Add to room queue',
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildCrunchyroll() => Column(
    children: [
      _DiscoveryHeader(
        title: 'Crunchyroll',
        icon: Icons.ondemand_video_rounded,
        accent: const Color(0xFFF47521),
        onBack: _handleDiscoveryBack,
        onHistory: _openHistory,
        onLike: _openLikes,
      ),
      Container(
        width: double.infinity,
        color: const Color(0xFF24170F),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
        child: const Text(
          'BETA · Sign in with your own Crunchyroll account. Xynk uses provider cookies and licence responses on this device for playback; they are not sent to Xynk rooms.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFFFC49A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(child: _browserSurface()),
    ],
  );

  Future<void> _showBrowserRecovery() async {
    final clearCache = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Reload page'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_rounded),
              title: const Text('Clear cached files and reload'),
              subtitle: const Text('Your provider sign-ins are kept.'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (clearCache != null && mounted) {
      await _recoverBrowser(clearCache: clearCache);
    }
  }

  Future<void> _recoverBrowser({bool clearCache = false}) async {
    if (recoveringBrowser || committing) return;
    final page = currentUri;
    if (page == null || !{'http', 'https'}.contains(page.scheme)) return;
    webScrapeDebounce?.cancel();
    setState(() {
      recoveringBrowser = true;
      webPageGeneration++;
      browserError = null;
      pendingWebMedia = null;
      pendingCrunchyrollMedia = null;
      resolvingPage = false;
      preparingWebVideo = false;
      readyWebPage = null;
      readyWebPageAt = null;
      webPlayIntentHost = null;
      webPlayIntentAt = null;
      lastWebScrapeIdentity = null;
    });
    final recoveryGeneration = webPageGeneration;
    try {
      if (clearCache) await browser.clearCache();
      if (!mounted ||
          currentUri != page ||
          webPageGeneration != recoveryGeneration) {
        return;
      }
      await browser.loadRequest(page);
    } catch (_) {
      if (mounted &&
          currentUri == page &&
          webPageGeneration == recoveryGeneration) {
        setState(
          () => browserError = 'The page could not be reloaded. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => recoveringBrowser = false);
    }
  }

  Widget _browserSurface() => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
    child: Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: browser)),
        if (loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (browserError case final String message)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF0D0D12),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: recoveringBrowser ? null : _recoverBrowser,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                      TextButton(
                        onPressed: recoveringBrowser
                            ? null
                            : () => _recoverBrowser(clearCache: true),
                        child: const Text('Clear cached files and retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (pendingWebMedia case final _PendingWebMedia media)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _WebMediaPreview(
              media: media,
              addingToRoom: widget.targetRoomId != null,
              onConfirm: _confirmPendingWebMedia,
              onDismiss: _dismissPendingWebMedia,
            ),
          ),
        if (pendingCrunchyrollMedia case final _PendingCrunchyrollMedia media)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _crunchyrollPreview(media),
          ),
      ],
    ),
  );

  void _openHistory() => _showMediaLibrary(
    title: 'History',
    items: widget.controller.history,
    accent: const Color(0xFFB88CFF),
  );

  void _openLikes() => _showMediaLibrary(
    title: 'Like',
    items: widget.controller.likedVideos,
    accent: const Color(0xFFFF86B7),
  );

  Future<void> _showMediaLibrary({
    required String title,
    required List<ViewingActivity> items,
    required Color accent,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (pageContext) => Scaffold(
        backgroundColor: const Color(0xFF12141D),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(pageContext),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Icon(
                      title == 'Like'
                          ? Icons.favorite_rounded
                          : Icons.history_rounded,
                      color: accent,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          title == 'Like'
                              ? 'No liked videos yet.'
                              : 'No watch history yet.',
                          style: const TextStyle(color: Colors.white60),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.18,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: items.length,
                        itemBuilder: (_, index) {
                          final item = items[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              Navigator.pop(pageContext);
                              await _playLibraryItem(item);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  MediaPreview(
                                    mediaId: item.mediaId,
                                    provider: item.provider,
                                    thumbnailUrl: item.thumbnailUrl,
                                    contentLabel: item.title,
                                    sensitive: item.sensitive,
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        9,
                                        22,
                                        9,
                                        8,
                                      ),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Color(0xE6000000),
                                          ],
                                        ),
                                      ),
                                      child: Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _playLibraryItem(ViewingActivity item) async {
    setState(() => committing = true);
    await widget.controller.selectViewingActivity(
      item,
      targetRoomId: widget.targetRoomId,
    );
    if (!mounted) return;
    if (widget.controller.error == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => committing = false);
    _showMessage(widget.controller.error!);
  }

  Widget _crunchyrollPreview(_PendingCrunchyrollMedia media) => Material(
    color: const Color(0xF21A1411),
    elevation: 12,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 112,
              height: 72,
              child: MediaPreview(
                mediaId: media.uri.toString(),
                provider: 'CRUNCHYROLL',
                thumbnailUrl: media.posterUrl,
                contentLabel: media.title,
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
                  'SELECTED EPISODE',
                  style: TextStyle(
                    color: Color(0xFFF47521),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  media.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (media.nextEpisodes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${media.nextEpisodes.length} later episode${media.nextEpisodes.length == 1 ? '' : 's'} will appear as suggestions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: committing
                            ? null
                            : () => _confirmCrunchyrollMedia(media),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          widget.targetRoomId == null
                              ? 'Play in room'
                              : 'Add to room',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Choose another episode',
                      onPressed: () =>
                          setState(() => pendingCrunchyrollMedia = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void _openYoutube() {
    setState(() => source = _DiscoverySource.youtube);
    _loadYoutube();
  }

  Future<void> _openInitialProvider(String provider) async {
    final mediaId = widget.initialMediaId?.trim() ?? '';
    final sourceUrl = widget.initialSourceUrl?.trim() ?? '';
    if (provider == 'YOUTUBE') {
      setState(() => source = _DiscoverySource.youtube);
      if (mediaId.isEmpty) {
        await _loadYoutube();
        return;
      }
      ignoreInitialMediaSelection = true;
      await browser.loadRequest(
        Uri.https('m.youtube.com', '/watch', {'v': mediaId}),
      );
      return;
    }

    if (provider == 'CRUNCHYROLL') {
      setState(() => source = _DiscoverySource.crunchyroll);
      final uri = Uri.tryParse(sourceUrl.isNotEmpty ? sourceUrl : mediaId);
      await browser.loadRequest(
        uri != null && const {'http', 'https'}.contains(uri.scheme)
            ? uri
            : Uri.parse('https://www.crunchyroll.com/'),
      );
      return;
    }

    final portalEngine = switch (provider) {
      'GOOGLE_DRIVE' ||
      'GOOGLE DRIVE' ||
      'DRIVE.GOOGLE.COM' => _WebEngine.googleDrive,
      'DROPBOX' || 'DROPBOX.COM' => _WebEngine.dropbox,
      'ONEDRIVE' || 'ONEDRIVE.LIVE.COM' || '1DRV.MS' => _WebEngine.oneDrive,
      'BOX' || 'BOX.COM' || 'APP.BOX.COM' => _WebEngine.box,
      'NEXTCLOUD' => _WebEngine.nextcloud,
      'INTERNET_ARCHIVE' ||
      'INTERNET ARCHIVE' ||
      'ARCHIVE.ORG' => _WebEngine.archive,
      'X' || 'X.COM' || 'TWITTER.COM' => _WebEngine.x,
      'TWITCH' || 'TWITCH.TV' => _WebEngine.twitch,
      'VIMEO' || 'VIMEO.COM' => _WebEngine.vimeo,
      'NETFLIX' || 'NETFLIX.COM' => _WebEngine.netflix,
      'PRIME_VIDEO' ||
      'PRIME VIDEO' ||
      'PRIMEVIDEO.COM' => _WebEngine.primeVideo,
      _ => null,
    };
    if (portalEngine != null) {
      _openProviderPortal(portalEngine);
      final uri = Uri.tryParse(sourceUrl.isNotEmpty ? sourceUrl : mediaId);
      if (uri != null && uri.scheme == 'https') {
        search.text = uri.toString();
        await browser.loadRequest(uri);
      }
      return;
    }

    setState(() {
      source = _DiscoverySource.web;
      webEngine = _WebEngine.google;
    });
    final uri = Uri.tryParse(sourceUrl.isNotEmpty ? sourceUrl : mediaId);
    if (uri != null && const {'http', 'https'}.contains(uri.scheme)) {
      search.text = uri.toString();
      await browser.loadRequest(uri);
    } else {
      _searchWeb();
    }
  }

  void _openWeb() {
    FocusScope.of(context).unfocus();
    setState(() {
      source = _DiscoverySource.web;
      webEngine = _WebEngine.google;
      currentUri = null;
      selectedPageTitle = null;
      resolvingPage = false;
    });
    browser.loadRequest(_providerPortal(_WebEngine.google).home);
  }

  void _openProviderPortal(_WebEngine engine) {
    FocusScope.of(context).unfocus();
    final portal = _providerPortal(engine);
    setState(() {
      source = _DiscoverySource.web;
      webEngine = engine;
      currentUri = null;
      selectedPageTitle = null;
      resolvingPage = false;
      browserError = null;
      pendingWebMedia = null;
      webPlayerPresent = false;
      preparingWebVideo = false;
      search.clear();
    });
    if (!portal.shareLinkOnly) browser.loadRequest(portal.home);
  }

  Widget _buildShareLinkLanding(_ProviderPortal portal) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            portal.label == 'Public video URL'
                ? Icons.link_rounded
                : portal.label == 'Dropbox'
                ? Icons.inventory_2_rounded
                : Icons.cloud_rounded,
            size: 76,
            color: portal.label == 'Public video URL'
                ? const Color(0xFF7DD3FC)
                : portal.label == 'Dropbox'
                ? const Color(0xFF3984FF)
                : const Color(0xFF34A853),
          ),
          const SizedBox(height: 18),
          Text(
            portal.label == 'Public video URL'
                ? 'Add a public video'
                : 'Choose your video in ${portal.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            portal.label == 'Public video URL'
                ? 'Paste a public HTTPS .mp4 or .m3u8 address above. The link is checked before it is added to a room.'
                : 'Create a viewable shared link, copy it, return here, and paste it above. '
                      'Xynk stores the video reference—not your cloud password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, height: 1.45),
          ),
          const SizedBox(height: 22),
          if (portal.label != 'Public video URL')
            OutlinedButton.icon(
              onPressed: () =>
                  launchUrl(portal.home, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('Open ${portal.label}'),
            ),
        ],
      ),
    ),
  );

  Future<void> _installCrunchyrollSelectionBridge() async {
    try {
      await browser.runJavaScript(r'''
        (() => {
          if (window.__letsCookCrunchyrollReady) return;
          window.__letsCookCrunchyrollReady = true;
          document.addEventListener('click', (event) => {
            const anchor = event.target && event.target.closest
              ? event.target.closest('a[href*="/watch/"]')
              : null;
            if (!anchor) return;
            const url = new URL(anchor.href, location.href);
            if (!url.hostname.endsWith('crunchyroll.com') || !url.pathname.includes('/watch/')) return;
            const describe = (item) => {
              const card = item.closest('article, li, section, div');
              const image = (card && card.querySelector('img')) || item.querySelector('img');
              const episodeUrl = new URL(item.href, location.href);
              const slug = episodeUrl.pathname.split('/').filter(Boolean)[2] || '';
              const episodeTitle = slug.split('-').filter(Boolean)
                .map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
              const label = String(
                item.getAttribute('aria-label') || item.title ||
                (card && card.querySelector('h1,h2,h3,h4,[class*="title"]')?.textContent) ||
                item.textContent || document.title || 'Crunchyroll episode'
              ).replace(/\s+/g, ' ').trim();
              const episodeNumber = label.match(/\b(?:Episode\s*|E)(\d+)\b/i)?.[1];
              return {
                url: episodeUrl.href,
                title: /^(?:start watching|continue(?: episode)?|up next)\b/i.test(label) && episodeTitle
                  ? (episodeNumber ? `E${episodeNumber} – ${episodeTitle}` : episodeTitle) : label,
                posterUrl: image ? (image.currentSrc || image.src || '') : ''
              };
            };
            const episodes = [];
            const seen = new Set();
            document.querySelectorAll('a[href*="/watch/"]').forEach((item) => {
              const candidate = describe(item);
              if (!seen.has(candidate.url)) {
                seen.add(candidate.url);
                episodes.push(candidate);
              }
            });
            const selected = describe(anchor);
            const selectedIndex = episodes.findIndex((item) => item.url === selected.url);
            const nextEpisodes = selectedIndex >= 0
              ? episodes.slice(selectedIndex + 1)
              : [];
            CrunchyrollSelection.postMessage(JSON.stringify({
              ...selected,
              nextEpisodes
            }));
            // Crunchyroll navigates episode links within its SPA, where
            // onPageFinished may not run. Capture the episode heading once
            // that route renders instead of keeping the button's CTA text.
            let checks = 0;
            const selectedUrl = selected.url;
            const checkEpisodeTitle = () => {
              if (location.href !== selectedUrl) {
                if (++checks < 40) setTimeout(checkEpisodeTitle, 500);
                return;
              }
              const heading = [...document.querySelectorAll('h1,h2,h3')]
                .map((item) => (item.textContent || '').replace(/\s+/g, ' ').trim())
                .find((value) => /^E\d+\s*[–—-]\s*\S/i.test(value));
              if (heading) {
                CrunchyrollSelection.postMessage(JSON.stringify({
                  url: selectedUrl,
                  title: heading,
                  posterUrl: document.querySelector('meta[property="og:image"]')?.content || selected.posterUrl,
                  nextEpisodes
                }));
              } else if (++checks < 40) {
                setTimeout(checkEpisodeTitle, 500);
              }
            };
            setTimeout(checkEpisodeTitle, 500);
          }, true);
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _captureCrunchyrollEpisodePage() async {
    try {
      await browser.runJavaScript(r'''
        (() => {
          if (!/^\/watch\/[A-Za-z0-9]+/.test(location.pathname)) return;
          const pageUrl = location.href;
          let attempts = 0;
          const capture = () => {
            if (location.href !== pageUrl) return;
            const heading = [...document.querySelectorAll('h1,h2,h3')]
              .map((item) => (item.textContent || '').replace(/\s+/g, ' ').trim())
              .find((value) => /^E\d+\s*[–—-]\s*\S/i.test(value));
            if (heading) {
              const posterUrl = document.querySelector('meta[property="og:image"]')?.content || '';
              CrunchyrollSelection.postMessage(JSON.stringify({
                url: pageUrl,
                title: heading,
                posterUrl
              }));
            } else if (++attempts < 12) {
              setTimeout(capture, 500);
            }
          };
          capture();
        })();
      ''');
    } catch (_) {}
  }

  void _handleCrunchyrollSelection(String message) {
    if (source != _DiscoverySource.crunchyroll || committing) return;
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final uri = Uri.tryParse((data['url'] as String? ?? '').trim());
      if (uri == null ||
          uri.scheme != 'https' ||
          !uri.host.toLowerCase().endsWith('crunchyroll.com') ||
          !uri.path.contains('/watch/')) {
        return;
      }
      final title = (data['title'] as String? ?? '').trim();
      final poster = (data['posterUrl'] as String? ?? '').trim();
      final nextEpisodes = <_PendingCrunchyrollMedia>[];
      for (final raw in (data['nextEpisodes'] as List<dynamic>? ?? const [])) {
        if (raw is! Map) continue;
        final nextUri = Uri.tryParse((raw['url'] as String? ?? '').trim());
        if (nextUri == null ||
            nextUri.scheme != 'https' ||
            !nextUri.host.toLowerCase().endsWith('crunchyroll.com') ||
            !nextUri.path.contains('/watch/')) {
          continue;
        }
        final nextTitle = (raw['title'] as String? ?? '').trim();
        final nextPoster = (raw['posterUrl'] as String? ?? '').trim();
        nextEpisodes.add(
          _PendingCrunchyrollMedia(
            uri: nextUri,
            title: nextTitle.isEmpty ? 'Crunchyroll episode' : nextTitle,
            posterUrl: nextPoster.isEmpty ? null : nextPoster,
          ),
        );
      }
      setState(() {
        pendingCrunchyrollMedia = _PendingCrunchyrollMedia(
          uri: uri,
          title: title.isEmpty ? 'Crunchyroll episode' : title,
          posterUrl: poster.isEmpty ? null : poster,
          nextEpisodes: nextEpisodes,
        );
      });
    } catch (_) {}
  }

  Future<void> _confirmCrunchyrollMedia(_PendingCrunchyrollMedia media) async {
    if (committing) return;
    setState(() => committing = true);
    await widget.controller.selectProviderMedia(
      provider: 'CRUNCHYROLL',
      mediaId: media.uri.toString(),
      title: media.title,
      thumbnailUrl: media.posterUrl,
      targetRoomId: widget.targetRoomId,
      followingMedia: media.nextEpisodes
          .map(
            (episode) => (
              mediaId: episode.uri.toString(),
              title: episode.title,
              thumbnailUrl: episode.posterUrl,
            ),
          )
          .toList(),
    );
    if (!mounted) return;
    if (widget.controller.error != null) {
      setState(() => committing = false);
      _showMessage(widget.controller.error!);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  void _backToSources() {
    webPageGeneration++;
    webPlayerPresent = false;
    preparingWebVideo = false;
    FocusScope.of(context).unfocus();
    setState(() {
      source = null;
      webEngine = null;
      currentUri = null;
      selectedPageTitle = null;
      resolvingPage = false;
      loading = false;
    });
  }

  Future<void> _handleDiscoveryBack() async {
    if (await browser.canGoBack()) {
      await browser.goBack();
      if (source == _DiscoverySource.web) {
        // Ad and failed navigations often leave one or more empty history
        // entries. Skip those so one Back action returns to visible content.
        for (var attempt = 0; attempt < 2; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          final url = await browser.currentUrl();
          final uri = Uri.tryParse(url ?? '');
          if (uri != null &&
              uri.host.isNotEmpty &&
              uri.scheme.startsWith('http') &&
              !_isKnownAdUri(uri)) {
            break;
          }
          if (!await browser.canGoBack()) break;
          await browser.goBack();
        }
      }
      return;
    }
    if (source == _DiscoverySource.web && webEngine != null) {
      _backToSources();
      return;
    }
    _backToSources();
  }

  void _searchYoutubeWhileTyping(String value) {
    debounce?.cancel();
    if (value.trim().length < 2) return;
    debounce = Timer(const Duration(milliseconds: 550), _loadYoutube);
  }

  Future<void> _loadYoutube() => browser.loadRequest(
    search.text.trim().isEmpty
        ? Uri.parse('https://m.youtube.com/')
        : Uri.https('m.youtube.com', '/results', {
            'search_query': search.text.trim(),
          }),
  );
  void _chooseEngine(_WebEngine engine) {
    setState(() {
      webEngine = engine;
      currentUri = null;
      selectedPageTitle = null;
      resolvingPage = false;
    });
    _searchWeb();
  }

  void _searchWeb() {
    FocusScope.of(context).unfocus();
    final value = search.text.trim();
    var uri = Uri.tryParse(value);
    if (uri?.scheme == 'https') {
      uri = _normalizedProviderVideoUri(uri!, webEngine);
      search.text = uri.toString();
      browser.loadRequest(uri);
      return;
    }
    final engine = webEngine ?? _WebEngine.google;
    final portal = _providerPortal(engine);
    if (portal.provider) {
      browser.loadRequest(portal.home);
      return;
    }
    browser.loadRequest(Uri.https('www.google.com', '/search', {'q': value}));
  }

  Uri _normalizedProviderVideoUri(Uri uri, _WebEngine? engine) {
    final provider = _publicLinkProvider(engine);
    return provider == null ? uri : normalizePublicMediaLink(uri, provider);
  }

  PublicMediaLinkProvider? _publicLinkProvider(_WebEngine? engine) =>
      switch (engine) {
        _WebEngine.googleDrive => PublicMediaLinkProvider.googleDrive,
        _WebEngine.dropbox => PublicMediaLinkProvider.dropbox,
        _WebEngine.oneDrive => PublicMediaLinkProvider.oneDrive,
        _WebEngine.box => PublicMediaLinkProvider.box,
        _WebEngine.nextcloud => PublicMediaLinkProvider.nextcloud,
        _ => null,
      };

  bool _isCloudDownloadCandidate(Uri uri) {
    final provider = _publicLinkProvider(webEngine);
    return provider != null && isPublicMediaDownloadCandidate(uri, provider);
  }

  void _handleWebSelection(String message) {
    if (source != _DiscoverySource.web || committing) return;
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final uri = Uri.tryParse((data['url'] as String? ?? '').trim());
      if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) return;
      final changed = currentUri != uri;
      setState(() {
        if (changed) {
          // Same-document navigation does not call onPageStarted. Give it a
          // new generation so an older scrape cannot publish a stale card.
          webPageGeneration++;
          resolvingPage = false;
          pendingWebMedia = null;
        }
        currentUri = uri;
        readyWebPage = uri;
        readyWebPageAt = DateTime.now();
        selectedPageTitle = (data['title'] as String? ?? '').trim();
      });
      _scheduleRaveStyleWebScrape(uri);
    } catch (_) {}
  }

  String _webScrapeIdentity(Uri uri) => uri
      .replace(query: '', fragment: '')
      .toString()
      .replaceFirst(RegExp(r'/$'), '');

  bool _isRaveStyleWebScrapeCandidate(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final isGoogle =
        host == 'google.com' ||
        host.startsWith('www.google.') ||
        host.contains('.google.');
    if (isGoogle || path == '/') return false;

    final home = webEngine == null ? null : _providerPortal(webEngine!).home;
    if (home != null && _webScrapeIdentity(home) == _webScrapeIdentity(uri)) {
      return false;
    }
    return true;
  }

  void _scheduleRaveStyleWebScrape(Uri uri) {
    // Generic Web waits for the selected site's player to emit MediaIntent
    // or MediaDetector. A page can contain previews and multiple videos.
    if (webEngine == _WebEngine.google || webEngine == null) return;
    if (!_isRaveStyleWebScrapeCandidate(uri) || committing) return;
    final identity = _webScrapeIdentity(uri);
    if (identity == lastWebScrapeIdentity &&
        (resolvingPage || pendingWebMedia != null)) {
      return;
    }
    lastWebScrapeIdentity = identity;
    webScrapeDebounce?.cancel();
    webScrapeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || source != _DiscoverySource.web || currentUri != uri) {
        return;
      }
      unawaited(_resolveSelectedWebPage(uri, showFailure: false));
    });
  }

  void _handleMediaIntent(String message) {
    if (source != _DiscoverySource.web || loading) return;
    final iframe = message.startsWith('iframe:');
    final intentPage = Uri.tryParse(
      (iframe ? message.substring(6) : message).trim(),
    );
    final readyPage = readyWebPage;
    final readyAt = readyWebPageAt;
    if (intentPage == null ||
        readyPage == null ||
        readyAt == null ||
        intentPage.host.toLowerCase() != readyPage.host.toLowerCase()) {
      return;
    }
    webPlayIntentHost = intentPage.host.toLowerCase();
    webPlayIntentAt = DateTime.now();
    if (webEngine == _WebEngine.google || webEngine == null) {
      // A page-wide scrape can select a different video than the one tapped.
      // Prefer the armed element; reserve page resolution for iframe players
      // whose media cannot be observed from the parent document.
      if (!iframe) return;
    }
    // The JavaScript bridge emits this only for a trusted interaction inside
    // a content-sized player. This is the Rave-style scrape boundary: page
    // navigation alone does nothing; opening/playing the real player starts
    // normalization and validation while MediaDetector captures local URLs.
    final engine = webEngine;
    final provider = _browserProviderCode(engine);
    if (engine != null &&
        provider != null &&
        _looksLikeSelectedProviderMedia(engine, intentPage)) {
      unawaited(_commitProviderPage(intentPage, provider));
      return;
    }
    unawaited(_resolveSelectedWebPage(intentPage, showFailure: false));
  }

  // Observe document readiness independently of page-finished: third-party
  // resources can keep that callback waiting after the player is usable. This
  // observer only marks the page as player-capable. It must never resolve or
  // queue media until the user actually clicks/plays that player.
  // Legacy DOM detector retained for compatibility diagnostics; the active
  // Web flow is URL change -> centralized resolver.
  // ignore: unused_element
  Future<void> _waitForWebPlayer(int generation) async {
    for (var tick = 0; tick < 90; tick++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted ||
          generation != webPageGeneration ||
          source != _DiscoverySource.web ||
          committing ||
          pendingWebMedia != null) {
        return;
      }
      try {
        final raw = await browser.runJavaScriptReturningResult('''
          (() => {
            const host = location.hostname.toLowerCase();
            if (document.readyState === 'loading' ||
                host === 'google.com' || host.startsWith('www.google.') ||
                host.includes('.google.')) return '';
            const nodes = document.querySelectorAll(
              'video, [data-player], [class*="video-player"], [class*="player-container"], iframe[src*="/embed/"]'
            );
            const present = Array.from(nodes).some(node => {
              const rect = node.getBoundingClientRect();
              // Small autoplaying profile/search previews are discovery
              // tiles, not the page's selected player. Requiring a content-
              // sized surface prevents false Play-in-room cards there while
              // still accepting ordinary mobile video players.
              return rect.width >= 240 && rect.height >= 135 &&
                !node.closest('.ad, [class*="advert"], [class*="preroll"], [class*="ima-ad"], [data-ad]');
            });
            return present ? location.href : '';
          })();
        ''');
        var page = raw.toString();
        if (page.startsWith('"')) page = jsonDecode(page) as String;
        if (!mounted || generation != webPageGeneration) return;
        final uri = Uri.tryParse(page);
        if (uri == null || uri.scheme != 'https' || uri != currentUri) {
          if (preparingWebVideo || webPlayerPresent) {
            setState(() {
              preparingWebVideo = false;
              webPlayerPresent = false;
            });
          }
          continue;
        }
        if (!webPlayerPresent) {
          setState(() {
            webPlayerPresent = true;
            preparingWebVideo = false;
            loading = false;
          });
        }
        // Page readiness is stable identity only. MediaIntent (a trusted user
        // click/play) or MediaDetector (the playing element's concrete stream)
        // performs the single normalization/validation action.
        readyWebPage = uri;
        readyWebPageAt ??= DateTime.now();
      } catch (_) {
        // The document may be replaced during a redirect; observe again.
      }
    }
    if (mounted && generation == webPageGeneration) {
      setState(() => preparingWebVideo = false);
    }
  }

  Future<void> _selectCurrentWebPage() async {
    final pageUri = currentUri;
    if (pageUri == null || pageUri.scheme != 'https') {
      _showMessage('Open the video page first.');
      return;
    }
    final publicLinkProvider = _publicLinkProvider(webEngine);
    if (publicLinkProvider != null) {
      final publicMediaUri = normalizePublicMediaLink(
        pageUri,
        publicLinkProvider,
      );
      if (publicMediaUri != pageUri &&
          isPublicMediaDownloadCandidate(publicMediaUri, publicLinkProvider)) {
        final sourceType = publicMediaUri.path.toLowerCase().endsWith('.m3u8')
            ? 'DIRECT_HLS'
            : 'DIRECT_MP4';
        if (mounted) setState(() => resolvingPage = true);
        final playable = await probeDirectMedia(
          publicMediaUri,
          sourceType: sourceType,
        );
        if (!mounted) return;
        setState(() => resolvingPage = false);
        if (!playable) {
          _showMessage(
            'This file is still private or is not a playable video. Share it as anyone-with-the-link, then try again.',
          );
          return;
        }
        final label = _providerPortal(webEngine!).label;
        _showPendingWebMedia(
          _PendingWebMedia(
            uri: publicMediaUri,
            pageUri: pageUri,
            sourceType: sourceType,
            title: selectedPageTitle?.trim().isNotEmpty == true
                ? selectedPageTitle!.trim()
                : '$label video',
            siteName: label,
            selectedAt: DateTime.now(),
          ),
        );
        return;
      }
    }
    final browserProvider = _browserProviderCode(webEngine);
    if (browserProvider != null &&
        _looksLikeSelectedProviderMedia(webEngine!, pageUri)) {
      await _commitProviderPage(pageUri, browserProvider);
      return;
    }
    webPlayIntentHost = pageUri.host.toLowerCase();
    webPlayIntentAt = DateTime.now();
    await _resolveSelectedWebPage(pageUri, showFailure: true);
  }

  String? _browserProviderCode(_WebEngine? engine) => switch (engine) {
    _WebEngine.googleDrive => 'GOOGLE_DRIVE',
    _WebEngine.dropbox => 'DROPBOX',
    _WebEngine.oneDrive => 'ONEDRIVE',
    _WebEngine.box => 'BOX',
    _WebEngine.nextcloud => 'NEXTCLOUD',
    _WebEngine.archive => 'INTERNET_ARCHIVE',
    _WebEngine.x => 'X',
    _WebEngine.twitch => 'TWITCH',
    _WebEngine.vimeo => 'VIMEO',
    _WebEngine.netflix => 'NETFLIX',
    _WebEngine.primeVideo => 'PRIME_VIDEO',
    _ => null,
  };

  bool _looksLikeSelectedProviderMedia(_WebEngine engine, Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    bool hostIs(String value) => host == value || host.endsWith('.$value');
    return switch (engine) {
      _WebEngine.googleDrive =>
        hostIs('drive.google.com') && path.contains('/file/'),
      _WebEngine.dropbox =>
        hostIs('dropbox.com') &&
            (path.contains('/s/') ||
                path.contains('/scl/') ||
                path.contains('/preview/')),
      _WebEngine.oneDrive =>
        hostIs('1drv.ms') ||
            (hostIs('onedrive.live.com') &&
                (uri.queryParameters.containsKey('id') ||
                    uri.queryParameters.containsKey('resid'))),
      _WebEngine.box => hostIs('box.com') && path.contains('/file/'),
      _WebEngine.nextcloud => path.length > 1,
      _WebEngine.archive =>
        hostIs('archive.org') &&
            path.contains('/details/') &&
            path != '/details/movies',
      _WebEngine.x =>
        (hostIs('x.com') || hostIs('twitter.com')) && path.contains('/status/'),
      _WebEngine.twitch =>
        hostIs('twitch.tv') &&
            (path.contains('/videos/') ||
                (path.length > 1 && !path.startsWith('/directory'))),
      _WebEngine.vimeo =>
        hostIs('vimeo.com') && RegExp(r'/(?:video/)?\d+').hasMatch(path),
      _WebEngine.netflix => hostIs('netflix.com') && path.contains('/watch/'),
      _WebEngine.primeVideo =>
        (hostIs('primevideo.com') || hostIs('amazon.com')) &&
            path.contains('/detail/'),
      _ => false,
    };
  }

  Future<void> _commitProviderPage(Uri uri, String provider) async {
    if (committing) return;
    final portal = _providerPortal(webEngine!);
    final title = selectedPageTitle?.trim();
    setState(() => committing = true);
    final thumbnailUrl = await _readPageThumbnail();
    if (!mounted) return;
    await widget.controller.selectProviderMedia(
      provider: provider,
      mediaId: uri.toString(),
      title: title?.isNotEmpty == true ? title! : '${portal.label} video',
      thumbnailUrl: thumbnailUrl,
      targetRoomId: widget.targetRoomId,
    );
    if (!mounted) return;
    final succeeded = widget.targetRoomId == null
        ? widget.controller.activeRoom != null
        : widget.controller.watchState?.mediaId == uri.toString() ||
              widget.controller.queue.any(
                (item) => item.mediaId == uri.toString(),
              );
    if (succeeded) {
      Navigator.pop(context);
      return;
    }
    setState(() => committing = false);
    _showMessage(
      widget.controller.error ?? 'Could not add this provider page.',
    );
  }

  Future<String?> _readPageThumbnail() async {
    try {
      final raw = await browser.runJavaScriptReturningResult(r'''
        (() => {
          const video = document.querySelector('video');
          const image = video?.poster
            || document.querySelector('meta[property="og:image"]')?.content
            || document.querySelector('meta[name="twitter:image"]')?.content
            || document.querySelector('link[rel="image_src"]')?.href
            || '';
          try { return image ? new URL(image, location.href).href : ''; }
          catch (_) { return ''; }
        })();
      ''');
      var value = raw.toString();
      if (value.startsWith('"')) value = jsonDecode(value) as String;
      final uri = Uri.tryParse(value.trim());
      return uri?.scheme == 'https' && uri?.host.isNotEmpty == true
          ? uri.toString()
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveSelectedWebPage(
    Uri pageUri, {
    bool showFailure = false,
  }) async {
    if (resolvingPage || committing || pendingWebMedia != null) return;
    final generation = webPageGeneration;
    if (mounted) setState(() => resolvingPage = true);
    try {
      final resolved = await widget.controller.api.resolveWebMedia(
        pageUri.toString(),
      );
      if (!mounted ||
          generation != webPageGeneration ||
          currentUri != pageUri ||
          source != _DiscoverySource.web ||
          pendingWebMedia != null ||
          committing) {
        return;
      }
      final sourceUrl = (resolved['sourceUrl'] as String? ?? '').trim();
      final sourceUri = Uri.tryParse(sourceUrl);
      final sourceType = (resolved['sourceType'] as String? ?? '').trim();
      if (sourceUri == null ||
          sourceUri.scheme != 'https' ||
          hasUnresolvedMediaTemplate(sourceUri) ||
          !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(sourceType)) {
        return;
      }
      if (!await probeDirectMedia(
        sourceUri,
        sourceType: sourceType,
        sourcePage: pageUri,
      )) {
        if (showFailure) {
          _showMessage(
            'The page returned a video address, but it was not playable. '
            'Play the video on the page once so Xynk can capture the '
            'real stream.',
          );
        }
        return;
      }
      if (!mounted ||
          generation != webPageGeneration ||
          currentUri != pageUri ||
          source != _DiscoverySource.web) {
        return;
      }
      _showPendingWebMedia(
        _PendingWebMedia(
          uri: sourceUri,
          pageUri: pageUri,
          sourceType: sourceType,
          title: (resolved['title'] as String? ?? '').trim().isEmpty
              ? (selectedPageTitle?.trim().isNotEmpty == true
                    ? selectedPageTitle!.trim()
                    : 'Selected web video')
              : (resolved['title'] as String).trim(),
          siteName: (resolved['siteName'] as String? ?? '').trim().isEmpty
              ? pageUri.host
              : (resolved['siteName'] as String).trim(),
          selectedAt: DateTime.now(),
          posterUrl: () {
            final value = (resolved['thumbnailUrl'] as String? ?? '').trim();
            final thumbnail = Uri.tryParse(value);
            return thumbnail != null &&
                    thumbnail.scheme == 'https' &&
                    thumbnail.host.isNotEmpty
                ? thumbnail.toString()
                : null;
          }(),
        ),
      );
    } catch (_) {
      // A provider page may expose its stream only after playback starts.
      // Keep the local detector armed instead of failing the selection early.
      if (showFailure) {
        _showMessage(
          'This page did not expose a reusable stream. Play the video once '
          'and try again, or use Screen sharing.',
        );
      }
    } finally {
      if (mounted &&
          generation == webPageGeneration &&
          pendingWebMedia == null) {
        setState(() => resolvingPage = false);
      }
    }
  }

  Future<void> _installWebNavigationBridge() async {
    try {
      await browser.runJavaScript('''
        (() => {
          if (window.__letsCookNavigationReady) return;
          window.__letsCookNavigationReady = true;
          let currentUrl = location.href;
          const report = () => {
            try {
              WebSelection.postMessage(JSON.stringify({
                url: location.href,
                title: String(document.title || '').trim()
              }));
            } catch (_) {}
          };
          report();
          setInterval(() => {
            if (currentUrl === location.href) return;
            currentUrl = location.href;
            report();
          }, 100);
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _chooseYoutube(String id) async {
    if (!mounted || committing || source != _DiscoverySource.youtube) return;
    setState(() => committing = true);
    final video = VideoSuggestion(
      videoId: id,
      title: 'YouTube video',
      channelTitle: 'YouTube',
      thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    );
    await widget.controller.selectYoutubeVideo(
      video,
      targetRoomId: widget.targetRoomId,
    );
    if (!mounted) return;
    final succeeded =
        widget.controller.error == null &&
        (widget.targetRoomId != null || widget.controller.activeRoom != null);
    if (succeeded) {
      Navigator.pop(context);
      return;
    }
    setState(() => committing = false);
    _showMessage(widget.controller.error ?? 'Could not prepare this video.');
  }

  Future<void> _chooseDirect() async {
    final uri = currentUri;
    if (uri == null ||
        uri.scheme != 'https' ||
        (!_isDirect(uri) && !_isCloudDownloadCandidate(uri))) {
      _showMessage('Open a public HTTPS .mp4 or .m3u8 URL first.');
      return;
    }
    final sourceType = uri.path.toLowerCase().endsWith('.m3u8')
        ? 'DIRECT_HLS'
        : 'DIRECT_MP4';
    if (!await probeDirectMedia(uri, sourceType: sourceType)) {
      _showMessage(
        'That shared link did not return a public video file. Check that anyone with the link can view it.',
      );
      return;
    }
    await _commitDirect(
      uri,
      origin: _DirectCommitOrigin.pastedUrlButton,
      sourceType: sourceType,
    );
  }

  void _showPendingWebMedia(_PendingWebMedia media) {
    if (!mounted) return;
    setState(() {
      resolvingPage = false;
      pendingWebMedia = media;
    });
    if (_autoCommitProviderSelection(webEngine)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || committing || pendingWebMedia != media) return;
        unawaited(
          _commitDirect(
            media.uri,
            origin: _DirectCommitOrigin.webPreviewButton,
            sourceType: media.sourceType,
            title: media.title,
            siteName: media.siteName,
            thumbnailUrl: media.posterUrl,
            sourcePageUrl: media.pageUri,
          ),
        );
      });
    }
  }

  bool _autoCommitProviderSelection(_WebEngine? engine) => switch (engine) {
    null || _WebEngine.google => false,
    _WebEngine.netflix || _WebEngine.primeVideo => false,
    _ => true,
  };

  Future<void> _confirmPendingWebMedia() async {
    final media = pendingWebMedia;
    if (media == null) return;
    if (DateTime.now().difference(media.selectedAt) <
        const Duration(milliseconds: 1500)) {
      _showMessage('Video selected. Tap Play in room to confirm.');
      return;
    }
    await _commitDirect(
      media.uri,
      origin: _DirectCommitOrigin.webPreviewButton,
      sourceType: media.sourceType,
      title: media.title,
      siteName: media.siteName,
      thumbnailUrl: media.posterUrl,
      sourcePageUrl: media.pageUri,
    );
  }

  Future<void> _dismissPendingWebMedia() async {
    if (mounted) setState(() => pendingWebMedia = null);
    try {
      await browser.runJavaScript('''
        document.querySelectorAll('video[data-lets-cook-captured="true"]').forEach((video) => {
          video.dataset.letsCookCaptured = 'false';
        });
      ''');
    } catch (_) {}
  }

  Future<void> _commitDirect(
    Uri uri, {
    required _DirectCommitOrigin origin,
    required String sourceType,
    String? title,
    String? siteName,
    String? thumbnailUrl,
    Uri? sourcePageUrl,
  }) async {
    if (committing) return;
    if (origin == _DirectCommitOrigin.webPreviewButton &&
        pendingWebMedia?.uri != uri) {
      return;
    }
    setState(() => committing = true);
    final cleanTitle = title?.trim() ?? '';
    final cleanSite = siteName?.trim() ?? '';
    final synchronizedTitle = cleanTitle.isNotEmpty && cleanSite.isNotEmpty
        ? '$cleanTitle · $cleanSite'
        : cleanTitle.isNotEmpty
        ? cleanTitle
        : null;
    try {
      await widget.controller.selectDirectVideo(
        uri.toString(),
        targetRoomId: widget.targetRoomId,
        sourceType: sourceType,
        title: synchronizedTitle,
        thumbnailUrl: thumbnailUrl,
        sourcePageUrl: sourcePageUrl?.toString(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => committing = false);
      _showMessage('Could not prepare this video: $error');
      return;
    }
    if (!mounted) return;
    final succeeded =
        widget.controller.error == null &&
        (widget.targetRoomId != null || widget.controller.activeRoom != null);
    if (succeeded) {
      Navigator.pop(context);
      return;
    }
    setState(() => committing = false);
    _showMessage(widget.controller.error ?? 'Could not prepare this video.');
  }

  Future<void> _hideYoutubeShorts() async {
    try {
      await browser.runJavaScript(
        '''document.querySelectorAll('ytm-reel-shelf-renderer, ytm-shorts-lockup-view-model, [href^="/shorts/"]').forEach((n)=>{const s=n.closest('ytm-reel-shelf-renderer');(s||n).style.display='none';});''',
      );
    } catch (_) {}
  }

  Future<void> _prepareYoutubePage() async {
    await _hideYoutubeShorts();
    try {
      await browser.runJavaScript('''
        if (!window.__letsCookYoutubeReady) {
          window.__letsCookYoutubeReady = true;
          document.addEventListener('click', (event) => {
            const link = event.target && event.target.closest
              ? event.target.closest('a[href]')
              : null;
            if (!link) return;
            const url = new URL(link.href, location.href);
            if (url.hostname.endsWith('youtube.com') && url.pathname === '/playlist' && url.searchParams.get('list')) {
              return;
            }
            if (url.hostname.endsWith('youtube.com') && url.pathname === '/watch' && url.searchParams.get('v')) {
              event.preventDefault();
              event.stopPropagation();
              YoutubeDetector.postMessage(url.href);
            }
          }, true);
        }
      ''');
    } catch (_) {}
  }

  // Browser-side complement to the central scraper for sites that reveal the
  // concrete stream only after the user starts the real page player.
  Future<void> _installMediaDetector() async {
    try {
      await browser.runJavaScript('''
        (() => {
          if (window.__letsCookMediaReady) return;
          window.__letsCookMediaReady = true;
          const detectorReadyAt = Date.now();
          window.open = () => null;
          document.addEventListener('click', (event) => {
            const link = event.target && event.target.closest
              ? event.target.closest('a[target]')
              : null;
            if (link) link.target = '_self';
          }, true);
          const candidates = [];
          const isAdUrl = (url) => {
            const value = String(url || '').toLowerCase();
            return value.includes('doubleclick') ||
              value.includes('googlesyndication') ||
              value.includes('googleadservices') ||
              value.includes('adservice') ||
              value.includes('flirtify.com') ||
              value.includes('/vast/') || value.includes('vast=') ||
              value.includes('/preroll') || value.includes('preroll=') ||
              value.includes('/advert') || value.includes('video-ad');
          };
          const isMedia = (url) => {
            const value = String(url || '').toLowerCase();
            return value.startsWith('https://') &&
              (value.includes('.m3u8') || value.includes('.mp4') ||
               value.includes('mime=video') || value.includes('format=m3u8')) &&
              !value.includes('.m4s') && !value.includes('.ts?') &&
              !value.includes('.mp4.jpg') && !value.includes('/preview_') &&
              !value.includes('_preview.mp4') && !value.includes('/preview.mp4');
          };
          const qualityHeight = (url, label = '') => {
            const value = (String(label || '') + ' ' + String(url || '')).toLowerCase();
            const explicit = value.match(/(?:^|[^0-9])(2160|1440|1080|720|540|480|360|240|144)(?:p|[^0-9]|\$)/);
            if (explicit) return Number(explicit[1]);
            const dimensions = value.match(/(?:^|[^0-9])([0-9]{3,4})x([0-9]{3,4})(?:[^0-9]|\$)/);
            if (dimensions) return Math.min(Number(dimensions[1]), Number(dimensions[2]));
            return 0;
          };
          const score = (item) => {
            const value = String(item.url || '').toLowerCase();
            const hls = value.includes('.m3u8') ||
              String(item.type || '').toLowerCase().includes('mpegurl');
            const h264 = value.includes('h264') || value.includes('avc1');
            const hardCodec = value.includes('av1') || value.includes('h265') ||
              value.includes('hevc');
            // A master HLS stream can adapt through every advertised rendition.
            return Number(item.priority || 0) * 1000000 +
              (h264 ? 300000 : 0) + (hardCodec ? -300000 : 0) +
              (hls ? 100000 : 0) + qualityHeight(value, item.quality);
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
          const remember = (url, type = '', quality = '', priority = 0) => {
            if (!isMedia(url) || isAdUrl(url)) return;
            const item = {
              url: String(url), type: String(type), quality: String(quality || ''),
              priority: Number(priority || 0)
            };
            const existing = candidates.findIndex((candidate) => candidate.url === item.url);
            if (existing >= 0) {
              item.priority = Math.max(item.priority, candidates[existing].priority || 0);
              candidates.splice(existing, 1);
            }
            candidates.push(item);
            if (candidates.length > 80) candidates.shift();
          };
          const isConcrete = (item) => {
            const value = String(item?.url || '').toLowerCase();
            return !value.includes('_tpl_') &&
              !value.includes('{quality}') &&
              !value.includes('%7bquality%7d');
          };
          const rememberPageSources = () => {
            document.querySelectorAll('video source[src], video[src]').forEach((node) => {
              remember(node.currentSrc || node.src, node.type || '',
                node.getAttribute('label') || node.getAttribute('data-quality') ||
                node.getAttribute('res') || node.getAttribute('size') || '', 20);
            });
            // Many sites keep their complete rendition table in JSON/script data
            // while assigning only the initial low rendition to the video element.
            document.querySelectorAll('script').forEach((script) => {
              const text = script.textContent || '';
              if (text.length > 2000000) return;
              const mediaPattern = /https:\\/\\/[^"'\\s<>{}]+?(?:\\.m3u8|\\.mp4)(?:\\?[^"'\\s<>{}]*)?/gi;
              for (const match of text.matchAll(mediaPattern)) {
                const raw = match[0]
                  .replaceAll('\\\\u002F', '/')
                  .replaceAll('\\\\/', '/')
                  .replaceAll('&amp;', '&');
                const vicinity = text.slice(Math.max(0, match.index - 100), match.index + match[0].length + 100);
                remember(raw, '', vicinity, 10);
              }
              // Common player configurations explicitly distinguish the main
              // video renditions from VAST/pre-roll advertising.
              const contentPattern = /video_(?:alt_)?url[0-9]*[ \t]*:[ \t]*['"](https:[/][/][^'"]+)['"]/gi;
              for (const match of text.matchAll(contentPattern)) {
                const raw = match[1]
                  .replaceAll('\\\\u002F', '/')
                  .replaceAll('\\\\/', '/')
                  .replaceAll('&amp;', '&');
                remember(raw, '', raw, 100);
              }
            });
          };
          const rankedCandidates = (extra = []) => [...extra, ...candidates]
            .filter((item) => isMedia(item.url) && isConcrete(item) &&
              !isAdUrl(item.url) && isAllowedContentCandidate(item.url))
            .sort((a, b) => score(b) - score(a));
          const bestCandidate = (extra = []) => rankedCandidates(extra)[0];
          performance.getEntriesByType('resource').forEach((entry) => remember(entry.name));
          rememberPageSources();
          try {
            new PerformanceObserver((list) =>
              list.getEntries().forEach((entry) => remember(entry.name)))
              .observe({type: 'resource', buffered: true});
          } catch (_) {}
          const originalFetch = window.fetch;
          window.fetch = function(input, init) {
            remember(typeof input === 'string' ? input : input && input.url);
            return originalFetch.apply(this, arguments);
          };
          const originalOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url) {
            remember(url);
            return originalOpen.apply(this, arguments);
          };
          const wasExplicitlySelected = (video) => {
            const armedAt = Number(video.dataset.letsCookArmedAt || 0);
            const armedPage = String(video.dataset.letsCookArmedPage || '');
            return armedAt > 0 && Date.now() - armedAt < 120000 &&
              armedPage === location.href;
          };
          let lastTrustedInteractionAt = 0;
          document.addEventListener('pointerdown', (event) => {
            if (event.isTrusted) lastTrustedInteractionAt = Date.now();
          }, true);
          const isSearchResultsPage = () => {
            const host = location.hostname.toLowerCase();
            const google = host === 'google.com' || host.startsWith('www.google.') ||
              host.includes('.google.');
            // Search engines can render playable preview <video> nodes and use
            // several URL shapes. They are discovery surfaces, never sources.
            return google;
          };
          const arm = (video) => {
            video.dataset.letsCookArmedAt = String(Date.now());
            video.dataset.letsCookArmedPage = location.href;
            requestPageResolve();
          };
          let lastPageResolveAt = 0;
          const requestPageResolve = (iframe = false) => {
            if (isSearchResultsPage() || Date.now() - detectorReadyAt < 1000 ||
                Date.now() - lastTrustedInteractionAt > 2000 ||
                Date.now() - lastPageResolveAt < 1200) return;
            lastPageResolveAt = Date.now();
            try { MediaIntent.postMessage((iframe ? 'iframe:' : '') + location.href); } catch (_) {}
          };
          const visibleContentVideos = () => Array.from(document.querySelectorAll('video'))
            .filter((video) => {
              const rect = video.getBoundingClientRect();
              return rect.width >= 160 && rect.height >= 90 &&
                !video.closest('.ad, [class*="advert"], [class*="preroll"], [class*="ima-ad"], [id*="ad-container"], [data-ad]');
            });
          const armVideoAt = (x, y, target) => {
            if (isSearchResultsPage() || Date.now() - detectorReadyAt < 1000) return;
            const videos = visibleContentVideos();
            let armed = false;
            videos.forEach((video) => {
              const rect = video.getBoundingClientRect();
               if (video.paused && rect.width > 0 && rect.height > 0 &&
                  x >= rect.left && x <= rect.right &&
                  y >= rect.top && y <= rect.bottom) {
                arm(video);
                armed = true;
              }
            });
            if (armed || !target || target.closest?.('a[href]')) return;
            const hint = String(
              target.getAttribute?.('aria-label') || target.getAttribute?.('title') ||
              target.className || target.id || target.textContent || ''
            ).toLowerCase();
            const playerControl = target.closest?.(
              'button, [role="button"], video, canvas, iframe, [class*="play"], [id*="play"], [class*="player"], [class*="video"]'
            );
            if (!playerControl) return;
            const controlRect = playerControl?.getBoundingClientRect?.();
            const directPlayerSurface = playerControl.matches?.('video, iframe, canvas');
            if ((!videos.length && !directPlayerSurface && !hint.includes('play')) ||
                !controlRect || controlRect.width < 24 || controlRect.height < 24 ||
                playerControl.closest?.('.ad, [class*="advert"], [class*="preroll"], [id*="ad-container"], [data-ad]')) {
              return;
            }
            // Custom players and cross-origin iframe players may never expose
            // their inner <video> to this document. Resolving the current page
            // here invokes the same proven path as the top Play button.
            requestPageResolve();
            const primary = videos.sort((a, b) => {
              const ar = a.getBoundingClientRect();
              const br = b.getBoundingClientRect();
              return (br.width * br.height) - (ar.width * ar.height);
            })[0];
            if (primary?.paused) arm(primary);
          };
          // A click belongs to the document where the user completed the
          // action. Unlike raw pointer events it is not carried into a newly
          // navigated page, so clicking a search result cannot arm a player.
          document.addEventListener('click', (event) => {
            if (!event.isTrusted) return;
            armVideoAt(event.clientX, event.clientY, event.target);
          }, true);
          // Android's native video controls can consume click before it reaches
          // the document. Capture the same player-local intent on pointerdown;
          // search pages and taps outside a visible paused player stay ignored.
          document.addEventListener('pointerdown', (event) => {
            if (!event.isTrusted) return;
            armVideoAt(event.clientX, event.clientY, event.target);
          }, true);
          // Clicks inside a cross-origin iframe do not bubble to the parent.
          // WebView moves focus to that iframe, so use the focus transition as
          // a playback intent and resolve the containing provider page.
          window.addEventListener('blur', () => {
            setTimeout(() => {
              const frame = document.activeElement;
              if (!frame || frame.tagName !== 'IFRAME') return;
              const rect = frame.getBoundingClientRect();
              const src = String(frame.src || '').toLowerCase();
              if (rect.width < 160 || rect.height < 90 || isAdUrl(src) ||
                  frame.closest('.ad, [class*="advert"], [class*="preroll"], [id*="ad-container"], [data-ad]')) return;
              requestPageResolve(true);
            }, 0);
          }, true);
          const report = (video) => {
            // Autoplay, profile previews and landing-page hero players are not
            // selections. Only the exact player armed by a trusted user click
            // may create a room resource.
            if (isSearchResultsPage() || !wasExplicitlySelected(video)) return;
            const url = video.currentSrc || video.src || '';
            const source = video.querySelector('source[src]');
            const resolved = url || (source ? source.src : '');
            const type = video.getAttribute('type') || (source ? source.type : '') || '';
            const adContainer = video.closest(
              '.ad, [class*="advert"], [class*="preroll"], [class*="ima-ad"], [id*="ad-container"], [data-ad]'
            );
            if (adContainer || isAdUrl(resolved)) return;
            rememberPageSources();
            // The source used by the playing element is stronger evidence
            // than speculative URLs embedded in page scripts.
            remember(resolved, type, video.videoHeight ? String(video.videoHeight) : '', 250);
            const ranked = rankedCandidates();
            const chosen = ranked[0];
            if (chosen) {
              video.dataset.letsCookArmedAt = '0';
              video.dataset.letsCookArmedPage = '';
              video.dataset.letsCookCaptured = 'true';
              video.pause();
              MediaDetector.postMessage(JSON.stringify({
                url: chosen.url,
                type: chosen.type || type,
                quality: qualityHeight(chosen.url, chosen.quality),
                title: document.title || '',
                siteName: document.querySelector('meta[property="og:site_name"]')?.content || location.hostname,
                posterUrl: video.poster || document.querySelector('meta[property="og:image"]')?.content || '',
                pageUrl: location.href,
                candidates: ranked.slice(0, 3).map((item) => ({
                  url: item.url,
                  type: item.type || '',
                  quality: qualityHeight(item.url, item.quality)
                }))
              }));
              return true;
            }
            return false;
          };
          const retryReport = (video) => {
            // Several players create the HLS request only after their first
            // `playing` event. The performance observer remembers that URL,
            // but without a retry the old one-shot capture never consumed it.
            [120, 350, 800, 1600, 3000].forEach((delay) => {
              setTimeout(() => {
                if (video.dataset.letsCookCaptured !== 'true') report(video);
              }, delay);
            });
          };
          const bind = (video) => {
            if (video.dataset.letsCookBound) return;
            video.dataset.letsCookBound = 'true';
            const intercept = () => {
              if (video.dataset.letsCookCaptured === 'true') {
                video.pause();
                return;
              }
              if (!wasExplicitlySelected(video)) return;
              requestPageResolve();
              if (!report(video)) retryReport(video);
            };
            video.addEventListener('play', intercept, true);
            video.addEventListener('playing', intercept, true);
            video.addEventListener('loadedmetadata', () => report(video), true);
            video.addEventListener('progress', () => report(video), true);
          };
          document.querySelectorAll('video').forEach(bind);
          new MutationObserver(() => document.querySelectorAll('video').forEach(bind))
            .observe(document.documentElement, {childList: true, subtree: true});
          // Some provider players replace nodes or dispatch media events in a
          // way that bypasses listeners installed on the original element.
          // Poll only for an actively playing, visible content-sized video;
          // requestPageResolve is throttled and search pages are excluded.
          setInterval(() => {
            for (const video of visibleContentVideos()) {
              if (wasExplicitlySelected(video) && !video.paused &&
                  !video.ended && video.readyState >= 2) {
                // A preroll can outlast the initial retries. Consume the real
                // stream when it appears, even if the player keeps the same
                // element and emits no new play event after the ad.
                if (report(video)) break;
                requestPageResolve();
                break;
              }
            }
          }, 500);
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _installAdCleaner() async {
    try {
      await browser.runJavaScript('''
        (() => {
          if (window.__letsCookAdCleanerReady) return;
          window.__letsCookAdCleanerReady = true;
          const selectors = [
            'ins.adsbygoogle',
            'iframe[src*="doubleclick"]',
            'iframe[src*="googlesyndication"]',
            'iframe[src*="adservice"]',
            '[id^="google_ads"]',
            '[id*="ad-container"]',
            '[class~="advertisement"]',
            '[class*="advertisement-"]',
            '[class*="ad-overlay"]',
            '[class*="ad-banner"]',
            '[class*="sponsored-result"]',
            '[data-testid*="ad-result"]',
            '[data-ad]',
            '[aria-label="Sponsored"]',
            '.results--ads',
            '.result--ad',
            '.badge--ad'
          ];
          const clean = () => {
            document.querySelectorAll(selectors.join(',')).forEach((node) => node.remove());
            document.documentElement.style.overflow = '';
            if (document.body) document.body.style.overflow = '';
          };
          clean();
          new MutationObserver(clean).observe(document.documentElement, {
            childList: true,
            subtree: true
          });
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _handleDetectedMedia(String message) async {
    if (source != _DiscoverySource.web || committing) {
      return;
    }
    // A concrete stream captured while the page resolver is preparing is the
    // successful result of that preparation, not a competing event. The old
    // guard discarded exactly the MP4/HLS event that should finish the card.
    if (preparingWebVideo && mounted) {
      setState(() => preparingWebVideo = false);
    }
    final captureGeneration = webPageGeneration;
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final pageUri = Uri.tryParse((data['pageUrl'] as String? ?? '').trim());
      final readyAt = readyWebPageAt;
      final readyPage = readyWebPage;
      if (loading ||
          readyAt == null ||
          readyPage == null ||
          pageUri == null ||
          DateTime.now().difference(readyAt) < const Duration(seconds: 1) ||
          pageUri.host.toLowerCase() != readyPage.host.toLowerCase()) {
        return;
      }
      webPlayIntentHost = null;
      webPlayIntentAt = null;
      final url = (data['url'] as String? ?? '').trim();
      final type = (data['type'] as String? ?? '').toLowerCase();
      final pageTitle = (data['title'] as String? ?? '').trim();
      final siteName = (data['siteName'] as String? ?? '').trim();
      final posterUrl = (data['posterUrl'] as String? ?? '').trim();
      final quality = (data['quality'] ?? '').toString().trim();
      final effectiveTitle = pageTitle.isNotEmpty
          ? pageTitle
          : selectedPageTitle?.trim() ?? '';
      final candidateData = <Map<String, dynamic>>[
        {'url': url, 'type': type, 'quality': quality},
        ...(data['candidates'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)),
      ];
      final tested = <String>{};
      final probeCandidates = <({Uri uri, String type, String quality})>[];
      Uri? uri;
      var selectedType = type;
      var selectedQuality = quality;
      for (final candidate in candidateData) {
        final candidateUrl = (candidate['url'] ?? '').toString().trim();
        if (!tested.add(candidateUrl)) continue;
        final candidateUri = Uri.tryParse(candidateUrl);
        if (candidateUri == null ||
            candidateUri.scheme != 'https' ||
            hasUnresolvedMediaTemplate(candidateUri) ||
            _isKnownAdUri(candidateUri)) {
          continue;
        }
        final candidateType = (candidate['type'] ?? '')
            .toString()
            .toLowerCase();
        final sourceType =
            candidateType.contains('mpegurl') ||
                candidateUrl.toLowerCase().contains('.m3u8')
            ? 'DIRECT_HLS'
            : 'DIRECT_MP4';
        probeCandidates.add((
          uri: candidateUri,
          type: sourceType,
          quality: (candidate['quality'] ?? '').toString().trim(),
        ));
        if (probeCandidates.length == 3) break;
      }
      final probeResults = await Future.wait(
        probeCandidates.map(
          (candidate) async => (
            candidate: candidate,
            playable:
                isProviderOwnedBrowserMedia(
                  candidate.uri,
                  sourcePage: pageUri,
                ) ||
                await probeDirectMedia(
                  candidate.uri,
                  sourceType: candidate.type,
                  sourcePage: pageUri,
                ),
          ),
        ),
      );
      // A stream belongs to the page that selected it. Navigation while a
      // request is in flight must not publish an overlay for the old page.
      if (!mounted || captureGeneration != webPageGeneration) return;
      for (final result in probeResults) {
        if (!result.playable) continue;
        uri = result.candidate.uri;
        selectedType = result.candidate.type;
        selectedQuality = result.candidate.quality;
        break;
      }
      if (uri == null) {
        // Allow a fresh trusted player tap to retry if every transient signed
        // URL failed validation. The old captured marker permanently paused
        // the site player after a single CDN/network failure.
        unawaited(_resetMediaDetectorCapture());
      }
      if (uri == null) {
        final pageUrl = (data['pageUrl'] as String? ?? '').trim();
        if (pageUrl.startsWith('https://')) {
          try {
            final resolved = await widget.controller.api.resolveWebMedia(
              pageUrl,
            );
            if (!mounted || captureGeneration != webPageGeneration) return;
            final resolvedUrl = (resolved['sourceUrl'] as String? ?? '').trim();
            final resolvedUri = Uri.tryParse(resolvedUrl);
            final resolvedType = (resolved['sourceType'] as String? ?? '')
                .trim();
            if (resolvedUri != null &&
                resolvedUri.scheme == 'https' &&
                !hasUnresolvedMediaTemplate(resolvedUri) &&
                const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(resolvedType)) {
              final playable = await probeDirectMedia(
                resolvedUri,
                sourceType: resolvedType,
                sourcePage: pageUri,
              );
              if (!mounted || captureGeneration != webPageGeneration) return;
              if (!playable) {
                unawaited(_resetMediaDetectorCapture());
                return;
              }
              _showPendingWebMedia(
                _PendingWebMedia(
                  uri: resolvedUri,
                  pageUri: pageUri,
                  sourceType: resolvedType,
                  title:
                      (resolved['title'] as String?)?.trim().isNotEmpty == true
                      ? (resolved['title'] as String).trim()
                      : effectiveTitle,
                  siteName:
                      (resolved['siteName'] as String?)?.trim().isNotEmpty ==
                          true
                      ? (resolved['siteName'] as String).trim()
                      : siteName,
                  selectedAt: DateTime.now(),
                  posterUrl: posterUrl.isEmpty ? null : posterUrl,
                  quality: quality.isEmpty ? null : quality,
                ),
              );
              return;
            }
          } catch (error) {
            if (!mounted || captureGeneration != webPageGeneration) return;
            unawaited(_resetMediaDetectorCapture());
            if (mounted) setState(() => resolvingPage = false);
            _showMessage(error.toString());
            return;
          }
        }
        if (mounted) setState(() => resolvingPage = false);
        _showMessage(
          url.startsWith('blob:')
              ? 'This site uses a protected or browser-only stream that cannot be synchronized.'
              : 'This page does not expose a playable HTTPS video stream.',
        );
        return;
      }
      final sourceType =
          selectedType.contains('mpegurl') ||
              uri.toString().toLowerCase().contains('.m3u8')
          ? 'DIRECT_HLS'
          : 'DIRECT_MP4';
      _showPendingWebMedia(
        _PendingWebMedia(
          uri: uri,
          pageUri: pageUri,
          sourceType: sourceType,
          title: effectiveTitle.isEmpty ? 'Selected web video' : effectiveTitle,
          siteName: siteName.isEmpty ? pageUri.host : siteName,
          selectedAt: DateTime.now(),
          posterUrl: posterUrl.isEmpty ? null : posterUrl,
          quality: selectedQuality.isEmpty ? null : selectedQuality,
        ),
      );
    } catch (_) {
      if (!mounted || captureGeneration != webPageGeneration) return;
      unawaited(_resetMediaDetectorCapture());
      if (mounted) setState(() => resolvingPage = false);
      _showMessage('This page does not expose a supported video stream.');
    }
  }

  Future<void> _resetMediaDetectorCapture() async {
    try {
      await browser.runJavaScript('''
        document.querySelectorAll('video').forEach((video) => {
          video.dataset.letsCookCaptured = 'false';
          video.dataset.letsCookArmedAt = '0';
          video.dataset.letsCookArmedPage = '';
        });
      ''');
    } catch (_) {}
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static bool _isDirect(Uri uri) =>
      uri.path.toLowerCase().endsWith('.mp4') ||
      uri.path.toLowerCase().endsWith('.m3u8');
  static bool _isKnownAdUri(Uri? uri) {
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'doubleclick.net' ||
        host.endsWith('.doubleclick.net') ||
        host == 'flirtify.com' ||
        host.endsWith('.flirtify.com') ||
        host == 'googlesyndication.com' ||
        host.endsWith('.googlesyndication.com') ||
        host == 'googleadservices.com' ||
        host.endsWith('.googleadservices.com') ||
        host == 'adservice.google.com' ||
        host.endsWith('.adservice.google.com');
  }

  static bool _isYoutubeShort(Uri? uri) =>
      uri != null &&
      uri.host.toLowerCase().endsWith('youtube.com') &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'shorts';
  static bool _isYoutubePlaylist(Uri? uri) =>
      uri != null &&
      uri.host.toLowerCase().endsWith('youtube.com') &&
      uri.path == '/playlist' &&
      (uri.queryParameters['list']?.isNotEmpty ?? false);
  static String? _youtubeVideoId(Uri? uri) {
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') return uri.pathSegments.firstOrNull;
    if (host.endsWith('youtube.com') && uri.path == '/watch') {
      final id = uri.queryParameters['v'];
      return id == null || id.isEmpty ? null : id;
    }
    if (host.endsWith('youtube.com') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'embed') {
      return uri.pathSegments[1];
    }
    return null;
  }
}

class _DiscoveryHeader extends StatelessWidget {
  const _DiscoveryHeader({
    required this.title,
    required this.onBack,
    this.icon,
    this.accent,
    this.onHistory,
    this.onLike,
    this.onBrowserRecovery,
  });
  final String title;
  final VoidCallback onBack;
  final IconData? icon;
  final Color? accent;
  final VoidCallback? onHistory;
  final VoidCallback? onLike;
  final VoidCallback? onBrowserRecovery;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 14, 5),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        if (icon != null) ...[
          Container(
            width: 39,
            height: 30,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
        ),
        if (onHistory != null)
          IconButton(
            tooltip: 'History',
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded),
          ),
        if (onBrowserRecovery != null)
          IconButton(
            tooltip: 'Browser options',
            onPressed: onBrowserRecovery,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        if (onLike != null)
          IconButton(
            tooltip: 'Like',
            onPressed: onLike,
            icon: const Icon(Icons.favorite_rounded),
          ),
      ],
    ),
  );
}

class _WebMediaPreview extends StatelessWidget {
  const _WebMediaPreview({
    required this.media,
    required this.addingToRoom,
    required this.onConfirm,
    required this.onDismiss,
  });

  final _PendingWebMedia media;
  final bool addingToRoom;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 18,
    color: const Color(0xF21A1627),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x55FFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF2301C4A), Color(0xF2141B35)],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 92,
              height: 62,
              child: MediaPreview(
                mediaId: media.uri.toString(),
                provider: media.sourceType,
                thumbnailUrl: media.posterUrl,
                contentLabel: media.title,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  media.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    media.siteName,
                    if (media.quality?.isNotEmpty == true) '${media.quality}p',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        icon: Icon(
                          addingToRoom
                              ? Icons.add_to_queue_rounded
                              : Icons.play_arrow_rounded,
                          size: 19,
                        ),
                        label: Text(
                          addingToRoom ? 'Add to queue' : 'Play in room',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onDismiss,
                      tooltip: 'Dismiss preview',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.name,
    required this.icon,
    this.accent,
    this.onTap,
    this.badge,
  });
  final String name;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .92, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutBack,
    builder: (context, value, child) =>
        Transform.scale(scale: value, child: child),
    child: Material(
      color: onTap == null ? const Color(0x18FFFFFF) : const Color(0x2CFFFFFF),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                size: 39,
                color: onTap == null ? Colors.white30 : accent ?? Colors.white,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: name.length > 9 ? 14 : 17,
                        fontWeight: FontWeight.w900,
                        color: onTap == null ? Colors.white54 : Colors.white,
                      ),
                    ),
                    if (onTap == null) ...[
                      const SizedBox(height: 2),
                      Text(
                        badge ?? 'SOON',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.name,
    required this.letter,
    required this.colors,
    required this.onTap,
  });
  final String name;
  final String letter;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x32FFFFFF),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Column(
          children: [
            ShaderMask(
              shaderCallback: (bounds) =>
                  LinearGradient(colors: colors).createShader(bounds),
              child: Text(
                letter,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 58,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );
}

class _DiscoveryBackdrop extends StatelessWidget {
  const _DiscoveryBackdrop();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF692653),
          Color(0xFF392481),
          Color(0xFF104981),
          Color(0xFF151020),
        ],
        stops: [0, .33, .68, 1],
      ),
    ),
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
