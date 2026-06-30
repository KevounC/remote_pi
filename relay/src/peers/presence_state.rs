use super::connections::{ConnectionInsert, ConnectionRemove};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum PresenceTransition {
    BecameOnline { peer_id: String },
    StayedOnline { peer_id: String },
    BecameOffline { peer_id: String, since_ts: i64 },
    StayedOnlineAfterDisconnect { peer_id: String },
}

#[derive(Debug, Default)]
pub(crate) struct PresenceState;

impl PresenceState {
    pub(crate) fn on_connection_inserted(insert: &ConnectionInsert) -> PresenceTransition {
        if insert.was_offline_before {
            PresenceTransition::BecameOnline {
                peer_id: insert.peer_id.clone(),
            }
        } else {
            PresenceTransition::StayedOnline {
                peer_id: insert.peer_id.clone(),
            }
        }
    }

    pub(crate) fn on_connection_removed(
        remove: &ConnectionRemove,
        now_ms: i64,
    ) -> Option<PresenceTransition> {
        if !remove.removed_connection {
            return None;
        }

        if remove.peer_offlined {
            Some(PresenceTransition::BecameOffline {
                peer_id: remove.peer_id.clone(),
                since_ts: now_ms,
            })
        } else {
            Some(PresenceTransition::StayedOnlineAfterDisconnect {
                peer_id: remove.peer_id.clone(),
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn insert(peer_id: &str, was_offline_before: bool) -> ConnectionInsert {
        ConnectionInsert {
            peer_id: peer_id.to_string(),
            conn_id: 1,
            was_offline_before,
            is_first_in_room: true,
        }
    }

    fn remove(peer_id: &str, removed_connection: bool, peer_offlined: bool) -> ConnectionRemove {
        ConnectionRemove {
            peer_id: peer_id.to_string(),
            removed_connection,
            room_emptied: peer_offlined,
            peer_offlined,
        }
    }

    #[test]
    fn inserted_offline_peer_becomes_online() {
        assert_eq!(
            PresenceState::on_connection_inserted(&insert("peer", true)),
            PresenceTransition::BecameOnline {
                peer_id: "peer".to_string()
            }
        );
    }

    #[test]
    fn inserted_already_online_peer_stays_online() {
        assert_eq!(
            PresenceState::on_connection_inserted(&insert("peer", false)),
            PresenceTransition::StayedOnline {
                peer_id: "peer".to_string()
            }
        );
    }

    #[test]
    fn removed_non_last_connection_stays_online_after_disconnect() {
        assert_eq!(
            PresenceState::on_connection_removed(&remove("peer", true, false), 42),
            Some(PresenceTransition::StayedOnlineAfterDisconnect {
                peer_id: "peer".to_string()
            })
        );
    }

    #[test]
    fn removed_last_connection_becomes_offline() {
        assert_eq!(
            PresenceState::on_connection_removed(&remove("peer", true, true), 42),
            Some(PresenceTransition::BecameOffline {
                peer_id: "peer".to_string(),
                since_ts: 42,
            })
        );
    }

    #[test]
    fn stale_remove_has_no_presence_transition() {
        assert_eq!(
            PresenceState::on_connection_removed(&remove("peer", false, false), 42),
            None
        );
    }
}
