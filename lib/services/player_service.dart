import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';
import '../models/chapter.dart';
import 'api_service.dart';
import 'download_service.dart';
import 'storage_service.dart';
import 'native_player.dart';

/// 播放服务 - 调用原生 ExoPlayer 引擎，实现锁屏/通知栏/蓝牙控制
class PlayerService {
  final ApiService _apiService;
  final DownloadService? _downloadService;
  final StorageService? _storageService;
  final NativePlayer _nativePlayer;

  String _bookName = '';
  List<Chapter> _chapters = [];
  int _currentIndex = 0;
  String _lastAudioUrl = '';
  Timer? _pollTimer;

  // 定时关闭
  Timer? _sleepTimer;
  SleepMode _sleepMode = SleepMode.off;
  int _sleepRemainingMinutes = 0;
  int _sleepRemainingChapters = 0;
  bool _manualSwitch = false;
  bool _chapterEndFired = false;

  // 回调
  Function()? onProgressChanged;
  Function()? onChapterChanged;
  Function()? onPlayStateChanged;
  void Function(String message)? onError;

  PlayerService(
    this._apiService, {
    DownloadService? downloadService,
    StorageService? storageService,
    required NativePlayer nativePlayer,
  })  : _downloadService = downloadService,
        _storageService = storageService,
        _nativePlayer = nativePlayer {
    _setupListeners();
  }

  String get bookName => _bookName;
  List<Chapter> get chapters => _chapters;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlayingCache;
  double get speed => _speedCache;
  Duration get duration => Duration(milliseconds: _durationCache);
  Duration get position => Duration(milliseconds: _positionCache);
  int get positionMs => _positionCache;
  int get durationMs => _durationCache;
  String get currentChapterName =>
      _currentIndex < _chapters.length ? _chapters[_currentIndex].displayName : '';

  // 缓存值（定时轮询原生播放器获取）
  bool _isPlayingCache = false;
  double _speedCache = 1.0;
  int _positionCache = 0;
  int _durationCache = 0;
  int _lastSeenIndex = 0;

  AudioPlayer? _compatPlayer; // 仅用于兼容 just_audio 接口

  /// 兼容旧调用，返回占位 AudioPlayer
  AudioPlayer get player {
    _compatPlayer ??= AudioPlayer();
    return _compatPlayer!;
  }

  void _setupListeners() {
    _nativePlayer.onPlayingChanged = (playing) {
      _isPlayingCache = playing;
      onPlayStateChanged?.call();
      if (!playing) {
        // 暂停/停止时把进度保存
        _saveAllProgress();
      }
    };

    _nativePlayer.onPositionDiscontinuity = () {
      onChapterChanged?.call();
    };

    // 启动轮询
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollState());
  }

  Future<void> _pollState() async {
    try {
      final s = await _nativePlayer.getState();
      _isPlayingCache = s.isPlaying;
      _speedCache = s.speed;
      _positionCache = s.positionMs;
      _durationCache = s.durationMs;

      // 检测章节切换
      if (s.currentIndex != _lastSeenIndex) {
        _lastSeenIndex = s.currentIndex;
        if (_currentIndex != s.currentIndex) {
          _currentIndex = s.currentIndex;
          if (!_manualSwitch) {
            _onChapterComplete();
          } else {
            _manualSwitch = false;
          }
          _chapterEndFired = false;
          onChapterChanged?.call();
          _saveAllProgress();
        }
      }

      // 位置接近末尾（<2秒）触发章节完成
      if (_isPlayingCache &&
          _durationCache > 0 &&
          (_durationCache - _positionCache) < 2000 &&
          !_chapterEndFired) {
        _chapterEndFired = true;
        _onChapterComplete();
      }

      // 进度保存
      if (_isPlayingCache && _bookName.isNotEmpty) {
        _saveCurrentChapterPosition(_positionCache);
      }
      onProgressChanged?.call();
    } catch (e) {
      debugPrint('pollState error: $e');
    }
  }

  void _onChapterComplete() {
    if (_sleepMode == SleepMode.chapters) {
      _sleepRemainingChapters--;
      if (_sleepRemainingChapters < 0) {
        _stopSleep();
        _nativePlayer.pause();
      }
    }
  }

  /// 加载并播放某本书
  Future<void> loadBook(String bookName, List<Chapter> chapters,
      {int startIndex = 0, int startPositionMs = 0}) async {
    _bookName = bookName;
    _chapters = chapters;
    _currentIndex = startIndex;
    _lastSeenIndex = startIndex;
    _manualSwitch = false;
    _chapterEndFired = false;

    // 构建URL列表（优先用本地缓存路径）
    final urls = <String>[];
    final titles = <String>[];
    for (final ch in chapters) {
      final local = await _downloadService?.getLocalFile(bookName, ch.fileName);
      final url = local ?? _apiService.getAudioUrl('${bookName}/${ch.fileName}');
      debugPrint('loadBook: [$startIndex] ${ch.fileName} -> $url');
      urls.add(url);
      titles.add(ch.displayName);
    }
    _lastAudioUrl = urls.isNotEmpty ? urls[0] : '';

    // 恢复该书的播放速度
    final savedSpeed = _storageService?.getSpeed(bookName) ?? 1.0;
    _speedCache = savedSpeed;

    await _nativePlayer.loadBook(
      chapterUrls: urls,
      chapterTitles: titles,
      startIndex: startIndex,
      startMs: startPositionMs,
    );

    if (savedSpeed != 1.0) {
      await _nativePlayer.setSpeed(savedSpeed);
    }
  }

  Future<void> play() => _nativePlayer.play();
  Future<void> pause() => _nativePlayer.pause();

  /// 跳转到指定章节播放
  Future<void> playChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    _manualSwitch = true;
    _currentIndex = index;
    _lastSeenIndex = index;
    _chapterEndFired = false;
    await _nativePlayer.seekToChapter(index);
    await _nativePlayer.play();
  }

  Future<void> seek(Duration position) async {
    await _nativePlayer.seek(position.inMilliseconds);
  }

  Future<void> seekToChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    _manualSwitch = true;
    _currentIndex = index;
    _lastSeenIndex = index;
    _chapterEndFired = false;
    await _nativePlayer.seekToChapter(index);
  }

  Future<void> playChapterAt(int index, int startMs) async {
    _manualSwitch = true;
    _currentIndex = index;
    _lastSeenIndex = index;
    _chapterEndFired = false;
    if (startMs > 0) {
      await _nativePlayer.seekToChapter(index);
      await _nativePlayer.seek(startMs);
    } else {
      await _nativePlayer.seekToChapter(index);
    }
    await _nativePlayer.play();
  }

  Future<void> skipToNext() => _nativePlayer.skipNext();
  Future<void> skipNext() => _nativePlayer.skipNext();
  Future<void> skipToPrevious() => _nativePlayer.skipPrev();
  Future<void> skipPrevious() => _nativePlayer.skipPrev();

  Future<void> togglePlayPause() async {
    if (_isPlayingCache) {
      await _nativePlayer.pause();
    } else {
      await _nativePlayer.play();
    }
  }

  Future<void> playPause() => togglePlayPause();

  /// 相对当前位置跳转，单位 = 秒（内部转成 ms 传给原生）
  /// 之所以用秒为单位，是因为 UI 上 forward_10 / replay_10 图标就是 10 秒的概念
  Future<void> seekRelative(int deltaSeconds) async {
    final deltaMs = deltaSeconds * 1000;
    final target = (_positionCache + deltaMs).clamp(0, _durationCache);
    await _nativePlayer.seek(target);
  }

  Future<void> setSpeed(double speed) async {
    await _nativePlayer.setSpeed(speed);
    _speedCache = speed;
    if (_bookName.isNotEmpty) await _storageService?.setSpeed(_bookName, speed);
  }

  // ===== 进度保存 =====
  void _saveCurrentChapterPosition(int ms) {
    if (_bookName.isEmpty) return;
    _storageService?.saveChapterPosition(_bookName, _currentIndex, ms, _durationCache);
  }

  void _saveAllProgress() {
    if (_bookName.isEmpty) return;
    _storageService?.saveChapterPosition(_bookName, _currentIndex, _positionCache, _durationCache);
  }

  Future<void> saveProgress() async => _saveAllProgress();

  Map<String, dynamic> getProgressInfo() {
    return {
      'bookName': _bookName,
      'chapterIndex': _currentIndex,
      'positionMs': _positionCache,
      'durationMs': _durationCache,
    };
  }

  // ===== 定时关闭 =====
  void startSleepTimer({int? minutes, int? chapters}) =>
      setSleepTimer(minutes: minutes, chapters: chapters);

  void cancelSleepTimer() {
    _stopSleep();
  }

  void setSleepTimer({int? minutes, int? chapters}) {
    _sleepTimer?.cancel();
    if (minutes != null) {
      _sleepMode = SleepMode.minutes;
      _sleepRemainingMinutes = minutes;
      _sleepTimer = Timer.periodic(const Duration(minutes: 1), (t) {
        _sleepRemainingMinutes--;
        if (_sleepRemainingMinutes <= 0) {
          t.cancel();
          _nativePlayer.pause();
          _stopSleep();
        }
      });
    } else if (chapters != null && chapters >= 0) {
      _sleepMode = SleepMode.chapters;
      _sleepRemainingChapters = chapters;
    }
  }

  void _stopSleep() {
    _sleepTimer?.cancel();
    _sleepMode = SleepMode.off;
    _sleepRemainingMinutes = 0;
    _sleepRemainingChapters = 0;
  }

  String get sleepRemainingText {
    if (_sleepMode == SleepMode.minutes) return '${_sleepRemainingMinutes}分钟';
    if (_sleepMode == SleepMode.chapters) {
      if (_sleepRemainingChapters == 0) return '本集完';
      return '剩$_sleepRemainingChapters集';
    }
    return '';
  }

  SleepMode get sleepMode => _sleepMode;
  int get sleepRemainingMinutes => _sleepRemainingMinutes;
  int get sleepRemainingChapters => _sleepRemainingChapters;

  void dispose() {
    _pollTimer?.cancel();
    _sleepTimer?.cancel();
  }
}

enum SleepMode { off, minutes, chapters }
