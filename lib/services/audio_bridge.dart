import 'package:flutter/services.dart';

/// Kotlin MethodChannel + PCM capture EventChannel.
class AudioBridge {
  AudioBridge();

  static const MethodChannel _audio = MethodChannel('local_party/audio');
  static const EventChannel _pcm =
      EventChannel('local_party/audio_pcm');

  Future<bool> requestMediaProjection() async {
    final ok = await _audio.invokeMethod<bool>('requestMediaProjection');
    return ok == true;
  }

  Future<void> startCaptureService() async {
    await _audio.invokeMethod<void>('startCaptureService');
  }

  Future<void> stopCaptureService() async {
    await _audio.invokeMethod<void>('stopCaptureService');
  }

  Future<void> startPlayback() async {
    await _audio.invokeMethod<void>('startPlayback');
  }

  Future<void> stopPlayback() async {
    await _audio.invokeMethod<void>('stopPlayback');
  }

  Future<void> feedPcm({
    required int playAtUtcMs,
    required Uint8List pcm,
  }) async {
    await _audio.invokeMethod<void>('feedPcm', <String, Object?>{
      'playAtUtcMs': playAtUtcMs,
      'pcm': pcm,
    });
  }

  Future<double> pcmLevel(Uint8List pcm) async {
    final v = await _audio.invokeMethod<double>('pcmLevel', <String, Object?>{
      'pcm': pcm,
    });
    return v ?? 0;
  }

  Stream<Map<String, dynamic>> pcmCaptureStream() {
    return _pcm.receiveBroadcastStream().map((event) {
      final map = Map<Object?, Object?>.from(event as Map);
      return Map<String, dynamic>.from(map);
    });
  }
}
