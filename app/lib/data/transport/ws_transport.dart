// WebSocket-based PeerTransport.
//
// Flow per connection:
//   1. Connect to relay WS
//   2. Ed25519 challenge-response (hello → challenge → auth)
//   3. After auth, two parallel streams of inbound frames:
//        - envelope frames `{peer, ct}` → decoded to the peer queue
//        - control frames (top-level `type`, no `peer`) → control stream
//      Outbound `subscribe_presence` / `presence_check` go raw too.
//
// `peer` is standard base64 of the destination's Ed25519 pubkey (matches
// the relay registry, populated from the peer's hello). `ct` is base64 of
// the inner-envelope bytes (plain JSON post-rollback, see plano 06).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/protocol/protocol.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../pairing/pair_request_flow.dart';

class WsTransportError implements Exception {
  final String message;
  const WsTransportError(this.message);

  @override
  String toString() => 'WsTransportError: $message';
}

class WsTransport implements PeerTransport, IControlLink {
  final WebSocketChannel _ws;
  final _queue = _MsgQueue();
  final _controlController =
      StreamController<ControlInbound>.broadcast();

  WsTransport._(this._ws);

  // Connect, authenticate with relay, and return a ready transport.
  static Future<WsTransport> connect({
    required String relayUrl,
    required String peerPubkey, // base64 standard or url — destination peer
    required SimpleKeyPair ed25519Key, // this device's Ed25519 long-term key
  }) async {
    // Plan-18 follow-up — set a WS-level pingInterval (RFC 6455
    // control frames). This keeps the TCP connection alive through
    // NAT / corporate proxies that aggressively close idle sockets,
    // and surfaces a dead WS as `onDone` / `onError` instead of
    // letting it silently linger until the next user action. The
    // protocol-level Ping/Pong handled by ConnectionManager covers
    // app↔Pi liveness; this one covers app↔relay TCP liveness.
    final WebSocketChannel ws = IOWebSocketChannel.connect(
      Uri.parse(relayUrl),
      pingInterval: const Duration(seconds: 20),
    );
    final transport = WsTransport._(ws);

    final challengeCompleter = Completer<Map<String, dynamic>>();
    bool authDone = false;

    final sub = ws.stream.listen(
      (raw) {
        if (!authDone) {
          try {
            challengeCompleter.complete(
              jsonDecode(raw as String) as Map<String, dynamic>,
            );
          } catch (e) {
            if (!challengeCompleter.isCompleted) {
              challengeCompleter.completeError(e);
            }
          }
          return;
        }
        try {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          // Envelope: {peer, room?, ct} → enqueue payload bytes.
          if (frame.containsKey('peer') && frame.containsKey('ct')) {
            final bytes = _b64Decode(frame['ct'] as String);
            final senderRoom = frame['room'] as String?;
            final senderRoomFmt = senderRoom == null
                ? 'absent'
                : senderRoom.length > 16
                    ? '${senderRoom.substring(0, 16)}…'
                    : senderRoom;
            // Plan-18 follow-up — DEMUX inbound by sender room.
            // SessionRepository is singleton; without this guard,
            // AgentChunks for a chat the user just left bleed into
            // the chat they're now viewing (singleton _state.streaming
            // gets contaminated). When senderRoom doesn't match the
            // currently-addressed Pi cwd, drop the payload. The
            // missed messages get reconciled via session_sync the
            // next time the user enters that room.
            //
            // Legacy Pis that don't carry `room` (senderRoom == null)
            // are still routed through unconditionally — same
            // behaviour as before the room demux landed.
            if (senderRoom != null && senderRoom != transport._activeRoom) {
              debugPrint(
                '[ws-raw] envelope DROPPED room-mismatch '
                'peer=${(frame['peer'] as String).substring(0, 8)}… '
                'sender_room=$senderRoomFmt '
                'active_room=${transport._activeRoom} '
                'ct.bytes=${bytes.length} '
                '(reconciled via session_sync on next visit)',
              );
              return;
            }
            debugPrint(
              '[ws-raw] envelope peer=${(frame['peer'] as String).substring(0, 8)}… '
              'sender_room=$senderRoomFmt ct.bytes=${bytes.length}',
            );
            transport._queue.add(bytes);
            return;
          }
          // Control: top-level `type` only → presence stream.
          final ctrl = ControlInbound.tryFromJson(frame);
          if (ctrl != null && !transport._controlController.isClosed) {
            debugPrint('[ws-raw] control type=${frame['type']}');
            transport._controlController.add(ctrl);
            return;
          }
          // Anything else: unknown shape. Was silently dropped — surface
          // it so we can diagnose "session_history nunca chegou" cases.
          final rawStr = raw.toString();
          final preview =
              rawStr.length > 160 ? '${rawStr.substring(0, 160)}…' : rawStr;
          debugPrint('[ws-raw] UNKNOWN frame shape: $preview');
        } catch (e, st) {
          // Was silently dropped → kept us blind to malformed payloads.
          final rawStr = raw.toString();
          final preview =
              rawStr.length > 160 ? '${rawStr.substring(0, 160)}…' : rawStr;
          debugPrint(
            '[ws-raw] decode ERROR: $e | preview=$preview '
            '| stack=${st.toString().split("\n").take(2).join(" | ")}',
          );
        }
      },
      onError: (e) {
        if (!challengeCompleter.isCompleted) challengeCompleter.completeError(e);
        transport._queue.error(e);
      },
      onDone: () {
        if (!challengeCompleter.isCompleted) {
          challengeCompleter.completeError(const WsTransportError('WS closed during auth'));
        }
        transport._queue.close();
        if (!transport._controlController.isClosed) {
          transport._controlController.close();
        }
      },
    );

    try {
      // 1. Hello (standard base64 — matches relay registry format).
      // Plan 17: app is a client (no cwd) and always announces itself
      // on the canonical 'main' room. Pi-side hellos include their own
      // room_id (one per cwd) AND room_meta; that's not our concern here.
      final pub = await ed25519Key.extractPublicKey();
      ws.sink.add(jsonEncode({
        'type': 'hello',
        'pubkey': base64.encode(pub.bytes),
        'room_id': 'main',
      }));

      // 2. Challenge
      final ch = await challengeCompleter.future;
      if (ch['type'] != 'challenge') {
        throw WsTransportError('Expected challenge, got ${ch['type']}');
      }
      final nonce = _b64Decode(ch['nonce'] as String);

      // 3. Auth
      final sig = await Ed25519().sign(nonce, keyPair: ed25519Key);
      ws.sink.add(jsonEncode({
        'type': 'auth',
        'sig': base64.encode(sig.bytes),
      }));
      authDone = true;

      transport._peerPubkey = _normalizeToStandard(peerPubkey);
      transport._sub = sub;
      return transport;
    } catch (e) {
      await sub.cancel();
      await ws.sink.close();
      rethrow;
    }
  }

  String _peerPubkey = '';
  StreamSubscription? _sub;

  /// Active target room on the Pi side. Plan 17: set via
  /// `setActiveRoom`, defaults to 'main' when unset. The outer envelope
  /// embeds this so the Pi can route the inner message to the right
  /// per-cwd session.
  String _activeRoom = 'main';

  /// Override the destination room (Pi side). The app remains on the
  /// 'main' room itself (that's what we sent in `hello.room_id`).
  void setActiveRoom(String room) {
    if (room == _activeRoom) {
      debugPrint(
        '[ws-tx] setActiveRoom no-op (already $_activeRoom)',
      );
      return;
    }
    debugPrint('[ws-tx] setActiveRoom $_activeRoom → $room');
    _activeRoom = room;
  }

  @override
  Future<void> send(Uint8List data) async {
    // Peek the inner JSON to log the outbound message type — helpful
    // when chasing "why didn't this reach Pi" issues.
    String typePeek = '?';
    try {
      final inner = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      typePeek = inner['type']?.toString() ?? '?';
    } catch (_) {/* keep '?' */}
    debugPrint(
      '[ws-tx] type=$typePeek bytes=${data.length} '
      'peer=${_peerPubkey.isEmpty ? "?" : "${_peerPubkey.substring(0, 8)}…"} '
      'room=$_activeRoom',
    );
    _ws.sink.add(jsonEncode({
      'peer': _peerPubkey,
      'room': _activeRoom,
      'ct': base64.encode(data),
    }));
  }

  @override
  Future<Uint8List> receive() => _queue.next();

  // ---- IControlLink --------------------------------------------------------

  @override
  Stream<ControlInbound> get controlFrames => _controlController.stream;

  @override
  void sendControl(Map<String, dynamic> json) {
    _ws.sink.add(jsonEncode(json));
  }

  // -------------------------------------------------------------------------

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _ws.sink.close();
    _queue.close();
    if (!_controlController.isClosed) await _controlController.close();
  }
}

// ---------------------------------------------------------------------------

class _MsgQueue {
  final _buf = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];
  bool _closed = false;

  void add(Uint8List msg) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(msg);
    } else if (!_closed) {
      _buf.add(msg);
    }
  }

  void error(Object e) {
    for (final w in _waiters) {
      w.completeError(e);
    }
    _waiters.clear();
    _closed = true;
  }

  void close() {
    for (final w in _waiters) {
      w.completeError(const WsTransportError('transport closed'));
    }
    _waiters.clear();
    _closed = true;
  }

  Future<Uint8List> next() {
    if (_closed) return Future.error(const WsTransportError('transport closed'));
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    final c = Completer<Uint8List>();
    _waiters.add(c);
    return c.future;
  }
}

// Decodes standard or url-safe base64 (pads defensively).
Uint8List _b64Decode(String s) {
  final pad = (4 - s.length % 4) % 4;
  final padded = s + '=' * pad;
  try {
    return base64.decode(padded);
  } on FormatException {
    return base64Url.decode(padded);
  }
}

// Relay registry uses standard base64 (from each peer's hello). QR/storage
// may carry url-safe encoding — re-encode to standard so the relay matches.
String _normalizeToStandard(String pubkey) {
  try {
    final pad = (4 - pubkey.length % 4) % 4;
    final bytes = base64Url.decode(pubkey + '=' * pad);
    return base64.encode(bytes);
  } catch (_) {
    return pubkey;
  }
}
