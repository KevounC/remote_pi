import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:app/ui/chat/widgets/message_bubble.dart';
import 'package:app/ui/chat/widgets/offline_banner.dart';
import 'package:app/ui/chat/widgets/streaming_bubble.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChatViewModel>().state;
    final vm = context.read<ChatViewModel>();

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, state),
            if (state is ChatReady)
              OfflineBanner(
                status: state.isOffline
                    ? const StatusRetrying(
                        nextRetry: Duration(seconds: 1),
                        attempt: 0,
                      )
                    : const StatusOnline(_NullChannel()),
                onRePair: () => context.go('/pair'),
              ),
            Expanded(child: _buildBody(context, state, vm)),
            _buildInput(state, vm),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ChatState state) {
    final title = state is ChatReady && state.messages.isNotEmpty
        ? _inferSessionName(state.messages)
        : 'Remote Pi';

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: kBg,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: kMono,
                    fontSize: 13,
                    color: kText,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    const Icon(Icons.lock_outline, color: kMuted, size: 9),
                    const SizedBox(width: 4),
                    const Text(
                      'E2E',
                      style: TextStyle(
                        fontFamily: kMono,
                        fontSize: 10,
                        color: kMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFFB5B5B5)),
            onPressed: () => context.push('/settings'),
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ChatState state, ChatViewModel vm) {
    return switch (state) {
      ChatNoPeer() => _EmptyState(
        icon: Icons.qr_code_scanner,
        message: 'No device paired',
        actionLabel: 'Scan QR',
        onAction: () => context.go('/pair'),
      ),
      ChatConnecting() => const _EmptyState(
        icon: Icons.sync_rounded,
        message: 'Connecting…',
      ),
      ChatFatalError(:final message) => _EmptyState(
        icon: Icons.error_outline_rounded,
        message: message,
        actionLabel: 'Re-pair',
        onAction: () => context.go('/pair'),
      ),
      ChatReady(:final messages, :final streaming) => _MessageList(
        messages: messages,
        streaming: streaming,
        onDecide: (id, decision) => vm.approveTool(id, decision),
      ),
    };
  }

  Widget _buildInput(ChatState state, ChatViewModel vm) {
    final isReady = state is ChatReady;
    final isOffline = isReady && state.isOffline;
    final isStreaming = isReady && state.streaming != null;
    final streamingId = isReady ? state.streaming?.inReplyTo : null;

    return InputBar(
      disabled: !isReady || isOffline,
      streaming: isStreaming,
      onSend: (text) => vm.sendMessage(text),
      onCancel: streamingId != null
          ? () => vm.cancel(streamingId)
          : null,
    );
  }

  static String _inferSessionName(List<ChatMessage> msgs) {
    for (final m in msgs) {
      if (m is UserMsg) return m.text.substring(0, m.text.length.clamp(0, 32));
    }
    return 'Remote Pi';
  }
}

// ---------------------------------------------------------------------------

class _MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final void Function(String, ApproveDecision) onDecide;

  const _MessageList({
    required this.messages,
    required this.streaming,
    required this.onDecide,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scroll = ScrollController();
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.userScrollDirection.name == 'reverse') {
        _userScrolled = true;
      }
      if (_scroll.position.pixels < 20) _userScrolled = false;
    });
  }

  @override
  void didUpdateWidget(_MessageList old) {
    super.didUpdateWidget(old);
    if (!_userScrolled) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount =
        widget.messages.length + (widget.streaming != null ? 1 : 0);

    return ListView.separated(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      itemCount: itemCount,
      separatorBuilder: (context, idx) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        // Index 0 = bottom = newest
        if (widget.streaming != null && i == 0) {
          return StreamingBubble(widget.streaming!);
        }
        final msgIdx = widget.messages.length -
            1 -
            (i - (widget.streaming != null ? 1 : 0));
        final msg = widget.messages[msgIdx];
        return switch (msg) {
          UserMsg() => UserBubble(msg),
          AssistantMsg() => AssistantBubble(msg),
          ToolEvent() => ToolRequestCard(
            tool: msg,
            onDecide: widget.onDecide,
          ),
        };
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kMuted, size: 48),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: kMuted, fontSize: 14)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.black,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

// Dummy IChannel so StatusOnline(const _NullChannel()) satisfies the type.
class _NullChannel implements IChannel {
  const _NullChannel();

  @override Stream<ServerMessage> get serverMessages => const Stream.empty();
  @override Future<void> send(ClientMessage msg) async {}
  @override Future<void> close() async {}
}
