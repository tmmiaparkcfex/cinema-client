import 'package:media_kit/media_kit.dart';

// Keep styled ASS and bitmap subtitles inside mpv's video renderer. Flutter's
// plain text subtitle overlay loses those styles and cannot draw bitmap tracks.
Player createNativePlayer() => Player(
  configuration: const PlayerConfiguration(
    title: '影院',
    libass: true,
    libassAndroidFont: 'assets/fonts/NotoSansSC.ttf',
    libassAndroidFontName: 'Noto Sans SC',
  ),
);
