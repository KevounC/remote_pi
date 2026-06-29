---
id: epic-bold-generated-protocol-dart-codegen-step-2
kind: story
stage: implementing
parent: epic-bold-generated-protocol-dart-codegen
depends_on: [epic-bold-generated-protocol-dart-codegen-step-1]
tags: [refactor]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Generate Dart client messages and shared value types beside the hand mirror

**Priority**: High  
**Risk**: Medium  
**Source Lens**: duplicated variants / generated contract  
**Files**: `app/lib/protocol/generated/protocol.g.dart`, `app/test/protocol_codegen/`, `app/lib/protocol/protocol.dart` (read-only reference)

## Current State

Client-side wire DTOs are handwritten in `app/lib/protocol/protocol.dart` as subclasses with manual `toJson` maps, while the same variants are declared in `pi-extension/src/protocol/types.ts`:

```dart
sealed class ClientMessage {
  Map<String, dynamic> toJson();
}

class UserMessage extends ClientMessage {
  final String id;
  final String text;
  final UserMessageStreamingBehavior? streamingBehavior;
  final List<WireImage>? images;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user_message',
    'id': id,
    'text': text,
    if (streamingBehavior != null)
      'streaming_behavior': streamingBehavior!.wireValue,
    if (images != null && images!.isNotEmpty)
      'images': images!.map((i) => i.toJson()).toList(),
  };
}
```

Mirrored shared types include `WireImage`, `ActionName`, `ThinkingLevel`, and `WireModel`.

## Target State

Generate the client half and shared value types beside the existing hand mirror, under a separate generated import used only by tests until the final swap:

```dart
// app/lib/protocol/generated/protocol.g.dart
sealed class ClientMessage {
  const ClientMessage();
  String get type;
  Map<String, dynamic> toJson();
}

final class UserMessage extends ClientMessage {
  const UserMessage({
    required this.id,
    required this.text,
    this.images,
    this.streamingBehavior,
  });

  @override
  String get type => 'user_message';
  final String id;
  final String text;
  final List<WireImage>? images;
  final UserMessageStreamingBehavior? streamingBehavior;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'text': text,
        if (images case final images? when images.isNotEmpty)
          'images': images.map((image) => image.toJson()).toList(),
        if (streamingBehavior case final behavior?)
          'streaming_behavior': behavior.wireValue,
      };
}
```

## Implementation Notes

- Generate exactly the current client wire shape: no new fields, no renamed fields, no changed omission rules.
- Preserve enum wire strings (`session_compact`, `xhigh`, `steer`) exactly.
- Generate equality/hashCode only for value types currently relying on equality (`WireImage`, `WireModel`) unless the schema-source feature standardizes broader equality.
- Keep generated classes in a separate library/import for this step so existing app code continues using the handwritten `protocol.dart` classes.
- Add tests that compare generated `toJson()` output to the existing handwritten `toJson()` output for every `ClientMessage` variant.

## Acceptance Criteria

- [ ] Generated client message classes exist for every current `ClientMessage` variant.
- [ ] Generated `toJson()` output matches the handwritten output for representative payloads, including optional image and streaming fields.
- [ ] Shared generated enums/value types preserve the current public names and wire strings.
- [ ] No production app imports are switched to generated code yet.

## Rollback

Remove the generated client output and tests. The handwritten protocol remains the runtime source.
