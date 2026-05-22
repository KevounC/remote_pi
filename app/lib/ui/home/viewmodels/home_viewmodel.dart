import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/home/states/home_state.dart';

/// HomeViewModel — passive list of paired peers + live presence dots
/// + rooms discovered on each peer (plan 17). A single tile per
/// (peer, room).
///
/// The WS connection is owned by [ConnectionManager] from app boot (plano
/// 12). Home only:
///   - reads the peer list from storage
///   - watches `presenceStream` + `roomsStream` to render dots / rooms
///     in real time
///   - writes [Preferences.selectedRoom] when the user taps a tile so
///     `/chat` knows which (peer, room) to address
class HomeViewModel extends ViewModel<HomeState> {
  final PairingStorage _storage;
  final Preferences _prefs;
  final ConnectionManager _conn;
  final ISessionRepository _repo;
  StreamSubscription<Map<String, PresenceState>>? _presenceSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<({String? epk, String? roomId})>? _workingSub;
  bool _relayConnected = false;
  String? _workingEpk;
  String? _workingRoomId;
  bool _disposed = false;

  HomeViewModel(this._storage, this._prefs, this._conn, this._repo)
      : super(const HomeLoading()) {
    _relayConnected = _conn.status is StatusOnline;
    _workingEpk = _repo.workingEpk;
    _workingRoomId = _repo.workingRoomId;
    _load();
    _presenceSub = _conn.presenceStream.listen(_onPresence);
    _roomsSub = _conn.roomsStream.listen(_onRooms);
    _statusSub = _conn.statusStream.listen(_onStatus);
    _workingSub = _repo.workingStream.listen(_onWorking);
  }

  /// `true` when the app's WS to the relay is alive (StatusOnline).
  /// When `false`, every room dot should render in the "reconnecting"
  /// colour (amber) regardless of `isRoomLive`, because the app has
  /// no fresh signal on any room.
  bool get isRelayConnected => _relayConnected;

  /// Plan-18 follow-up — `true` when `(epk, roomId)` is the room
  /// whose agent is currently streaming. Drives the blue "working"
  /// dot on the corresponding Home tile. Limited to the single
  /// currently-active room (room-demux drops chunks from non-active
  /// rooms); a future Pi-side `room_busy` control frame can widen
  /// this to all rooms.
  bool isRoomWorking(String epk, String roomId) {
    if (_workingEpk == null || _workingRoomId == null) return false;
    return _workingEpk == epk && _workingRoomId == roomId;
  }

  /// Plan-18 follow-up — expose just the working peer (without room).
  /// The Home large-title subtitle uses this to flip the global
  /// status to "Working" when any active room of that peer is
  /// streaming.
  String? get workingEpk => _workingEpk;

  Future<void> _load() async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (peers.isEmpty) {
      emit(const HomeNoPeer());
      return;
    }
    // Make sure the relay is pushing updates for everyone we know about;
    // the call is idempotent so this is safe even mid-session. The same
    // subscribe also covers rooms (plan 17 — replay block in
    // ConnectionManager sends both presence and rooms subscribes).
    _conn.subscribeToPeers(peers.map((p) => p.remoteEpk).toList());
    emit(HomeList(
      peers: peers,
      statusByEpk: _conn.presenceSnapshot,
      roomsByPeer: _conn.roomsSnapshot,
    ));
  }

  void _onPresence(Map<String, PresenceState> snapshot) {
    final s = state;
    if (s is! HomeList) return;
    emit(s.copyWith(statusByEpk: snapshot));
  }

  void _onRooms(Map<String, List<RoomInfo>> snapshot) {
    final s = state;
    if (s is! HomeList) return;
    emit(s.copyWith(roomsByPeer: snapshot));
  }

  void _onWorking(({String? epk, String? roomId}) w) {
    if (_workingEpk == w.epk && _workingRoomId == w.roomId) return;
    _workingEpk = w.epk;
    _workingRoomId = w.roomId;
    final s = state;
    if (s is HomeList) {
      emit(HomeList(
        peers: s.peers,
        statusByEpk: s.statusByEpk,
        roomsByPeer: s.roomsByPeer,
      ));
    }
  }

  void _onStatus(ConnectionStatus status) {
    final next = status is StatusOnline;
    if (next == _relayConnected) return;
    _relayConnected = next;
    // Trigger a re-render of any HomeList so tiles re-evaluate dot
    // colour (room-live vs reconnecting).
    final s = state;
    if (s is HomeList) {
      // emit a duplicate-looking HomeList so context.watch() triggers
      // even though peers / roomsByPeer / presence didn't change.
      emit(HomeList(
        peers: s.peers,
        statusByEpk: s.statusByEpk,
        roomsByPeer: s.roomsByPeer,
      ));
    }
  }

  /// Remember which (peer, room) the user picked. Falls back to
  /// `roomId='main'` when the caller doesn't supply one (legacy /
  /// pre-room-announce). Also flips the ConnectionManager's active
  /// room so subsequent sends carry the right outer envelope.
  Future<void> openSession(String epk, {String? roomId}) async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (!peers.any((p) => p.remoteEpk == epk)) return;
    final effectiveRoom = (roomId == null || roomId.isEmpty) ? 'main' : roomId;
    await _prefs.setSelectedRoom(epk: epk, roomId: effectiveRoom);
    // Tell the manager which Pi-side room to address. Safe to call
    // even if the manager is mid-connect (room is applied on the next
    // send and any active StatusOnline channel).
    _conn.switchRoom(effectiveRoom);
  }

  /// Helper for widgets: pass a peer's url-safe epk → returns standard
  /// for indexing into [HomeList.roomsByPeer] / [HomeList.statusByEpk].
  static String normalizeEpkForLookup(String epk) => toStandardB64(epk);

  /// Plan-17 follow-up — `true` if `(epk, roomId)` is currently live on
  /// the relay. Drives the presence dot on each tile (per-room, not
  /// per-peer anymore).
  bool isRoomLive(String epk, String roomId) =>
      _conn.isRoomLive(epk, roomId);

  /// Long-press menu — rename a single room locally (Pi never sees it).
  Future<void> renameRoom(String epk, String roomId, String? name) =>
      _conn.setRoomLocalName(epk, roomId, name);

  /// Long-press menu — delete a cached room locally. Caller should
  /// gate on `!isRoomLive` (only offline rooms can be removed).
  Future<void> deleteRoom(String epk, String roomId) =>
      _conn.deleteCachedRoom(epk, roomId);

  @override
  void dispose() {
    _disposed = true;
    _presenceSub?.cancel();
    _roomsSub?.cancel();
    _statusSub?.cancel();
    _workingSub?.cancel();
    super.dispose();
  }
}
