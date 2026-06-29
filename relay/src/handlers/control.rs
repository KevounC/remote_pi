use thiserror::Error;

use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ControlFrameError {
    #[error("control frame {frame_type} requested {requested} peers, limit is {limit}")]
    TooManyPeers {
        frame_type: String,
        requested: usize,
        limit: usize,
    },
    #[error("control frame {frame_type} peers field must be an array")]
    PeersNotArray { frame_type: String },
    #[error("control frame {frame_type} peers[{index}] must be a string")]
    PeerNotString { frame_type: String, index: usize },
}

/// Validates the peer-list shape shared by presence/rooms control frames.
///
/// This is the fail-closed boundary that generated control-frame decoding will
/// call once the connection actor lands. Until then, `peer.rs` uses it to stop
/// malformed `peers` values from mutating subscriptions as an empty list.
pub fn bounded_peer_list(
    frame_type: &str,
    peers: Option<&serde_json::Value>,
) -> Result<Vec<String>, ControlFrameError> {
    let Some(peers_value) = peers else {
        return Ok(Vec::new());
    };
    let Some(peer_array) = peers_value.as_array() else {
        return Err(ControlFrameError::PeersNotArray {
            frame_type: frame_type.to_owned(),
        });
    };
    if peer_array.len() > MAX_CONTROL_FRAME_PEERS {
        return Err(ControlFrameError::TooManyPeers {
            frame_type: frame_type.to_owned(),
            requested: peer_array.len(),
            limit: MAX_CONTROL_FRAME_PEERS,
        });
    }

    let mut out = Vec::with_capacity(peer_array.len());
    for (index, value) in peer_array.iter().enumerate() {
        let Some(peer) = value.as_str() else {
            return Err(ControlFrameError::PeerNotString {
                frame_type: frame_type.to_owned(),
                index,
            });
        };
        out.push(peer.to_owned());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{ControlFrameError, bounded_peer_list};
    use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;

    #[test]
    fn missing_peers_defaults_to_empty_list() {
        assert_eq!(
            bounded_peer_list("subscribe_presence", None),
            Ok(Vec::new())
        );
    }

    #[test]
    fn rejects_non_array_peer_list() {
        assert_eq!(
            bounded_peer_list("subscribe_presence", Some(&json!("peer-a"))),
            Err(ControlFrameError::PeersNotArray {
                frame_type: "subscribe_presence".to_owned()
            }),
        );
    }

    #[test]
    fn rejects_mixed_type_peer_list() {
        assert_eq!(
            bounded_peer_list("subscribe_presence", Some(&json!(["peer-a", 1]))),
            Err(ControlFrameError::PeerNotString {
                frame_type: "subscribe_presence".to_owned(),
                index: 1
            }),
        );
    }

    #[test]
    fn enforces_peer_limit() {
        let peers = (0..=MAX_CONTROL_FRAME_PEERS)
            .map(|idx| format!("peer-{idx}"))
            .collect::<Vec<_>>();
        assert!(matches!(
            bounded_peer_list("presence_check", Some(&json!(peers))),
            Err(ControlFrameError::TooManyPeers { requested, .. }) if requested == MAX_CONTROL_FRAME_PEERS + 1
        ));
    }
}
