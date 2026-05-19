import 'package:app/domain/session_state.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';

// StreamingBubble — shows the assistant's growing response + blinking cursor.
// The buffer is already batched with 16ms debounce in SessionRepository.

class StreamingBubble extends StatefulWidget {
  final StreamingMessage streaming;
  const StreamingBubble(this.streaming, {super.key});

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.streaming.buffer.isNotEmpty)
              Flexible(
                child: Text(widget.streaming.buffer, style: kMonoStyle),
              ),
            _BlinkingCursor(controller: _blink),
          ],
        ),
      ),
    );
  }
}

class _BlinkingCursor extends AnimatedWidget {
  const _BlinkingCursor({required AnimationController controller})
    : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final controller = listenable as AnimationController;
    final visible = controller.value < 0.5;
    return Container(
      width: 7,
      height: 14,
      margin: const EdgeInsets.only(left: 3, bottom: 1),
      color: visible ? kAccent : Colors.transparent,
    );
  }
}
