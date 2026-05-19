// ChatViewModel reacts to ISessionRepository stream changes.

import 'dart:async';

import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRepo implements ISessionRepository {
  final _ctrl = StreamController<SessionState>.broadcast(sync: true);
  SessionState _state = const SessionState();

  @override SessionState get current => _state;
  @override Stream<SessionState> get sessionStream => _ctrl.stream;
  @override Future<void> boot() async {}
  @override Future<void> connectTo(PeerRecord p) async {}

  @override
  Future<void> sendMessage(String text) async {
    final id = 'u${_ctrl.hashCode}';
    _push(_state.copyWith(
      messages: [..._state.messages, UserMsg(id: id, text: text)],
      streaming: StreamingMessage(inReplyTo: id),
    ));
  }

  @override Future<void> cancel(String targetId) async {}

  @override
  Future<void> approveTool(String toolCallId, ApproveDecision decision) async {
    final updated = _state.messages.map((m) {
      if (m is ToolEvent && m.toolCallId == toolCallId) {
        return m.copyWith(
          status: decision == ApproveDecision.allow
              ? ToolEventStatus.allowed
              : ToolEventStatus.denied,
        );
      }
      return m;
    }).toList();
    _push(_state.copyWith(messages: updated));
  }

  @override void dispose() => _ctrl.close();
  @override void adoptChannel(IChannel channel, PeerRecord peer) {}
  @override Future<void> disconnect() async {}

  void push(SessionState s) => _push(s);

  void _push(SessionState s) {
    _state = s;
    _ctrl.add(s);
  }
}

class _FakeChannel implements IChannel {
  final _ctrl = StreamController<ServerMessage>.broadcast(sync: true);

  @override Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override Future<void> send(ClientMessage msg) async {}
  @override Future<void> close() async => _ctrl.close();

  void push(ServerMessage msg) => _ctrl.add(msg);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatViewModel', () {
    late _FakeRepo repo;
    late ChatViewModel vm;

    setUp(() {
      repo = _FakeRepo();
      vm = ChatViewModel(repo);
    });

    tearDown(() {
      vm.dispose();
      repo.dispose();
    });

    test('initial state is ChatConnecting', () {
      expect(vm.state, isA<ChatConnecting>());
    });

    test('StatusNoPeer → ChatNoPeer', () {
      repo.push(const SessionState(connection: StatusNoPeer()));
      expect(vm.state, isA<ChatNoPeer>());
    });

    test('StatusOnline → ChatReady with empty messages', () {
      final ch = _FakeChannel();
      repo.push(SessionState(connection: StatusOnline(ch)));
      final s = vm.state;
      expect(s, isA<ChatReady>());
      expect((s as ChatReady).messages, isEmpty);
      expect(s.isOffline, isFalse);
    });

    test('StatusRetrying → ChatReady with isOffline=true', () {
      repo.push(
        const SessionState(
          connection: StatusRetrying(
            nextRetry: Duration(seconds: 2),
            attempt: 1,
          ),
        ),
      );
      expect((vm.state as ChatReady).isOffline, isTrue);
    });

    test('fingerprint mismatch → ChatFatalError', () {
      repo.push(
        const SessionState(
          connection: StatusOffline(
            reason: 'Remote key changed',
            canRetry: false,
          ),
        ),
      );
      expect(vm.state, isA<ChatFatalError>());
      expect((vm.state as ChatFatalError).message, 'Remote key changed');
    });

    test('messages accumulate in ChatReady', () {
      final ch = _FakeChannel();
      const msg1 = UserMsg(id: 'u1', text: 'hi');
      const msg2 = AssistantMsg(id: 'u1', text: 'hello back');
      repo.push(
        SessionState(
          connection: StatusOnline(ch),
          messages: [msg1, msg2],
        ),
      );
      expect((vm.state as ChatReady).messages, [msg1, msg2]);
    });

    test('streaming field propagates to ChatReady', () {
      final ch = _FakeChannel();
      const streaming = StreamingMessage(inReplyTo: 'u1', buffer: 'hello...');
      repo.push(
        SessionState(connection: StatusOnline(ch), streaming: streaming),
      );
      expect((vm.state as ChatReady).streaming, streaming);
    });

    test('sendMessage adds UserMsg', () async {
      await vm.sendMessage('test message');
      expect(repo.current.messages, isNotEmpty);
      expect(repo.current.messages.first, isA<UserMsg>());
      expect((repo.current.messages.first as UserMsg).text, 'test message');
    });

    test('approveTool updates ToolEvent status', () async {
      final ch = _FakeChannel();
      const tool = ToolEvent(
        id: 'tc1',
        toolCallId: 'tc1',
        tool: 'Bash',
        args: {'command': 'ls'},
      );
      repo.push(
        SessionState(connection: StatusOnline(ch), messages: [tool]),
      );

      await vm.approveTool('tc1', ApproveDecision.allow);

      final updated = repo.current.messages.first as ToolEvent;
      expect(updated.status, ToolEventStatus.allowed);
    });

    test('emit deduplicates equal states', () {
      final states = <ChatState>[];
      vm.addListener(() => states.add(vm.state));

      final ch = _FakeChannel();
      final s = SessionState(connection: StatusOnline(ch));
      // Push same state twice → ViewModel should only notify once if state ==
      repo.push(s);
      repo.push(s); // same object, same ==

      // Only 1 notification since state didn't change
      expect(states.length, 1);
    });
  });
}
