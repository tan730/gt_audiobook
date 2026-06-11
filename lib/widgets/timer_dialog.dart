import 'package:flutter/material.dart';
import '../services/player_service.dart';

/// 定时关闭选择弹窗
class TimerDialog extends StatefulWidget {
  final SleepMode currentMode;
  final int remainingMinutes;
  final int remainingChapters;
  final void Function(int minutes)? onSetTimer;
  final void Function(int chapters)? onSetChapterTimer;
  final VoidCallback? onCancel;

  const TimerDialog({
    super.key,
    this.currentMode = SleepMode.off,
    this.remainingMinutes = 0,
    this.remainingChapters = 0,
    this.onSetTimer,
    this.onSetChapterTimer,
    this.onCancel,
  });

  @override
  State<TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<TimerDialog> {
  final _chapterController = TextEditingController();

  @override
  void dispose() {
    _chapterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text('定时关闭',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                // 取消定时按钮
                if (widget.currentMode != SleepMode.off)
                  TextButton.icon(
                    onPressed: () {
                      widget.onCancel?.call();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('取消定时'),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 定时模式选择
            Text('定时关闭后', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTimeChip('10分钟', 10),
                _buildTimeChip('20分钟', 20),
                _buildTimeChip('30分钟', 30),
                _buildTimeChip('40分钟', 40),
                _buildTimeChip('60分钟', 60),
              ],
            ),

            const SizedBox(height: 20),

            Text('播放完指定集数后',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChapterChip('本集', 0),
                _buildChapterChip('1集', 1),
                _buildChapterChip('2集', 2),
                _buildChapterChip('3集', 3),
                _buildChapterChip('4集', 4),
                _buildChapterChip('5集', 5),
              ],
            ),

            const SizedBox(height: 12),

            // 自定义集数
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _chapterController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '自定义',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final n = int.tryParse(_chapterController.text);
                    if (n != null && n > 0) {
                      widget.onSetChapterTimer?.call(n);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('设置'),
                ),
              ],
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeChip(String label, int minutes) {
    final isActive = widget.currentMode == SleepMode.minutes &&
        (widget.remainingMinutes == minutes ||
            (widget.remainingMinutes >= minutes - 1 &&
                widget.remainingMinutes <= minutes + 1));

    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) {
        widget.onSetTimer?.call(minutes);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildChapterChip(String label, int chapters) {
    final isActive = widget.currentMode == SleepMode.chapters &&
        widget.remainingChapters == chapters;

    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) {
        widget.onSetChapterTimer?.call(chapters);
        Navigator.pop(context);
      },
    );
  }
}
