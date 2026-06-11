import 'package:flutter/material.dart';
import '../models/chapter.dart';
import '../services/player_service.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../widgets/timer_dialog.dart';

class PlayerScreen extends StatefulWidget {
  final PlayerService playerService;
  final DownloadService downloadService;
  final StorageService storageService;

  const PlayerScreen({
    super.key,
    required this.playerService,
    required this.downloadService,
    required this.storageService,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  late PlayerService _ps;
  Map<String, double> _dlProgress = {};
  final Set<String> _dlErrors = {};       // 下载失败的文件名
  final ScrollController _scrollCtrl = ScrollController();
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _ps = widget.playerService;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _ps.onProgressChanged = () {
      if (mounted) setState(() {});
      _saveProgress();
    };
    _ps.onChapterChanged = () {
      if (mounted) {
        setState(() {});
        _scrollToCurrent();
      }
      _saveProgress();
    };
    _ps.onPlayStateChanged = () {
      if (mounted) setState(() {});
    };

    final origCb = widget.downloadService.onProgress;
    widget.downloadService.onProgress = (bookName, fileName, progress) {
      if (mounted) setState(() => _dlProgress = Map.from(widget.downloadService.downloadProgress));
      origCb?.call(bookName, fileName, progress);
    };

    _checkDownloads();
    // 首帧渲染后延迟滚动到当前播放集居中（等待ListView完成布局）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), _scrollToCurrent);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkDownloads() async {
    final ds = widget.downloadService;
    for (final ch in _ps.chapters) {
      ch.downloaded = await ds.isDownloaded(_ps.bookName, ch.fileName);
    }
    if (mounted) setState(() {});
  }

  void _saveProgress() {
    if (_ps.bookName.isEmpty) return;
    final info = _ps.getProgressInfo();
    final posMs = info['positionMs'] as int;
    final dur = _ps.duration;
    // 播完（距末尾2秒内）→ 清除该章进度；未播完 → 保存
    if (dur != null && posMs > 0 && (dur.inMilliseconds - posMs) < 2000) {
      widget.storageService.clearChapterPosition(_ps.bookName, info['chapterIndex'] as int);
    } else {
      widget.storageService.saveProgress(
          _ps.bookName, info['chapterIndex'] as int, posMs);
    }
  }

  void _scrollToCurrent() {
    if (!_scrollCtrl.hasClients || _ps.chapters.isEmpty) return;
    final idx = _ps.currentIndex;
    final itemHeight = 52.0;
    final offset = (idx * itemHeight) - (_scrollCtrl.position.viewportDimension / 2) + (itemHeight / 2);
    final clamped = offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    if (clamped > 0) {
      _scrollCtrl.jumpTo(clamped);
    }
  }

  void _onChapterTap(int index) {
    final savedMs = widget.storageService.getChapterPosition(_ps.bookName, index);
    if (savedMs > 0 && index != _ps.currentIndex) {
      _ps.playChapterAt(index, savedMs);
    } else {
      _ps.playChapter(index);
    }
  }

  Future<void> _downloadChapter(Chapter ch) async {
    final fileName = ch.fileName;
    _dlErrors.remove(fileName);
    if (mounted) setState(() {});
    try {
      debugPrint('=== GT下载开始: book=${_ps.bookName}, file=$fileName');
      await widget.downloadService.downloadChapter(_ps.bookName, ch);
      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      debugPrint('=== GT下载失败: $e');
      debugPrint('=== STACK: $stackTrace');
      _dlErrors.add(fileName);
      if (mounted) setState(() {});
    }
  }

  void _showTimerDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => TimerDialog(
        currentMode: _ps.sleepMode,
        remainingMinutes: _ps.sleepRemainingMinutes,
        remainingChapters: _ps.sleepRemainingChapters,
        onSetTimer: (minutes) => _ps.startSleepTimer(minutes: minutes),
        onSetChapterTimer: (chapters) => _ps.startSleepTimer(chapters: chapters),
        onCancel: _ps.cancelSleepTimer,
      ),
    );
  }

  void _showJumpDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到第几章'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '输入章节编号', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null) {
                final index = _ps.chapters.indexWhere((c) => c.sortKey == n);
                if (index >= 0) {
                  Navigator.pop(ctx);
                  _onChapterTap(index);
                }
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ps.chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('还没有在播放的内容'),
            const SizedBox(height: 8),
            const Text('去书库选择一本书开始听吧'),
          ],
        ),
      );
    }

    final currentChapter = _ps.currentIndex < _ps.chapters.length ? _ps.chapters[_ps.currentIndex] : null;

    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              if (currentChapter != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(currentChapter.displayName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${_ps.currentIndex + 1} / ${_ps.chapters.length}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.skip_next), tooltip: '跳转', onPressed: _showJumpDialog),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  _buildSleepTimerButton(),
                  const SizedBox(width: 8),
                  _buildSpeedButton(),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.my_location), tooltip: '跳转', onPressed: _showJumpDialog),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: _ps.chapters.length,
                  itemBuilder: (context, index) {
                    final ch = _ps.chapters[index];
                    final isCurrent = index == _ps.currentIndex;
                    return _buildChapterRow(ch, index, isCurrent);
                  },
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _buildProgressSlider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_formatDuration(_ps.position), style: Theme.of(context).textTheme.bodySmall),
                  Text(_formatDuration(_ps.duration), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 36), onPressed: _ps.skipPrevious),
                IconButton(icon: _buildSeekButton('15', Icons.replay_10), onPressed: () => _ps.seekRelative(-15)),
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),
                  child: IconButton(
                    icon: Icon(_ps.isPlaying ? Icons.pause : Icons.play_arrow, size: 44,
                        color: Theme.of(context).colorScheme.onPrimary),
                    onPressed: () => _ps.playPause(),
                  ),
                ),
                IconButton(icon: _buildSeekButton('15', Icons.forward_10), onPressed: () => _ps.seekRelative(15)),
                IconButton(icon: const Icon(Icons.skip_next_rounded, size: 36), onPressed: _ps.skipNext),
              ]),
              const SizedBox(height: 4),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildChapterRow(Chapter ch, int index, bool isCurrent) {
    final fileName = ch.fileName;
    final isDownloading = _dlProgress.containsKey(fileName);
    final isError = _dlErrors.contains(fileName);
    final savedMs = widget.storageService.getChapterPosition(_ps.bookName, index);
    final hasProgress = savedMs > 0 && !isCurrent;

    return InkWell(
      onTap: () => _onChapterTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 32,
            child: isCurrent
                ? Icon(Icons.play_arrow, size: 20, color: Theme.of(context).colorScheme.primary)
                : Text('${index + 1}', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ch.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? Theme.of(context).colorScheme.primary : null)),
              if (hasProgress)
                Text('已听 ${_formatPosition(savedMs)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11)),
            ]),
          ),
          SizedBox(
            width: 36,
            child: isCurrent
                ? Icon(Icons.volume_up, size: 18, color: Theme.of(context).colorScheme.primary)
                : isError
                    ? _buildRedDot(ch)
                    : isDownloading
                        ? _buildOrangePulseDot()
                        : ch.downloaded
                            ? _buildGreenDot()
                            : _buildDownloadButton(ch),
          ),
        ]),
      ),
    );
  }

  Widget _buildDownloadButton(Chapter ch) {
    return IconButton(
      icon: const Icon(Icons.download, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => _downloadChapter(ch),
    );
  }

  Widget _buildOrangePulseDot() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Opacity(
        opacity: 0.4 + (_pulseCtrl.value * 0.6),
        child: child,
      ),
      child: Container(width: 8, height: 8,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.orange)),
    );
  }

  Widget _buildRedDot(Chapter ch) {
    return GestureDetector(
      onTap: () => _downloadChapter(ch),
      child: Container(width: 8, height: 8,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
    );
  }

  Widget _buildGreenDot() {
    return Container(width: 8, height: 8,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green));
  }

  Widget _buildSeekButton(String label, IconData icon) {
    return Stack(alignment: Alignment.center, children: [
      Icon(icon, size: 32),
      Positioned(bottom: 0,
          child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))),
    ]);
  }

  Widget _buildSleepTimerButton() {
    if (_ps.sleepMode == SleepMode.off) {
      return ActionChip(avatar: const Icon(Icons.timer_outlined, size: 18), label: const Text('定时关闭'), onPressed: _showTimerDialog);
    }
    String label = _ps.sleepMode == SleepMode.minutes ? '⏱ ${_ps.sleepRemainingMinutes}分钟' : '⏱ 剩${_ps.sleepRemainingChapters}集';
    return ActionChip(
        avatar: const Icon(Icons.timer, size: 18, color: Colors.orange),
        label: Text(label),
        backgroundColor: Colors.orange.withAlpha(30),
        onPressed: _showTimerDialog);
  }

  Widget _buildSpeedButton() {
    final speed = _ps.speed;
    final label = speed == 1.0 ? '1.0x' : speed == 1.25 ? '1.25x' : '${speed}x';
    return ActionChip(avatar: const Icon(Icons.speed, size: 18), label: Text(label), onPressed: () {
      final speeds = [1.0, 1.25, 1.5, 0.75];
      final nextIndex = (speeds.indexOf(speed) + 1) % speeds.length;
      _ps.setSpeed(speeds[nextIndex]);
    });
  }

  Widget _buildProgressSlider() {
    final duration = _ps.duration;
    final position = _ps.position;
    if (duration == null) return const Slider(value: 0, onChanged: null);
    return Slider(
      value: (position?.inMilliseconds ?? 0).clamp(0, duration.inMilliseconds).toDouble(),
      max: duration.inMilliseconds.toDouble(),
      onChanged: (value) => _ps.seek(Duration(milliseconds: value.toInt())),
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPosition(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }
}
