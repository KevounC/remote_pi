// Plan/31 — read-only projection of the cross-session index for Home. Watches
// the durable `sessions_index` box; INCREMENTAL projection per BoxEvent.

import 'dart:async';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/domain/contracts/repository.dart';

class HomeReadRepository extends Repository {
  HomeReadRepository(this._boxes);

  final LocalBoxes _boxes;

  /// Reactive list of session-index rows (working/idle + last message). Home
  /// overlays this onto its peer/room tiles derived from ConnectionManager.
  ///
  /// Durable rows are session-scoped (`peer:room:session_id`). Compatibility
  /// peer+room rows from older builds are ignored by [SessionIndexRecord]
  /// because they lack `session_id`; room reachability remains supplied by the
  /// runtime/ConnectionManager path instead of this transcript index.
  Stream<List<SessionIndexRecord>> watchSessions() {
    final box = _boxes.sessionsIndexBox();
    final byKey = <String, SessionIndexRecord>{};
    StreamSubscription? sub;
    late final StreamController<List<SessionIndexRecord>> controller;
    controller = StreamController<List<SessionIndexRecord>>(
      onListen: () {
        for (final k in box.keys) {
          final r = box.get(k);
          if (r is Map) {
            final record = SessionIndexRecord.tryFromJson(
              r.cast<String, dynamic>(),
            );
            if (record != null) byKey['$k'] = record;
          }
        }
        if (!controller.isClosed) controller.add(byKey.values.toList());
        sub = box.watch().listen((event) {
          final key = '${event.key}';
          if (event.deleted) {
            byKey.remove(key);
          } else {
            final r = box.get(event.key);
            if (r is Map) {
              final record = SessionIndexRecord.tryFromJson(
                r.cast<String, dynamic>(),
              );
              if (record == null) {
                byKey.remove(key);
              } else {
                byKey[key] = record;
              }
            }
          }
          if (!controller.isClosed) controller.add(byKey.values.toList());
        });
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Current snapshot (non-reactive) — used to seed a ViewModel synchronously.
  /// Uses the same session-scoped filtering as [watchSessions].
  Map<String, SessionIndexRecord> snapshot() {
    final box = _boxes.sessionsIndexBox();
    final out = <String, SessionIndexRecord>{};
    for (final k in box.keys) {
      final r = box.get(k);
      if (r is Map) {
        final record = SessionIndexRecord.tryFromJson(
          r.cast<String, dynamic>(),
        );
        if (record != null) out['$k'] = record;
      }
    }
    return out;
  }
}
