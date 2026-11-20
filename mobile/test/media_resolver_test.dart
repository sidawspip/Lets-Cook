import 'package:flutter_test/flutter_test.dart';
import 'package:lets_cook_mobile/models/models.dart';
import 'package:lets_cook_mobile/services/media_resolver.dart';
import 'package:lets_cook_mobile/services/public_media_links.dart';

void main() {
  test('direct media template selects a mobile-safe rendition', () {
    final template = Uri.parse(
      'https://cdn.example/media=hls4/'
      'multi=256x144:144p:,426x240:240p:,854x480:480p:/'
      'video/_TPL_.av1.mp4',
    );

    final resolved = resolveDirectMediaTemplate(template);

    expect(resolved.toString(), endsWith('/video/240p.av1.mp4'));
    expect(resolved.toString(), isNot(contains('_TPL_')));
  });

  test('recognizes unresolved provider templates', () {
    expect(
      hasUnresolvedMediaTemplate(
        Uri.parse('https://cdn.example/video/_TPL_.av1.mp4'),
      ),
      isTrue,
    );
    expect(
      hasUnresolvedMediaTemplate(
        Uri.parse('https://cdn.example/video/360p.h264.mp4'),
      ),
      isFalse,
    );
  });

  test('captured streams retain their page request context', () {
    final page = Uri.parse('https://videos.example/watch/selected');
    final stream = Uri.parse('https://cdn.example/video/360.mp4');

    final headers = directMediaHttpHeaders(stream, sourcePage: page);

    expect(headers['Referer'], page.toString());
    expect(headers['Origin'], 'https://videos.example');
    expect(headers['User-Agent'], contains('Android'));
  });

  test('xHamster media CDN uses the selected page as request context', () {
    final page = Uri.parse(
      'https://xhamster46.desi/videos/queen-marika-selected',
    );
    final stream = Uri.parse(
      'https://video-nss.xhmediacdn.com/signed/media/master.m3u8',
    );

    final headers = directMediaHttpHeaders(stream, sourcePage: page);

    expect(headers['Referer'], 'https://xhamster46.desi/');
    expect(headers['Origin'], 'https://xhamster46.desi');
    expect(isProviderOwnedBrowserMedia(stream, sourcePage: page), isTrue);
    expect(
      isProviderOwnedBrowserMedia(
        Uri.parse('https://ads.example/video.mp4'),
        sourcePage: page,
      ),
      isFalse,
    );
  });

  test(
    'resolved media keeps ordered fallbacks and source-specific headers',
    () {
      final primary = Uri.parse('https://cdn.example/master.m3u8');
      final low = Uri.parse('https://cdn.example/240p.m3u8');
      final media = ResolvedMedia(
        primary,
        httpHeaders: const {'Referer': 'https://page.example/'},
        fallbackSources: [
          ResolvedMediaSource(
            low,
            httpHeaders: const {'Referer': 'https://page.example/video'},
          ),
          ResolvedMediaSource(primary),
        ],
      );

      expect(media.orderedSources.map((source) => source.uri), [primary, low]);
      expect(
        media.orderedSources.last.httpHeaders['Referer'],
        'https://page.example/video',
      );
    },
  );

  test('normalizes backend source alternatives without unsafe headers', () {
    final page = Uri.parse('https://xhamster46.desi/videos/selected');
    final sources = resolvedMediaSourcesFromResponse([
      {
        'url': 'https://video-nss.xhmediacdn.com/video/720p.m3u8',
        'sourceType': 'DIRECT_HLS',
        'httpHeaders': {
          'Referer': 'https://xhamster46.desi/',
          'Cookie': 'must-not-be-forwarded',
        },
      },
      {
        'url': 'https://video-nss.xhmediacdn.com/video/_TPL_.mp4',
        'sourceType': 'DIRECT_MP4',
      },
    ], sourcePage: page);

    expect(sources, hasLength(1));
    expect(sources.single.httpHeaders['Referer'], '${page.origin}/');
    expect(sources.single.httpHeaders.containsKey('Cookie'), isFalse);
  });

  test('normalizes public cloud share links without credentials', () {
    final drive = normalizePublicMediaLink(
      Uri.parse('https://drive.google.com/file/d/file-123/view'),
      PublicMediaLinkProvider.googleDrive,
    );
    final dropbox = normalizePublicMediaLink(
      Uri.parse('https://www.dropbox.com/s/abc/movie.mp4?dl=0'),
      PublicMediaLinkProvider.dropbox,
    );
    final oneDrive = normalizePublicMediaLink(
      Uri.parse('https://1drv.ms/v/s!example'),
      PublicMediaLinkProvider.oneDrive,
    );
    final box = normalizePublicMediaLink(
      Uri.parse('https://app.box.com/s/example/file/123'),
      PublicMediaLinkProvider.box,
    );
    final nextcloud = normalizePublicMediaLink(
      Uri.parse('https://cloud.example.com/s/share-token'),
      PublicMediaLinkProvider.nextcloud,
    );

    expect(drive.host, 'drive.usercontent.google.com');
    expect(drive.queryParameters['id'], 'file-123');
    expect(dropbox.queryParameters['raw'], '1');
    expect(dropbox.queryParameters.containsKey('dl'), isFalse);
    expect(oneDrive.queryParameters['download'], '1');
    expect(box.queryParameters['download'], '1');
    expect(nextcloud.path, '/s/share-token/download');
  });

  test('only normalized public links are download candidates', () {
    final share = Uri.parse('https://app.box.com/s/example/file/123');
    final download = normalizePublicMediaLink(
      share,
      PublicMediaLinkProvider.box,
    );

    expect(
      isPublicMediaDownloadCandidate(share, PublicMediaLinkProvider.box),
      isFalse,
    );
    expect(
      isPublicMediaDownloadCandidate(download, PublicMediaLinkProvider.box),
      isTrue,
    );
  });

  test('provider HTTPS media is offered to the native custom player', () async {
    final resolver = SplitMediaResolver();
    addTearDown(resolver.close);

    final media = await resolver.resolve(
      const RoomWatchState(
        provider: 'DROPBOX',
        sourceType: 'DROPBOX',
        sourceUrl: 'https://cdn.example.test/movie.mp4',
        mediaId: 'https://cdn.example.test/movie.mp4',
        title: 'Provider movie',
        playing: true,
        positionSeconds: 0,
      ),
    );

    expect(media.uri, Uri.parse('https://cdn.example.test/movie.mp4'));
  });
}
