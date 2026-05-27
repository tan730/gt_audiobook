import 'package:flutter/services.dart';

/// 通过 Native MethodChannel 控制 Android Foreground Service
class ForegroundService {
  static const _channel = MethodChannel('com.gtmatch.audiobook/foreground');

  static Future<void> start(String title) async {
    try {
      await _channel.invokeMethod('startForeground', {'title': title});
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopForeground');
    } catch (_) {}
  }
}
