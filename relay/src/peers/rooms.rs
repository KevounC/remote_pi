use std::collections::HashMap;
use std::sync::Mutex;

use super::connections::{ConnectionInsert, ConnectionRemove, RoomKey};
use crate::rooms::{RoomMeta, RoomMetaPatch};

#[derive(Debug, Clone)]
pub(crate) struct RoomEnded {
    pub room_id: String,
}

#[derive(Debug, Clone)]
pub(crate) struct RoomMetaPatchResult {
    pub meta: RoomMeta,
}

/// Canonical live room metadata keyed by `(peer_id, room_id)`.
///
/// ConnectionRegistry owns only live socket delivery. This store owns one
/// metadata snapshot per live room so `rooms_check` and `room_meta_update`
/// share the same source of truth. Duplicate connections refresh the snapshot
/// to preserve the old `Vec::last()` compatibility behavior, but only the first
/// connection produces a `room_announced` result.
#[derive(Debug, Default)]
pub(crate) struct RoomStateStore {
    rooms: Mutex<HashMap<RoomKey, RoomMeta>>,
}

impl RoomStateStore {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    pub(crate) fn on_connection_inserted(
        &self,
        peer_id: &str,
        meta: RoomMeta,
        insert: &ConnectionInsert,
    ) -> Option<RoomMeta> {
        let key = (peer_id.to_string(), meta.room_id.clone());
        let mut rooms = self.rooms.lock().unwrap();
        rooms.insert(key, meta.clone());

        insert.is_first_in_room.then_some(meta)
    }

    pub(crate) fn on_connection_removed(
        &self,
        peer_id: &str,
        room_id: &str,
        remove: &ConnectionRemove,
    ) -> Option<RoomEnded> {
        if !remove.room_emptied {
            return None;
        }

        let key = (peer_id.to_string(), room_id.to_string());
        let mut rooms = self.rooms.lock().unwrap();
        rooms.remove(&key);

        Some(RoomEnded {
            room_id: room_id.to_string(),
        })
    }

    pub(crate) fn rooms_of(&self, peer_id: &str) -> Vec<RoomMeta> {
        let rooms = self.rooms.lock().unwrap();
        rooms
            .iter()
            .filter(|((p, _), _)| p == peer_id)
            .map(|(_, meta)| meta.clone())
            .collect()
    }

    pub(crate) fn apply_patch(
        &self,
        peer_id: &str,
        room_id: &str,
        patch: RoomMetaPatch,
    ) -> Option<RoomMetaPatchResult> {
        let key = (peer_id.to_string(), room_id.to_string());
        let mut rooms = self.rooms.lock().unwrap();
        let meta = rooms.get_mut(&key)?;

        if let Some(model) = patch.model {
            meta.model = model;
        }
        if let Some(thinking) = patch.thinking {
            meta.thinking = thinking;
        }
        if let Some(session_id) = patch.session_id {
            meta.session_id = session_id;
        }
        if let Some(working) = patch.working {
            meta.working = working;
        }

        Some(RoomMetaPatchResult { meta: meta.clone() })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_meta(room_id: &str) -> RoomMeta {
        RoomMeta {
            room_id: room_id.into(),
            name: None,
            cwd: None,
            session_id: None,
            model: None,
            thinking: None,
            working: false,
            started_at: 0,
        }
    }

    fn insert(conn_id: u64, is_first_in_room: bool) -> ConnectionInsert {
        ConnectionInsert {
            peer_id: "peer".to_string(),
            conn_id,
            was_offline_before: is_first_in_room,
            is_first_in_room,
        }
    }

    #[test]
    fn duplicate_connection_refreshes_snapshot_without_announcement() {
        let store = RoomStateStore::new();
        let peer = "peer";
        let mut first = make_meta("main");
        first.model = Some("old".to_string());
        let mut second = make_meta("main");
        second.model = Some("new".to_string());
        second.working = true;

        assert!(
            store
                .on_connection_inserted(peer, first, &insert(1, true))
                .is_some()
        );
        assert!(
            store
                .on_connection_inserted(peer, second, &insert(2, false))
                .is_none()
        );

        let rooms = store.rooms_of(peer);
        assert_eq!(rooms.len(), 1);
        assert_eq!(rooms[0].model.as_deref(), Some("new"));
        assert!(rooms[0].working);
    }

    #[test]
    fn patch_preserves_working_absence_and_applies_false() {
        let store = RoomStateStore::new();
        let peer = "peer";
        let mut meta = make_meta("main");
        meta.working = true;
        store.on_connection_inserted(peer, meta, &insert(1, true));

        let model_only = store
            .apply_patch(
                peer,
                "main",
                RoomMetaPatch {
                    model: Some(Some("opus".to_string())),
                    ..Default::default()
                },
            )
            .expect("room exists")
            .meta;
        assert_eq!(model_only.model.as_deref(), Some("opus"));
        assert!(model_only.working, "absent working must preserve true");

        let off = store
            .apply_patch(
                peer,
                "main",
                RoomMetaPatch {
                    working: Some(false),
                    ..Default::default()
                },
            )
            .expect("room exists")
            .meta;
        assert!(!off.working, "working false is a real patch");
    }

    #[test]
    fn last_connection_removes_room() {
        let store = RoomStateStore::new();
        let peer = "peer";
        store.on_connection_inserted(peer, make_meta("main"), &insert(1, true));

        let remove = ConnectionRemove {
            peer_id: peer.to_string(),
            removed_connection: true,
            room_emptied: false,
            peer_offlined: false,
        };
        assert!(store.on_connection_removed(peer, "main", &remove).is_none());
        assert_eq!(store.rooms_of(peer).len(), 1);

        let remove = ConnectionRemove {
            peer_id: peer.to_string(),
            removed_connection: true,
            room_emptied: true,
            peer_offlined: true,
        };
        let ended = store
            .on_connection_removed(peer, "main", &remove)
            .expect("last connection ends room");
        assert_eq!(ended.room_id, "main");
        assert!(store.rooms_of(peer).is_empty());
    }
}
