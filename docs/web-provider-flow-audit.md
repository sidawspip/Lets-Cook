# Web provider flow

Rave APK reference: `com.wemesh.android` 9.0.49 (2349).
These are static decompilation findings, not proof of live Rave traffic.

## Reference path

`WebGridFragment.loadWeb` installs `web.js` after guarded navigation.
`webScrape` routes generic pages through `Priapus.processUrl` and known
providers through metadata adapters. A scrape yields a resource ID, title,
thumbnail, ordered links, request context and optional subtitles.
The thumbnail overlay resolves that resource ID before
`maybeCreateRaveOrAddToQueue` performs the central room action.
`VideoMetadataManager.fetchAndCacheMetadata` reuses unexpired metadata and
deduplicates refresh by the stable page URL.

Evidence: navigation `ev_78c0d0bb81194f0464fa6d064813194a1235f74e05dcf2047c4b1bbf46167b45`;
resource DTO `ev_859abebac226e758dff8cd5f154f5354db39842483f4cb774683950735c7f4be`;
overlay `ev_dbb8fcbeeefd23241baf247839d1f5b383c230bb742d27c3f7982949610558f2`;
central action `ev_41e6c3f1077241e8da99761ec8c082bf07762f42188e210a289f185e27b518c5`;
refresh `ev_9906f51ad0b4138143145d7388c15b841f1899ff1b02f352bf5c26342b91cda0`.

## LetsCook runtime findings

- Android native video controls can consume the document click. A trusted
  press on the visible paused player must also record selection intent.
- The JavaScript detector emits numeric quality. Casting that value to
  String in Dart discarded the captured video before the room overlay.
- Preroll can outlast the initial capture retries. Continue checking only
  the selected playing element for the real content stream.
- Reject asynchronous validation results when navigation changes the page
  generation, including failure callbacks that would reset a new page.
- Windows composition WebView needs a focusable native child window and
  explicit controller focus when the user presses its page.

## Required verification

Build success and resolver/controller tests do not establish end-to-end
playback. Verify selection on a public non-DRM site, thumbnail overlay,
room creation, advancing native-player time, and in-room queue behavior.
Then verify navigation during resolution, a long preroll, an expired stream,
and an initialization failure with another available rendition.

The Web resolver now returns a stable page URL, a primary source and ordered
source alternatives with request headers and optional expiry. The resolver
tests cover the provider CDN boundary: the exact CDN and its subdomains are
accepted, while a different host that merely ends in the same text is not.
Neither this test nor queue serialization demonstrates that a second device
can play an expiring stream. Subtitle handling and live cross-device playback
remain separate checks. LetsCook does not use Rave's private scraper.

## Browser recovery

Android retries the current page and offers a separate action to clear cached
files while retaining sign-ins. It uses the existing WebView profile. Windows
uses a WebView2 InPrivate controller for generic Web browsing and a persistent
profile for provider sign-ins. Both clients discard stale detections when a
page fails so the previous video's room overlay does not survive a retry.
Neither client disables certificate validation. A reset from a site or its
network can still occur with an empty cache.

On November 4, 2026, a Windows runner using the app's WebView2 plugin
opened the video with ID `xhnBXwX` on `xhamster46.desi`. The detector
reported no selection on load. A click on the main player emitted a
selection, and the server returned 17 source alternatives. With the
resolver headers, the Windows FVP player advanced from 1.963 to 3.966
seconds (duration 184.900 seconds). This run exercised the browser,
resolver and player independently of the signed-in room UI. For the
same path on `xhamster.com`, WebView2 reported a connection reset.
