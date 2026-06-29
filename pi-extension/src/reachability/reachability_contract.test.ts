import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import {
  REACHABILITY_BACKOFF_MS,
  REACHABILITY_RELAY_LIVENESS_CHECK_MS,
  REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  REACHABILITY_RELAY_PING_INTERVAL_MS,
  reachabilityBackoffMs,
} from "./reachability_contract.js";

interface ReachabilityContractJson {
  backoffSeconds: number[];
  heartbeat: {
    relayWsPingSeconds: number;
    extensionLivenessCheckSeconds: number;
    extensionLivenessTimeoutSeconds: number;
  };
}

const contractPath = fileURLToPath(
  new URL("../../../protocol/schema/reachability.json", import.meta.url),
);

function readContract(): ReachabilityContractJson {
  return JSON.parse(readFileSync(contractPath, "utf8")) as ReachabilityContractJson;
}

describe("pi-extension reachability policy projection", () => {
  test("backoff policy matches the JSON contract and clamps attempts", () => {
    const contract = readContract();

    expect(REACHABILITY_BACKOFF_MS).toEqual(
      contract.backoffSeconds.map((seconds) => seconds * 1_000),
    );
    expect([-1, 0, 1, 2, 3, 4, 5, 99].map(reachabilityBackoffMs)).toEqual([
      1_000,
      1_000,
      2_000,
      5_000,
      10_000,
      30_000,
      30_000,
      30_000,
    ]);
  });

  test("relay liveness windows match the JSON contract", () => {
    const { heartbeat } = readContract();

    expect(REACHABILITY_RELAY_PING_INTERVAL_MS).toBe(heartbeat.relayWsPingSeconds * 1_000);
    expect(REACHABILITY_RELAY_LIVENESS_CHECK_MS).toBe(
      heartbeat.extensionLivenessCheckSeconds * 1_000,
    );
    expect(REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS).toBe(
      heartbeat.extensionLivenessTimeoutSeconds * 1_000,
    );
  });
});
