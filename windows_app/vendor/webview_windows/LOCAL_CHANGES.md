# Local changes to webview_windows 0.4.0

The Windows composition controller now receives `MoveFocus(PROGRAMMATIC)`
before mouse or touch pointer down. Forwarding pointer input alone can focus an
HTML input visually while keyboard input remains in the Flutter host window.
The zero-sized native input host is a visible child of the Flutter view rather
than a message-only window, allowing WebView2 to receive native keyboard focus.
Rendering remains in the Flutter texture.

`initialize(inPrivate: true)` creates a WebView2 composition controller with
an InPrivate profile named `LetsCookPrivateWeb`. Other controllers retain the
existing persistent profile. The discovery browser uses InPrivate for generic
Web browsing. Navigation errors from superseded navigations are ignored by
matching WebView2 navigation IDs. Cache disabling now passes the CDP property
`cacheDisabled`; clearing cached files does not clear provider cookies.

The Dart SDK upper bound is widened to Dart 4 for this Dart 3 application.
Upstream source and license are preserved. The application selects this copy
through its `dependency_overrides` entry.
