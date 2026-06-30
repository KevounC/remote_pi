// Plan/31 — read-only projection of the active session's rows + runtime.
// NO channel dependency: it only reads the DB and watches it. Projection is
// INCREMENTAL — it mutates an in-memory map per BoxEvent rather than re-reading
// the whole box (Risk 1 / #defaults).

import 'dart:async';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/domain/contracts/repository.dart';
import 'package:app/domain/entities/remote_session_ref.dart';

class SessionReadRepository extends Repository {
  SessionReadRepository(this._boxes);

  final LocalBoxes _boxes;

  /// Reactive ordered message list for a canonical remote session. Emits the
  /// current snapshot on listen, then an updated list per row change.
  Stream<List<MessageRecord>> watchMessages(RemoteSessionRef ref) {
    final byKey = <int, MessageRecord>{};
    StreamSubscription? sub;
    late final StreamController<List<MessageRecord>> controller;
    controller = StreamController<List<MessageRecord>>(
      onListen: () async {
        final box = await _boxes.msgsBox(ref);
        for (final k in box.keys) {
          byKey[(k as num).toInt()] = MessageRecord.fromJson(
            _coerce(box.get(k)),
          );
        }
        if (!controller.isClosed) controller.add(_sorted(byKey));
        sub = box.watch().listen((event) {
          final key = (event.key as num).toInt();
          if (event.deleted) {
            byKey.remove(key);
          } else {
            // Incremental: read ONLY the changed key, not the whole box.
            byKey[key] = MessageRecord.fromJson(_coerce(box.get(key)));
          }
          if (!controller.isClosed) controller.add(_sorted(byKey));
        });
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Reactive volatile runtime (connection/presence) for `(epk, roomId)`.
  Stream<RuntimeRecord> watchRuntime(String epk, String roomId) {
    final box = _boxes.runtimeBox();
    final key = LocalBoxes.runtimeKey(epk, roomId);
    RuntimeRecord read() {
      final raw = box.get(key);
      return raw is Map
          ? RuntimeRecord.fromJson(raw.cast<String, dynamic>())
          : const RuntimeRecord();
    }

    StreamSubscription? sub;
    late final StreamController<RuntimeRecord> controller;
    controller = StreamController<RuntimeRecord>(
      onListen: () {
        if (!controller.isClosed) controller.add(read());
        sub = box.watch(key: key).listen((_) {
          if (!controller.isClosed) controller.add(read());
        });
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  static List<MessageRecord> _sorted(Map<int, MessageRecord> byKey) {
    final keys = byKey.keys.toList()..sort();
    return [for (final k in keys) byKey[k]!];
  }

  static Map<String, dynamic> _coerce(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return <String, dynamic>{};
  }
}
