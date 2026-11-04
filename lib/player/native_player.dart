import 'package:media_kit/media_kit.dart';

import '../core/app_log.dart';

// Keep forward/backward packets in bounded RAM. media_kit otherwise enables an
// append-only disk cache, even when the source is already a local HTTP proxy.
const nativePlaybackProperties = <String, String>{
  'cache': 'yes',
  'cache-on-disk': 'no',
  'demuxer-max-back-bytes': '16777216',
  'cache-secs': '30',
  'cache-pause': 'yes',
  'cache-pause-initial': 'yes',
  'cache-pause-wait': '3',
  // One proxy part allows 15 s for headers plus 15 s for its body. The native
  // reader must not abandon that live request at media_kit's 5 s default.
  'network-timeout': '40',
};

Future<void> configureNativePlayback(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  for (final entry in nativePlaybackProperties.entries) {
    await native.setProperty(entry.key, entry.value);
  }
  AppLog.info(
    'player-cache',
    'disk=${await native.getProperty('cache-on-disk')} '
        'networkTimeout=${await native.getProperty('network-timeout')} '
        'cacheSeconds=${await native.getProperty('cache-secs')}',
  );
}

// Keep styled ASS and bitmap subtitles inside mpv's video renderer. Flutter's
// plain text subtitle overlay loses those styles and cannot draw bitmap tracks.
Player createNativePlayer() => Player(
  configuration: const PlayerConfiguration(
    title: '影院',
    bufferSize: 64 * 1024 * 1024,
    libass: true,
    libassAndroidFont: 'assets/fonts/NotoSansSC.ttf',
    libassAndroidFontName: 'Noto Sans SC',
  ),
);
