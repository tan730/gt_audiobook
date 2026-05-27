import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// 将 just_audio 接入 audio_service，提供锁屏/通知栏控制
class AudioPlayerHandler extends BaseAudioHandler {
  AudioPlayer? _player;

  AudioPlayerHandler() {
    _initState();
  }

  /// 连接播放器
  void bindPlayer(AudioPlayer player) {
    _player = player;
    player.playbackEventStream.listen(_onPlaybackEvent);
    player.playingStream.listen((_) => _syncState());
    _initState();
  }

  void _initState() {
    mediaItem.add(null);
    playbackState.add(PlaybackState(
      controls: const [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {MediaAction.seek},
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  void _syncState() {
    final p = _player;
    if (p == null) return;
    final playing = p.playing;

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapState(p.processingState),
      playing: playing,
      updatePosition: p.position,
      bufferedPosition: p.bufferedPosition,
      speed: p.speed,
    ));
  }

  void _onPlaybackEvent(PlaybackEvent event) => _syncState();

  AudioProcessingState _mapState(ProcessingState s) {
    switch (s) {
      case ProcessingState.idle: return AudioProcessingState.idle;
      case ProcessingState.loading: return AudioProcessingState.loading;
      case ProcessingState.buffering: return AudioProcessingState.buffering;
      case ProcessingState.ready: return AudioProcessingState.ready;
      case ProcessingState.completed: return AudioProcessingState.completed;
    }
  }

  /// 更新通知栏显示
  void setMeta(String book, String chapter) {
    mediaItem.add(MediaItem(
      id: '0',
      album: book,
      title: chapter,
    ));
  }

  @override Future<void> play() async => _player?.play();
  @override Future<void> pause() async => _player?.pause();
  @override Future<void> skipToNext() async { if (_player?.hasNext == true) await _player?.seekToNext(); }
  @override Future<void> skipToPrevious() async { if (_player?.hasPrevious == true) await _player?.seekToPrevious(); }
  @override Future<void> seek(Duration position) async => _player?.seek(position);
  @override Future<void> stop() async { await _player?.stop(); await super.stop(); }
}
