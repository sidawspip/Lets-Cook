import 'package:flutter_test/flutter_test.dart';
import 'package:lets_cook_windows/models/models.dart';
import 'package:lets_cook_windows/services/media_resolver.dart';
import 'package:lets_cook_windows/services/public_media_links.dart';

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

  test('normalized provider media resolves into the custom player', () async {
    final resolver = SplitMediaResolver();
    addTearDown(resolver.close);
    const state = RoomWatchState(
      roomId: 'room-1',
      mediaId: 'https://drive.usercontent.google.com/download?id=file-123',
      sourceUrl: 'https://drive.usercontent.google.com/download?id=file-123',
      provider: 'GOOGLE_DRIVE',
      title: 'Drive video',
      playing: true,
      positionSeconds: 12,
    );

    final media = await resolver.resolve(state);

    expect(media.uri, Uri.parse(state.sourceUrl!));
  });
}
