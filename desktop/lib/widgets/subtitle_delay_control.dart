import 'package:flutter/material.dart';

Duration subtitlePosition(Duration videoPosition, Duration delay) =>
    videoPosition - delay;

class SubtitleDelayControl extends StatefulWidget {
  final int initialMilliseconds;
  final ValueChanged<int> onChanged;
  const SubtitleDelayControl({
    super.key,
    this.initialMilliseconds = 0,
    required this.onChanged,
  });
  @override
  State<SubtitleDelayControl> createState() => _SubtitleDelayState();
}

class _SubtitleDelayState extends State<SubtitleDelayControl> {
  late int milliseconds = widget.initialMilliseconds;
  void change(int value) {
    setState(() => milliseconds = value.clamp(-30000, 30000));
    widget.onChanged(milliseconds);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Subtitle delay',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            IconButton(
              tooltip: 'Subtitles 100 ms earlier',
              onPressed: () => change(milliseconds - 100),
              icon: const Icon(Icons.remove),
            ),
            Text(
              '${milliseconds >= 0 ? '+' : ''}${(milliseconds / 1000).toStringAsFixed(1)} s',
            ),
            IconButton(
              tooltip: 'Subtitles 100 ms later',
              onPressed: () => change(milliseconds + 100),
              icon: const Icon(Icons.add),
            ),
            TextButton(onPressed: () => change(0), child: const Text('Reset')),
          ],
        ),
        const Text(
          'Positive values show subtitles later; negative values show them earlier.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
