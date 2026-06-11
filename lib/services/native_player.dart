import 'dart:async';
import 'package:flutter/services.dart';

/// 桥接 Android 原生 MediaController（基于 ExoPlayer+MediaSession）
/// 提供锁屏/通知栏/蓝牙耳机控制
class NativePlayer {
  static const _channel = MethodChannel('com.gtmatch.audiobook/player');
  final Completer<void> _ready = Completer<void>();

  NativePlayer() {
    _channel.setMethodCallHandler((call) async {
      await _onMethodCall(call);
    });
  }

  Future<void> get waitReady async {
    // 原生侧通过 isReady 探测
    try {
      while (true) {
        final ok = await _channel.invokeMethod<bool>('isReady');
        if (ok == true) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (_) {
      // 失败时也放行, 避免初始化卡死
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPlayingChanged':
        final cb = _onPlayingChanged;
        if (cb != null) cb(call.arguments as bool? ?? false);
        break;
      case 'onPositionDiscontinuity':
        final cb = _onPositionDiscontinuity;
        if (cb != null) cb();
        break;
    }
    return null;
  }

  void Function(bool isPlaying)? _onPlayingChanged;
  void Function()? _onPositionDiscontinuity;

  set onPlayingChanged(void Function(bool)? cb) => _onPlayingChanged = cb;
  set onPositionDiscontinuity(void Function()? cb) => _onPositionDiscontinuity = cb;

  // ===== 控制API =====
  Future<void> loadBook({
    required List<String> chapterUrls,
    required List<String> chapterTitles,
    required int startIndex,
    required int startMs,
  }) async {
    await _channel.invokeMethod('loadBook', {
      'chapterUrls': chapterUrls,
      'chapterTitles': chapterTitles,
      'startIndex': startIndex,
      'startMs': startMs,
    });
  }

  Future<void> play() => _channel.invokeMethod('play');
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> seek(int ms) => _channel.invokeMethod('seek', {'ms': ms});
  Future<void> seekToChapter(int index) => _channel.invokeMethod('seekToChapter', {'index': index});
  Future<void> setSpeed(double speed) => _channel.invokeMethod('setSpeed', {'speed': speed});
  Future<void> skipNext() => _channel.invokeMethod('skipNext');
  Future<void> skipPrev() => _channel.invokeMethod('skipPrev');
  Future<void> stop() => _channel.invokeMethod('stop');

  Future<NativePlayerState> getState() async {
    final raw = await _channel.invokeMethod('getState');
    final map = Map<String, dynamic>.from(raw as Map);
    return NativePlayerState(
      isPlaying: map['isPlaying'] as bool? ?? false,
      currentIndex: map['currentIndex'] as int? ?? 0,
      positionMs: map['positionMs'] as int? ?? 0,
      durationMs: map['durationMs'] as int? ?? 0,
      speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class NativePlayerState {
  final bool isPlaying;
  final int currentIndex;
  final int positionMs;
  final int durationMs;
  final double speed;

  NativePlayerState({
    required this.isPlaying,
    required this.currentIndex,
    required this.positionMs,
    required this.durationMs,
    required this.speed,
  });
}
