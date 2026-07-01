---
id: gate-refactor-boundaries-ambiguous-map-rpc-gateway-respondui
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# RPC UI responses are exposed as raw maps in a domain port

## Library
boundaries

## Rule
ambiguous-map-to-domain

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/domain/contracts/rpc_process_gateway.dart:62

## Issue
RpcProcessGateway.respondUi requires callers to pass a raw {value|confirmed|cancelled} Map<String, dynamic>, leaking wire shape into the domain/UI boundary.

## Fix
Needs analysis: replace the map with a typed RpcUiResponse sealed/value type and serialize it only in PiRpcProcess.
