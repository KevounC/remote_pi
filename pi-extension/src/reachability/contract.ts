export const REACHABILITY_STATES = [
  "connecting",
  "online",
  "degraded",
  "offline",
  "retrying",
] as const;

export type ReachabilityState = (typeof REACHABILITY_STATES)[number];

export const REACHABILITY_DISPLAY_NAMES: Record<ReachabilityState, string> = {
  connecting: "Connecting",
  online: "Online",
  degraded: "Degraded",
  offline: "Offline",
  retrying: "Retrying",
};

export const REACHABILITY_BACKOFF_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;

export function reachabilityBackoffMs(attempt: number): number {
  const safeAttempt = Number.isFinite(attempt) ? Math.max(0, Math.trunc(attempt)) : 0;
  return REACHABILITY_BACKOFF_MS[
    Math.min(safeAttempt, REACHABILITY_BACKOFF_MS.length - 1)
  ];
}

export const REACHABILITY_HEARTBEAT = {
  appProtocolPingMs: 25_000,
  relayWsPingMs: 25_000,
  extensionLivenessCheckMs: 20_000,
  extensionLivenessTimeoutMs: 70_000,
  degradedAfterMissedAppPongs: 3,
} as const;

export const REACHABILITY_TRANSITIONS = [
  ["offline", "connect_requested", "connecting"],
  ["connecting", "connect_succeeded", "online"],
  ["connecting", "connect_failed_retryable", "retrying"],
  ["connecting", "connect_cancelled", "offline"],
  ["online", "app_protocol_silence", "degraded"],
  ["online", "transport_closed", "retrying"],
  ["online", "stop_requested", "offline"],
  ["degraded", "fresh_app_frame_or_room_snapshot", "online"],
  ["degraded", "transport_closed", "retrying"],
  ["degraded", "stop_requested", "offline"],
  ["retrying", "retry_timer_fired", "connecting"],
  ["retrying", "stop_requested", "offline"],
  ["retrying", "retry_disabled", "offline"],
] as const satisfies readonly (readonly [ReachabilityState, string, ReachabilityState])[];

export type ReachabilityTransition = (typeof REACHABILITY_TRANSITIONS)[number];
export type ReachabilityEvent = ReachabilityTransition[1];
