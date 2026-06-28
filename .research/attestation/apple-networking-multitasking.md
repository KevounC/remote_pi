---
source_handle: apple-networking-multitasking
fetched: 2026-06-28
source_url: https://developer.apple.com/library/archive/technotes/tn2277/_index.html
provenance: source-direct
substrate_confidence: source-direct
---

# Apple Technical Note TN2277: Networking and Multitasking

Paraphrased summary: Apple's archived Networking and Multitasking technical note explains how iOS backgrounding and suspension affect network apps. When an app is suspended, its process does not execute, cannot handle incoming network data, and socket resources may be reclaimed. The note recommends closing and reopening cheap sockets across background/foreground transitions, handling socket errors on resume, doing background-transition work quickly, and using asynchronous networking with cancellable background tasks for work that must continue briefly.

## Key passages

- When iOS puts an app into the background, it may shortly thereafter suspend the app.
- When suspended, no code in the app process executes, making it impossible to handle incoming network data.
- While suspended, the system may reclaim resources from a network socket, closing the connection represented by that socket.
- If reopening a data socket is simple and cheap, the recommended approach is to close it when the app goes into the background and reopen it when it returns to foreground.
- If keeping a socket open in background, the app must correctly handle socket errors because reclaimed sockets become unusable.
- Transition work in `applicationDidEnterBackground` must be quick; waiting for network can trigger the watchdog.
- Asynchronous network APIs are recommended for supporting multitasking because cancellation must be quick and reliable.

## Structural metadata

- Source type: Apple Developer archive technical note
- Relevant domain: iOS mobile network lifecycle.
