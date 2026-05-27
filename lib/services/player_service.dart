import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:just_audio/just_audio.dart';
import '../models/chapter.dart';
import 'api_service.dart';
import 'download_service.dart';
import 'audio_handler.dart';
import 'storage_service.dart';
import 'foreground_service.dart';

/// 播放服务 - 音频播放引擎 + 后台服务
class PlayerService {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService;
  DownloadService? _downloadService;
  StorageService? _storageService;
  AudioPlayerHandler? _handler;

  void setHandler(AudioPlayerHandler? h) => _handler = h;

  void _updateMeta() {
    if (_handler == null || _chapters.isEmpty || _currentIndex >= _chapters.length) return;
    _handler!.setMeta(_bookName, _chapters[_currentIndex].displayName);
  }

  List<Chapter> _chapters = [];
  int _currentIndex = 0;
  String _bookName = '';

  // 定时关闭
  Timer? _sleepTimer;
  SleepMode _sleepMode = SleepMode.off;
  int _sleepRemainingMinutes = 0;
  int _sleepRemainingChapters = 0;
  bool _manualSwitch = false;  // 手动切章标记，防止假触发_onChapterComplete
  bool _chapterEndFired = false;  // 防止positionStream多次触发章节末尾

  // 回调
  VoidCallback? onProgressChanged;
  VoidCallback? onChapterChanged;
  VoidCallback? onPlayStateChanged;
  void Function(String message)? onError;

  PlayerService(this._apiService, {DownloadService? downloadService, StorageService? storageService})
      : _downloadService = downloadService, _storageService = storageService {
    _setupListeners();
  }

  /// 设置下载服务（用于离线播放）
  void setDownloadService(DownloadService ds) => _downloadService = ds;

  AudioPlayer get player => _player;
  List<Chapter> get chapters => _chapters;
  int get currentIndex => _currentIndex;
  String get bookName => _bookName;
  SleepMode get sleepMode => _sleepMode;
  int get sleepRemainingMinutes => _sleepRemainingMinutes;
  int get sleepRemainingChapters => _sleepRemainingChapters;

  bool get isPlaying => _player.playing;
  Duration? get position => _player.position;
  Duration? get duration => _player.duration;
  Stream<Duration?> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;

  // 倍速
  double get speed => _player.speed;
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    if (_bookName.isNotEmpty) _storageService?.setSpeed(_bookName, speed);
  }

  // 进度
  Future<void> seek(Duration position) => _player.seek(position);

  void _setupListeners() {
    _player.positionStream.listen((pos) => _onPositionUpdate(pos));
    _player.playerStateStream.listen((state) {
      onPlayStateChanged?.call();
      // 后台保活：播放时启动前台服务，暂停时停止
      if (state.playing && _bookName.isNotEmpty) {
        final ch = _currentIndex < _chapters.length ? _chapters[_currentIndex].displayName : _bookName;
        ForegroundService.start(ch);
      } else {
        ForegroundService.stop();
      }
    });
    _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex) {
        _manualSwitch = false;
        _chapterEndFired = false;
        _currentIndex = index;
        _updateMeta();
        onChapterChanged?.call();
      }
    });
  }

  void _onPositionUpdate(Duration? pos) {
    onProgressChanged?.call();
    if (_chapterEndFired || !_player.playing) return;
    final dur = _player.duration;
    if (pos != null && dur != null &&
        dur.inMilliseconds > 1000 &&
        (dur.inMilliseconds - pos.inMilliseconds) < 500) {
      _chapterEndFired = true;
      if (!_manualSwitch) _onChapterComplete();
    }
  }

  /// 加载并播放某本书
  Future<void> loadBook(String bookName, List<Chapter> chapters,
      {int startIndex = 0, int startPositionMs = 0}) async {
    _bookName = bookName;
    _chapters = chapters;
    _currentIndex = startIndex;

    // 构建播放列表（优先使用本地下载文件）
    final audioSources = <AudioSource>[];
    for (final ch in chapters) {
      final fileName = ch.fileName;
      final localPath = _downloadService != null
          ? await _downloadService!.getLocalFile(bookName, fileName)
          : null;

      if (localPath != null) {
        audioSources.add(AudioSource.file(localPath));
      } else {
        final url = _apiService.getAudioUrl(ch.file);
        audioSources.add(AudioSource.uri(Uri.parse(url)));
      }
    }

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: audioSources),
      initialIndex: startIndex,
      initialPosition: Duration(milliseconds: startPositionMs),
    );

    // 恢复该书的播放速度
    final savedSpeed = _storageService?.getSpeed(bookName) ?? 1.0;
    if (savedSpeed != 1.0) await _player.setSpeed(savedSpeed);

    if (startPositionMs > 0) {
      await _player.seek(Duration(milliseconds: startPositionMs));
    }
    _updateMeta();
  }

  /// 跳转到指定章节从头播放
  Future<void> playChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    _manualSwitch = true;
    _currentIndex = index;         // 先赋值，防止currentIndexStream触发_onChapterComplete
    await _player.seek(Duration.zero, index: index);
    await _player.play();
    onChapterChanged?.call();
  }

  /// 跳转到指定章节并从指定位置播放（用于恢复进度）
  Future<void> playChapterAt(int index, int startMs) async {
    if (index < 0 || index >= _chapters.length) return;
    _manualSwitch = true;
    _currentIndex = index;
    await _player.seek(Duration(milliseconds: startMs), index: index);
    await _player.play();
    onChapterChanged?.call();
  }

  // ======= 播放控制 =======
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> playPause() => _player.playing ? _player.pause() : _player.play();

  Future<void> skipNext() async {
    if (_currentIndex < _chapters.length - 1) {
      await playChapter(_currentIndex + 1);
    }
  }

  Future<void> skipPrevious() async {
    // 如果当前进度超过5秒，回到开头；否则上一集
    if (_player.position.inSeconds > 5) {
      await _player.seek(Duration.zero);
    } else if (_currentIndex > 0) {
      await playChapter(_currentIndex - 1);
    }
  }

  Future<void> seekRelative(int seconds) async {
    final newPos = _player.position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: max(0, min(
        newPos.inMilliseconds,
        (_player.duration?.inMilliseconds ?? 0),
      )),
    );
    await _player.seek(clamped);
  }

  // ======= 定时关闭 =======
  void startSleepTimer({int? minutes, int? chapters}) {
    cancelSleepTimer();

    if (minutes != null && minutes > 0) {
      _sleepMode = SleepMode.time;
      _sleepRemainingMinutes = minutes;
      _sleepTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _sleepRemainingMinutes--;
        onProgressChanged?.call();
        if (_sleepRemainingMinutes <= 0) {
          _player.pause();
          cancelSleepTimer();
        }
      });
    } else if (chapters != null && chapters >= 0) {
      _sleepMode = SleepMode.chapters;
      _sleepRemainingChapters = chapters; // 0=本集播完停
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMode = SleepMode.off;
    _sleepRemainingMinutes = 0;
    _sleepRemainingChapters = 0;
  }

  void _onChapterComplete() {
    if (_sleepMode == SleepMode.chapters) {
      _sleepRemainingChapters--;
      onProgressChanged?.call();
      if (_sleepRemainingChapters <= 0) {
        _player.pause();
        cancelSleepTimer();
      }
    }
  }

  /// 获取当前进度信息（用于保存）
  Map<String, dynamic> getProgressInfo() {
    return {
      'chapterIndex': _currentIndex,
      'positionMs': _player.position.inMilliseconds,
    };
  }

  void dispose() {
    cancelSleepTimer();
    _player.dispose();
  }
}

enum SleepMode { off, time, chapters }
