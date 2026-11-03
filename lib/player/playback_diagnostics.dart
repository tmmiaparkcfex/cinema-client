import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

class PlaybackDiagnostics {
  const PlaybackDiagnostics({
    this.decoder = '',
    this.droppedFrames = '',
    this.thermalState = '',
    this.lowPower = false,
  });

  final String decoder;
  final String droppedFrames;
  final String thermalState;
  final bool lowPower;

  String get decoderLabel => switch (decoder) {
    '' => '暂未取得',
    'no' => '软件解码',
    _ when decoder.contains('videotoolbox') => 'VideoToolbox 硬件解码',
    _ when decoder.contains('mediacodec') => 'MediaCodec 硬件解码',
    _ => decoder,
  };

  String get thermalLabel => switch (thermalState) {
    'nominal' => '正常',
    'fair' => '轻度升温',
    'serious' => '温度偏高',
    'critical' => '温度过高，建议暂停',
    _ => '当前设备未提供',
  };

  static Future<PlaybackDiagnostics> read(Player player) async {
    var decoder = '';
    var dropped = '';
    final native = player.platform;
    if (native is NativePlayer) {
      try {
        decoder = await native
            .getProperty('hwdec-current')
            .timeout(const Duration(seconds: 1));
        dropped = await native
            .getProperty('frame-drop-count')
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        // A renderer can still be opening or already have been disposed.
      }
    }
    Map<Object?, Object?> device = const {};
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        device =
            await const MethodChannel('cinema/device_vitals')
                .invokeMapMethod<Object?, Object?>('read')
                .timeout(const Duration(seconds: 1)) ??
            const {};
      } on PlatformException catch (_) {
      } on MissingPluginException catch (_) {
      } on TimeoutException catch (_) {}
    }
    return PlaybackDiagnostics(
      decoder: decoder,
      droppedFrames: dropped,
      thermalState: device['thermalState']?.toString() ?? '',
      lowPower: device['lowPowerMode'] == true,
    );
  }
}
