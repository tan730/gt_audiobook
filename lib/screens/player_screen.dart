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
  final Set<String> _dlErrors = {};
  Set<String> _queuedFiles = {};
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
    widget.downloadService.onProgress = (bookName, fileName, progress) async {
      if (mounted) {
        setState(() => _dlProgress = Map.from(widget.downloadService.downloadProgress));
        // 下载完成时刷新该章节的 downloaded 标志（图标从下载→绿点）
        if (progress >= 1.0 && bookName == _ps.bookName) {
          final idx = _ps.chapters.indexWhere((c) => c.fileName == fileName);
          if (idx >= 0 && await widget.downloadService.isDownloaded(bookName, fileName)) {
            _ps.chapters[idx].downloaded = true;
          }
        }
      }
      origCb?.call(bookName, fileName, progress);
    };

    // 监听队列变化
    widget.downloadService.onQueueChanged = () {
      if (mounted) {
        setState(() {
          _queuedFiles = Set.from(widget.downloadService.queuedFiles);
          _dlProgress = Map.from(widget.downloadService.downloadProgress);
        });
      }
    };

    _checkDownloads();
    // 首帧渲染后延迟滚动到当前播放集居中
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
    // 跟 ListView.itemExtent 必须保持一致
    const itemHeight = 40.0;
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
                  // 固定每行 40px，跟章节行实际高度一致
                  // （图标 32 + Padding vertical: 2×2 + 文字行高 ~32）
                  // 强制 itemExtent 后 ListView 自己保证每行真实高 = 40px
                  // _scrollToCurrent 直接用此值算居中偏移，不需要猜
                  itemExtent: 40,
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
                IconButton(icon: _buildSeekButton('10', Icons.replay_10), onPressed: () => _ps.seekRelative(-10)),
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),
                  child: IconButton(
                    icon: Icon(_ps.isPlaying ? Icons.pause : Icons.play_arrow, size: 44,
                        color: Theme.of(context).colorScheme.onPrimary),
                    onPressed: () => _ps.playPause(),
                  ),
                ),
                IconButton(icon: _buildSeekButton('10', Icons.forward_10), onPressed: () => _ps.seekRelative(10)),
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
    final isQueued = _queuedFiles.contains(fileName);
    final isError = _dlErrors.contains(fileName);
    final savedMs = widget.storageService.getChapterPosition(_ps.bookName, index);
    final hasProgress = savedMs > 0 && !isCurrent;

    // 用 Listener 替代 InkWell：自己控制"滑动 vs 点击"判断
    // 阈值 8.0 逻辑像素：比 Flutter InkWell 内部 kTouchSlop(18) 严格，
    // 比 4.0 宽松，正常点击能触发，小幅滑动/抖动不会误触
    return Listener(
      // translucent: 让事件同时穿透给 ListView，自己也能收到 PointerUp
      // opaque 会拦截 ListView 的滚动手势，反而导致列表卡住
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _chapterPointerDown[index] = event.position;
      },
      onPointerUp: (event) {
        _handleChapterRowTap(event, index);
      },
      onPointerCancel: (_) {
        _chapterPointerDown.remove(index);
      },
      child: InkWell(
        onTap: () {}, // 禁用 InkWell 默认 onTap，由 Listener 接管
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
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
                  if (isDownloading)
                    Text('下载中',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange, fontSize: 11))
                  else if (isQueued)
                    Text('排队中',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey, fontSize: 11))
                  else if (hasProgress)
                    Text('已听 ${_formatPosition(savedMs)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11)),
                ]),
              ),
              SizedBox(
                width: 36,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: isCurrent
                      ? Center(child: Icon(Icons.volume_up, size: 18, color: Theme.of(context).colorScheme.primary))
                      : isError
                          ? _buildRedDot(ch)
                          : isDownloading
                              ? _buildProgressIcon(fileName)
                              : isQueued
                                  ? _buildQueuedIcon(fileName)
                                  : ch.downloaded
                                      ? _buildGreenDot()
                                      : _buildDownloadButton(ch),
                ),
              ),
            ]),
            // 播放页不再显示下载进度条，统一由下载页展示
            // 行高固定 = 主 Row 32 + 外层 Padding vertical: 2×2 = 36，itemExtent=40 留 4px 余量
          ],
        ),
        ),
      ),
    );
  }

  /// 章节行点击处理：滑动距离 > 8 逻辑像素视为滑动，不触发播放
  /// 解决 ListView 滚动时小幅位移被 InkWell 误判为 tap 的问题
  static const double _chapterTapSlop = 8.0;
  final Map<int, Offset> _chapterPointerDown = {};

  void _handleChapterRowTap(PointerUpEvent event, int index) {
    final down = _chapterPointerDown.remove(index);
    if (down == null) return;
    final dx = (event.position - down).distance;
    if (dx <= _chapterTapSlop) {
      _onChapterTap(index);
    }
  }

  Widget _buildDownloadButton(Chapter ch) {
    // 不用 IconButton 是因为它内部硬约束最小 32×32，且视觉密度会撑高
    // 自己用 InkWell 包裸 Icon + 固定 32×32 容器，跟绿点/红点行高完全一致
    return InkWell(
      onTap: () => _downloadChapter(ch),
      child: const SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: Icon(Icons.download, size: 18),
        ),
      ),
    );
  }

  Widget _buildProgressIcon(String fileName) {
    // 闪烁橙色圆点：大小随 _pulseCtrl 动画在 6-10px 之间变化
    return GestureDetector(
      onTap: () {
        widget.downloadService.cancelDownload(fileName);
        setState(() {});
      },
      child: Tooltip(
        message: '点击取消下载',
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                // 0..1 映射到 6..10px
                final size = 6 + 4 * _pulseCtrl.value;
                return SizedBox(
                  width: size,
                  height: size,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQueuedIcon(String fileName) {
    return GestureDetector(
      onTap: () {
        widget.downloadService.cancelDownload(fileName);
          setState(() {});
      },
      child: const Tooltip(
        message: '点击取消排队',
        // 用 32×32 SizedBox 占位，跟未下载按钮尺寸一致，行高不塌
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(Icons.hourglass_empty, size: 18, color: Colors.blueGrey),
          ),
        ),
      ),
    );
  }

  Widget _buildRedDot(Chapter ch) {
    return GestureDetector(
      onTap: () => _downloadChapter(ch),
      // 32×32 占位 + 居中 8×8 红点，跟未下载按钮尺寸一致，行高不塌
      child: const SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGreenDot() {
    // 32×32 占位 + 居中 8×8 绿点，跟未下载按钮尺寸一致，行高不塌
    return const SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: SizedBox(
          width: 8,
          height: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green),
          ),
        ),
      ),
    );
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
