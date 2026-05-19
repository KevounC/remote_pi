import 'package:app/domain/session_state.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// UserBubble — right-aligned dark card
// ---------------------------------------------------------------------------

class UserBubble extends StatelessWidget {
  final UserMsg message;
  const UserBubble(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          decoration: BoxDecoration(
            color: kUserBubble,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Text(
            message.text,
            style: kSansBody.copyWith(color: kText),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AssistantBubble — left-aligned monospace text
// ---------------------------------------------------------------------------

class AssistantBubble extends StatelessWidget {
  final AssistantMsg message;
  const AssistantBubble(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: _renderText(message.text),
      ),
    );
  }

  Widget _renderText(String text) {
    // Simple highlight: file paths wrapped in backticks or containing /
    // are colored kHighlight. No full markdown in MVP.
    return Text.rich(
      _parseSpans(text),
      style: kMonoStyle,
    );
  }

  TextSpan _parseSpans(String text) {
    // Minimal inline highlight for file paths (word containing /)
    final spans = <InlineSpan>[];
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final isPath = w.contains('/') || w.contains('.ts') || w.contains('.dart');
      spans.add(
        TextSpan(
          text: i < words.length - 1 ? '$w ' : w,
          style: isPath ? kMonoStyle.copyWith(color: kHighlight) : null,
        ),
      );
    }
    return TextSpan(children: spans);
  }
}
