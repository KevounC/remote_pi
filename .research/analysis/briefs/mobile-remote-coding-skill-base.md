---
slug: mobile-remote-coding-skill-base
created: 2026-06-28
provenance: synthesis
---

# Mobile remote-coding skill-base brief

## Registration summary

- Commissioning items: `story-api-reference-flutter-mobile-stack` and `feature-mobile-remote-coding-best-practices-skill`.
- Scope authority: mixed.
- Verification rigor: standard for the high-impact mobile skill-base slices.
- Decision relevance: determine the initial reusable skill/checklist substrate agents must load before Remote Pi app/mobile-session refactors.

## Synthesis

Remote Pi should treat mobile remote coding as a snapshot-first state-machine problem, not as a permanently connected terminal. Flutter exposes lifecycle listeners, but its lifecycle docs warn that apps should not rely on receiving every possible notification; abrupt termination can skip states. [flutter-app-lifecycle]{1} Android can restrict background execution and network use for restricted apps except while foreground. [android-background-restrictions]{1} Apple's iOS networking note says suspended apps run no process code, cannot handle incoming network data, and may have socket resources reclaimed. [apple-networking-multitasking]{1}

The app already has an appropriate foundation: `ConnectionManager` separates connection states, canonical room snapshots, live room IDs, and active-room working correction. [remote-pi-app-transport-state]{1} The new skill base preserves that posture by making authoritative snapshots, idempotent actions, reconnect hydration, and explicit connected/working/stale/error UI states first-class review checks.

## Outputs

- `.agents/skills/flutter-mobile/SKILL.md`
- `.agents/skills/mobile-remote-coding/SKILL.md`
- Attestations added under `.research/attestation/` for Flutter lifecycle/context docs, Provider, WebSocket channel, go_router, Android/iOS background networking, and Remote Pi local app sources.

## Contradictions

No direct contradictions were found among fetched sources. The main tension is operational: WebSocket APIs support ping/reconnect mechanics, but mobile OS lifecycle documentation warns that background/suspended operation cannot be treated as continuous execution. The resolved design rule is to use pings/reconnect while foreground and rely on snapshot hydration after lifecycle or network discontinuity.

## Disconfirming analysis

Searched for evidence that lifecycle callbacks or WebSocket ping support could justify treating mobile sockets as continuously reliable. The fetched Flutter, Android, and Apple sources all point the other way: lifecycle notifications can be skipped, background restrictions can remove network access, and suspended iOS apps cannot process network data. [flutter-app-lifecycle]{1} [android-background-restrictions]{1} [apple-networking-multitasking]{1}

## Verification

- Citation handles in this brief correspond to `.research/attestation/*.md` files added during the engagement.
- Spot-check focus: load-bearing lifecycle and state-machine claims are tied to fetched source attestations; project-specific claims are tied to local source attestations.
