import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class RexSound {
  static const _channel = MethodChannel('cinema/rex-sound');
  static Future<void> play(String name) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('play', name);
    } on PlatformException {
      /* Audio feedback must not prevent navigation. */
    } on MissingPluginException {
      /* Widget tests and platforms without the bridge. */
    }
  }

  static Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Audio must not block leaving the introduction.
    } on MissingPluginException {
      // The bridge is absent in widget tests.
    }
  }
}
