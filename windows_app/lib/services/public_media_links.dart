enum PublicMediaLinkProvider { googleDrive, dropbox, oneDrive, box, nextcloud }

/// Converts public cloud share links into their provider's download form.
///
/// This never handles account cookies or private credentials. The resulting
/// URL still has to pass a media probe before it can be added to a room.
Uri normalizePublicMediaLink(Uri uri, PublicMediaLinkProvider provider) {
  final host = uri.host.toLowerCase();
  switch (provider) {
    case PublicMediaLinkProvider.googleDrive:
      if (host == 'drive.google.com' || host.endsWith('.drive.google.com')) {
        String? id = uri.queryParameters['id'];
        final marker = uri.pathSegments.indexOf('d');
        if (id == null && marker >= 0 && marker + 1 < uri.pathSegments.length) {
          id = uri.pathSegments[marker + 1];
        }
        if (id != null && id.trim().isNotEmpty) {
          return Uri.https('drive.usercontent.google.com', '/download', {
            'id': id.trim(),
            'export': 'download',
            'confirm': 't',
          });
        }
      }
      return uri;
    case PublicMediaLinkProvider.dropbox:
      if (host == 'dropbox.com' || host.endsWith('.dropbox.com')) {
        final query = Map<String, String>.from(uri.queryParameters)
          ..remove('dl')
          ..['raw'] = '1';
        return uri.replace(queryParameters: query);
      }
      return uri;
    case PublicMediaLinkProvider.oneDrive:
      if (host == '1drv.ms' ||
          host == 'onedrive.live.com' ||
          host.endsWith('.onedrive.live.com')) {
        final query = Map<String, String>.from(uri.queryParameters)
          ..['download'] = '1';
        return uri.replace(queryParameters: query);
      }
      return uri;
    case PublicMediaLinkProvider.box:
      if (host == 'box.com' || host.endsWith('.box.com')) {
        final query = Map<String, String>.from(uri.queryParameters)
          ..['download'] = '1';
        return uri.replace(queryParameters: query);
      }
      return uri;
    case PublicMediaLinkProvider.nextcloud:
      final segments = uri.pathSegments;
      final shareMarker = segments.indexOf('s');
      if (shareMarker >= 0 && shareMarker + 1 < segments.length) {
        final token = segments[shareMarker + 1];
        final alreadyDownload =
            shareMarker + 2 < segments.length &&
            segments[shareMarker + 2] == 'download';
        if (token.isNotEmpty && !alreadyDownload) {
          return uri.replace(
            pathSegments: [...segments.take(shareMarker + 2), 'download'],
          );
        }
      }
      return uri;
  }
}

bool isPublicMediaDownloadCandidate(Uri uri, PublicMediaLinkProvider provider) {
  final host = uri.host.toLowerCase();
  return switch (provider) {
    PublicMediaLinkProvider.googleDrive =>
      host == 'drive.usercontent.google.com',
    PublicMediaLinkProvider.dropbox =>
      (host == 'dropbox.com' || host.endsWith('.dropbox.com')) &&
          uri.queryParameters['raw'] == '1',
    PublicMediaLinkProvider.oneDrive =>
      (host == '1drv.ms' ||
              host == 'onedrive.live.com' ||
              host.endsWith('.onedrive.live.com')) &&
          uri.queryParameters['download'] == '1',
    PublicMediaLinkProvider.box =>
      (host == 'box.com' || host.endsWith('.box.com')) &&
          uri.queryParameters['download'] == '1',
    PublicMediaLinkProvider.nextcloud =>
      uri.pathSegments.length >= 3 &&
          uri.pathSegments.contains('s') &&
          uri.pathSegments.last == 'download',
  };
}
