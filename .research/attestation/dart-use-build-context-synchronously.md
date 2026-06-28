---
source_handle: dart-use-build-context-synchronously
fetched: 2026-06-28
source_url: https://dart.dev/tools/linter-rules/use_build_context_synchronously
provenance: source-direct
substrate_confidence: source-direct
---

# Dart lint `use_build_context_synchronously`

Paraphrased summary: The Dart lint documents the rule against using `BuildContext` across asynchronous gaps without a mounted check. It distinguishes checking `State.mounted` when using a `State` object's context from checking `BuildContext.mounted` when using another context variable.

## Key passages

- The lint says not to use `BuildContext` across asynchronous gaps.
- When using a `State` object's `context` property, check the `State` object's `mounted` property after the async gap.
- For other `BuildContext` instances such as local variables or function arguments, check the `BuildContext`'s own `mounted` property.
- A mounted check must dominate the later context use; merely checking in an unrelated branch is insufficient.

## Structural metadata

- Source type: Dart linter documentation
- Relevant rule: `use_build_context_synchronously`.
