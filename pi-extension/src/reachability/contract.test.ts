import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import {
  REACHABILITY_BACKOFF_MS,
  REACHABILITY_DISPLAY_NAMES,
  REACHABILITY_HEARTBEAT,
  REACHABILITY_STATES,
  REACHABILITY_TRANSITIONS,
  reachabilityBackoffMs,
} from "./contract.js";

interface ReachabilityContractJson {
  name: string;
  version: number;
  states: string[];
  displayNames: Record<string, string>;
  backoffSeconds: number[];
  heartbeat: {
    appProtocolPingSeconds: number;
    relayWsPingSeconds: number;
    extensionLivenessCheckSeconds: number;
    extensionLivenessTimeoutSeconds: number;
    degradedAfterMissedAppPongs: number;
  };
  transitions: { from: string; event: string; to: string }[];
}

const contractPath = fileURLToPath(
  new URL("../../../protocol/schema/reachability.json", import.meta.url),
);

function readContract(): ReachabilityContractJson {
  return JSON.parse(readFileSync(contractPath, "utf8")) as ReachabilityContractJson;
}

describe("Reachability TS projection", () => {
  test("states and display names match the interim JSON contract", () => {
    const contract = readContract();
    expect(contract.name).toBe("Reachability");
    expect(contract.version).toBe(1);
    expect(REACHABILITY_STATES).toEqual(contract.states);
    expect(REACHABILITY_DISPLAY_NAMES).toEqual(contract.displayNames);
    expect(Object.keys(REACHABILITY_DISPLAY_NAMES)).toEqual([...REACHABILITY_STATES]);
  });

  test("backoff policy matches the JSON contract and clamps attempts", () => {
    const contract = readContract();
    expect(REACHABILITY_BACKOFF_MS).toEqual(
      contract.backoffSeconds.map((seconds) => seconds * 1_000),
    );
    expect([-2, -1, 0, Number.NaN, Number.POSITIVE_INFINITY].map(reachabilityBackoffMs)).toEqual([
      1_000,
      1_000,
      1_000,
      1_000,
      1_000,
    ]);
    expect([1, 2.9, 3, 4, 5, 99].map(reachabilityBackoffMs)).toEqual([
      2_000,
      5_000,
      10_000,
      30_000,
      30_000,
      30_000,
    ]);
  });

  test("heartbeat policy matches the JSON contract", () => {
    const { heartbeat } = readContract();
    expect(REACHABILITY_HEARTBEAT).toEqual({
      appProtocolPingMs: heartbeat.appProtocolPingSeconds * 1_000,
      relayWsPingMs: heartbeat.relayWsPingSeconds * 1_000,
      extensionLivenessCheckMs: heartbeat.extensionLivenessCheckSeconds * 1_000,
      extensionLivenessTimeoutMs: heartbeat.extensionLivenessTimeoutSeconds * 1_000,
      degradedAfterMissedAppPongs: heartbeat.degradedAfterMissedAppPongs,
    });
  });

  test("transition table matches the JSON contract", () => {
    const contract = readContract();
    expect(REACHABILITY_TRANSITIONS.map(([from, event, to]) => ({ from, event, to }))).toEqual(
      contract.transitions,
    );
    expect(REACHABILITY_TRANSITIONS).toContainEqual([
      "online",
      "app_protocol_silence",
      "degraded",
    ]);
    expect(REACHABILITY_TRANSITIONS).toContainEqual([
      "degraded",
      "fresh_app_frame_or_room_snapshot",
      "online",
    ]);
  });
});
