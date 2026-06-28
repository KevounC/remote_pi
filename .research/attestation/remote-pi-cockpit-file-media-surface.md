---
source_handle: remote-pi-cockpit-file-media-surface
fetched: 2026-06-28
source_path: cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart
provenance: source-direct
---

# Remote Pi cockpit file/media surface attestation

## Source summary

Cockpit's file viewer handles markdown, text/code, SVG, images, and audio/video. Text and markdown are editable with save/discard/format flows, LSP diagnostics, and mounted guards around async UI operations. Media rendering is delegated to `MediaView`.

## Key passages

> `FileViewer` comments describe a file viewer body for markdown/text/image/A/V and say text and markdown are editable; a toolbar toggles preview/source, save is `Cmd+S`, and media/image/unsupported files stay read-only.

> `_FileViewerState` owns edit state, dirty/saving flags, code editing controller, focus node, LSP diagnostics subscription, and an LSP debounce timer.

> `_startLsp` captures `CockpitViewModel` with `context.read`, opens a document, listens for diagnostics, checks `mounted` before `setState`, and updates controller diagnostics.

> `didUpdateWidget` handles path changes by disposing/recreating controllers, closing old LSP documents, cancelling diagnostic subscriptions, and restarting LSP for new editable text.

> `dispose` cancels the LSP debounce and diagnostic subscription, closes the LSP document with `unawaited`, and disposes the editor controller/focus resources.

> `FileViewer` imports `SelectionArea` from Material for markdown selection/auto-scroll while the rest of the UI uses `shadcn_flutter`.

## Notes for Remote Pi

File/media changes are UI plus native/file-system/LSP boundary work. Preserve mounted guards, cancellation, draft ownership, and separation between ViewModel operations and widget rendering.
