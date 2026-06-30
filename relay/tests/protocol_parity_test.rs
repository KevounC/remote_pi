use std::collections::BTreeSet;

use relay::protocol::generated::cross_pc::{CROSS_PC_TYPES, CrossPcFrame};
use relay::protocol::generated::mesh::{
    MeshEnvelopeWire, MeshGetQuery, MeshGetResponse, MeshPostResponse,
};
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

fn jsonl_values(input: &str) -> Vec<Value> {
    input
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str::<Value>(line).expect("fixture line must be valid JSON"))
        .collect()
}

fn round_trip<T>(value: &Value) -> Value
where
    T: DeserializeOwned + Serialize,
{
    let decoded: T = serde_json::from_value(value.clone()).expect("fixture must decode");
    serde_json::to_value(decoded).expect("generated DTO must serialize")
}

#[test]
fn cross_pc_fixture_round_trips_through_generated_types() {
    let values = jsonl_values(include_str!(
        "../../protocol/fixtures/cross-pc/cross-pc.jsonl"
    ));
    let mut seen_types = BTreeSet::new();

    for value in values {
        let frame: CrossPcFrame = serde_json::from_value(value.clone())
            .expect("cross-PC fixture must deserialize through generated frame enum");
        let round_tripped = serde_json::to_value(&frame)
            .expect("generated cross-PC frame must serialize back to JSON");
        assert_eq!(
            round_tripped, value,
            "cross-PC fixture changed on round trip"
        );

        match frame {
            CrossPcFrame::PiEnvelope(frame) => {
                seen_types.insert("pi_envelope");
                assert!(
                    frame.envelope.body.is_object(),
                    "AgentEnvelope.body must remain opaque JSON, not a typed relay DTO"
                );
            }
            CrossPcFrame::PiEnvelopeIn(frame) => {
                seen_types.insert("pi_envelope_in");
                assert!(
                    frame.envelope.body.is_object(),
                    "PiEnvelopeIn envelope body must remain opaque JSON"
                );
            }
        }
    }

    let generated_types = CROSS_PC_TYPES.iter().copied().collect::<BTreeSet<_>>();
    assert_eq!(
        seen_types, generated_types,
        "cross-PC fixtures and generated variant registry must stay in parity"
    );
}

#[test]
fn relay_mesh_http_fixture_round_trips_through_generated_types() {
    let values = jsonl_values(include_str!(
        "../../protocol/fixtures/relay/mesh-http.jsonl"
    ));
    assert_eq!(
        values.len(),
        4,
        "mesh fixture documents all generated HTTP DTOs"
    );

    assert_eq!(round_trip::<MeshEnvelopeWire>(&values[0]), values[0]);
    assert_eq!(round_trip::<MeshPostResponse>(&values[1]), values[1]);
    assert_eq!(round_trip::<MeshGetResponse>(&values[2]), values[2]);
    assert_eq!(round_trip::<MeshGetQuery>(&values[3]), values[3]);
}
