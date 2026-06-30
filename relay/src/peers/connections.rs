use std::collections::HashMap;
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};

use axum::extract::ws::Message;
use tokio::sync::mpsc;

use crate::rooms::{RoomMeta, RoomMetaPatch};

pub(crate) type RoomKey = (String, String); // (peer_id, room_id)

#[derive(Debug)]
pub(crate) struct ConnectionEntry {
    pub conn_id: u64,
    pub room_meta: RoomMeta,
    pub tx: mpsc::UnboundedSender<Message>,
}

#[derive(Debug)]
pub(crate) struct ConnectionInsert {
    pub conn_id: u64,
    pub was_offline_before: bool,
    pub is_first_in_room: bool,
}

#[derive(Debug)]
pub(crate) struct ConnectionRemove {
    pub room_emptied: bool,
    pub peer_offlined: bool,
}

#[derive(Debug)]
pub(crate) struct RoomMetaSnapshot {
    pub model: Option<String>,
    pub thinking: Option<String>,
    pub session_id: Option<String>,
    pub working: bool,
}

/// Owns live relay connection state and delivery over registered senders.
///
/// This table is the single source of truth for which authenticated websocket
/// connections are live at each `(peer_id, room_id)` key. It deliberately keeps
/// `RoomMeta` on each entry for step-1 facade compatibility; later registry
/// split steps move that metadata to a dedicated room-state store.
#[derive(Debug)]
pub(crate) struct ConnectionRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnectionEntry>>>,
}

impl ConnectionRegistry {
    pub(crate) fn new() -> Self {
        Self {
            next_conn: AtomicU64::new(0),
            senders: Mutex::new(HashMap::new()),
        }
    }

    pub(crate) fn insert(
        &self,
        peer_id: &str,
        room_meta: RoomMeta,
        tx: mpsc::UnboundedSender<Message>,
    ) -> ConnectionInsert {
        let room_id = room_meta.room_id.clone();
        let key = (peer_id.to_string(), room_id);
        let conn_id = self.next_conn.fetch_add(1, Ordering::Relaxed);

        let mut lock = self.senders.lock().unwrap();
        let was_offline_before = !lock.keys().any(|(p, _)| p == peer_id);
        let is_first_in_room = !lock.contains_key(&key);
        lock.entry(key).or_default().push(ConnectionEntry {
            conn_id,
            room_meta,
            tx,
        });

        ConnectionInsert {
            conn_id,
            was_offline_before,
            is_first_in_room,
        }
    }

    pub(crate) fn remove(&self, peer_id: &str, room_id: &str, conn_id: u64) -> ConnectionRemove {
        let mut lock = self.senders.lock().unwrap();
        let key = (peer_id.to_string(), room_id.to_string());
        let mut room_emptied = false;

        if let Some(entries) = lock.get_mut(&key) {
            let before = entries.len();
            entries.retain(|entry| entry.conn_id != conn_id);
            let removed_something = entries.len() != before;
            if entries.is_empty() {
                lock.remove(&key);
                room_emptied = removed_something;
            }
        }

        let peer_offlined = room_emptied && !lock.keys().any(|(p, _)| p == peer_id);
        ConnectionRemove {
            room_emptied,
            peer_offlined,
        }
    }

    pub(crate) fn is_online(&self, peer_id: &str) -> bool {
        let lock = self.senders.lock().unwrap();
        lock.keys().any(|(p, _)| p == peer_id)
    }

    pub(crate) fn rooms_of(&self, peer_id: &str) -> Vec<RoomMeta> {
        let lock = self.senders.lock().unwrap();
        let mut by_room: HashMap<String, RoomMeta> = HashMap::new();
        for ((p, _), entries) in lock.iter() {
            if p == peer_id
                && let Some(entry) = entries.last()
            {
                by_room.insert(entry.room_meta.room_id.clone(), entry.room_meta.clone());
            }
        }
        by_room.into_values().collect()
    }

    pub(crate) fn update_room_meta(
        &self,
        peer_id: &str,
        room_id: &str,
        patch: &RoomMetaPatch,
    ) -> Option<RoomMetaSnapshot> {
        let mut lock = self.senders.lock().unwrap();
        let key = (peer_id.to_string(), room_id.to_string());
        let entries = lock.get_mut(&key)?;
        if entries.is_empty() {
            return None;
        }

        for entry in entries.iter_mut() {
            if let Some(ref m) = patch.model {
                entry.room_meta.model = m.clone();
            }
            if let Some(ref t) = patch.thinking {
                entry.room_meta.thinking = t.clone();
            }
            if let Some(ref session_id) = patch.session_id {
                entry.room_meta.session_id = session_id.clone();
            }
            if let Some(w) = patch.working {
                entry.room_meta.working = w;
            }
        }

        entries.first().map(|entry| RoomMetaSnapshot {
            model: entry.room_meta.model.clone(),
            thinking: entry.room_meta.thinking.clone(),
            session_id: entry.room_meta.session_id.clone(),
            working: entry.room_meta.working,
        })
    }

    pub(crate) fn send_to_room(
        &self,
        dest_peer: &str,
        dest_room: &str,
        msg: Message,
        skip_conn_id: u64,
    ) -> bool {
        let lock = self.senders.lock().unwrap();
        let key = (dest_peer.to_string(), dest_room.to_string());
        let Some(entries) = lock.get(&key) else {
            return false;
        };

        let mut delivered = false;
        for entry in entries {
            if entry.conn_id == skip_conn_id {
                continue;
            }
            if entry.tx.send(msg.clone()).is_ok() {
                delivered = true;
            }
        }
        delivered
    }

    pub(crate) fn send_to_peer(&self, peer_id: &str, msg: Message) -> bool {
        let mut sent = false;
        let lock = self.senders.lock().unwrap();
        for ((p, _), entries) in lock.iter() {
            if p == peer_id {
                for entry in entries {
                    let _ = entry.tx.send(msg.clone());
                    sent = true;
                }
            }
        }
        sent
    }

    pub(crate) fn send_to_all_rooms_of(&self, peer_id: &str, msg: Message) -> bool {
        self.send_to_peer(peer_id, msg)
    }
}

impl Default for ConnectionRegistry {
    fn default() -> Self {
        Self::new()
    }
}
