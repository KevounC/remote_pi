// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: cross_pc.

#![allow(dead_code)]

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentEnvelope {
    pub from: String,
    pub to: Value,
    pub id: String,
    pub re: Option<String>,
    pub body: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PiEnvelopeFrame {
    pub to_pc: String,
    pub envelope: AgentEnvelope,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PiEnvelopeInFrame {
    pub from_pc: String,
    pub envelope: AgentEnvelope,
}

pub const CROSS_PC_TYPES: &[&str] = &["pi_envelope", "pi_envelope_in"];
