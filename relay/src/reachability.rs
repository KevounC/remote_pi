use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReachabilityState {
    Connecting,
    Online,
    Degraded,
    Offline,
    Retrying,
}

impl ReachabilityState {
    pub const fn as_wire(self) -> &'static str {
        match self {
            Self::Connecting => "connecting",
            Self::Online => "online",
            Self::Degraded => "degraded",
            Self::Offline => "offline",
            Self::Retrying => "retrying",
        }
    }
}

pub const REACHABILITY_STATES: [ReachabilityState; 5] = [
    ReachabilityState::Connecting,
    ReachabilityState::Online,
    ReachabilityState::Degraded,
    ReachabilityState::Offline,
    ReachabilityState::Retrying,
];

pub const REACHABILITY_BACKOFF: [Duration; 5] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(5),
    Duration::from_secs(10),
    Duration::from_secs(30),
];

pub fn reachability_backoff(attempt: usize) -> Duration {
    REACHABILITY_BACKOFF[attempt.min(REACHABILITY_BACKOFF.len() - 1)]
}

pub const RELAY_WS_PING_INTERVAL: Duration = Duration::from_secs(25);
pub const APP_PROTOCOL_PING_INTERVAL: Duration = Duration::from_secs(25);
pub const EXTENSION_LIVENESS_CHECK_INTERVAL: Duration = Duration::from_secs(20);
pub const EXTENSION_LIVENESS_TIMEOUT: Duration = Duration::from_secs(70);
pub const DEGRADED_AFTER_MISSED_APP_PONGS: u8 = 3;

#[cfg(test)]
mod tests {
    use super::*;

    fn contract() -> serde_json::Value {
        serde_json::from_str(include_str!("../../protocol/schema/reachability.json"))
            .expect("reachability contract JSON must parse")
    }

    #[test]
    fn states_match_contract() {
        let contract = contract();
        let expected = contract["states"]
            .as_array()
            .expect("contract states must be an array")
            .iter()
            .map(|value| value.as_str().expect("state must be a string"))
            .collect::<Vec<_>>();
        let projected = REACHABILITY_STATES
            .iter()
            .map(|state| state.as_wire())
            .collect::<Vec<_>>();

        assert_eq!(projected, expected);
    }

    #[test]
    fn backoff_matches_contract_and_clamps() {
        let contract = contract();
        let expected = contract["backoffSeconds"]
            .as_array()
            .expect("contract backoff must be an array")
            .iter()
            .map(|value| Duration::from_secs(value.as_u64().expect("backoff must be u64")))
            .collect::<Vec<_>>();

        assert_eq!(REACHABILITY_BACKOFF.as_slice(), expected.as_slice());
        assert_eq!(reachability_backoff(0), Duration::from_secs(1));
        assert_eq!(reachability_backoff(4), Duration::from_secs(30));
        assert_eq!(reachability_backoff(99), Duration::from_secs(30));
    }

    #[test]
    fn heartbeat_policy_matches_contract() {
        let contract = contract();
        let heartbeat = contract["heartbeat"]
            .as_object()
            .expect("contract heartbeat must be an object");

        assert_eq!(
            RELAY_WS_PING_INTERVAL,
            Duration::from_secs(heartbeat["relayWsPingSeconds"].as_u64().unwrap())
        );
        assert_eq!(
            APP_PROTOCOL_PING_INTERVAL,
            Duration::from_secs(heartbeat["appProtocolPingSeconds"].as_u64().unwrap())
        );
        assert_eq!(
            EXTENSION_LIVENESS_CHECK_INTERVAL,
            Duration::from_secs(heartbeat["extensionLivenessCheckSeconds"].as_u64().unwrap())
        );
        assert_eq!(
            EXTENSION_LIVENESS_TIMEOUT,
            Duration::from_secs(
                heartbeat["extensionLivenessTimeoutSeconds"]
                    .as_u64()
                    .unwrap()
            )
        );
        assert_eq!(
            DEGRADED_AFTER_MISSED_APP_PONGS,
            heartbeat["degradedAfterMissedAppPongs"].as_u64().unwrap() as u8
        );
    }
}
