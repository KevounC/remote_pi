---
source_handle: web-socket-channel-io
fetched: 2026-06-28
source_url: https://pub.dev/documentation/web_socket_channel/latest/io/IOWebSocketChannel/IOWebSocketChannel.connect.html
provenance: source-direct
substrate_confidence: source-direct
---

# `web_socket_channel` `IOWebSocketChannel.connect`

Paraphrased summary: `IOWebSocketChannel.connect` creates a Dart `dart:io` WebSocket-backed channel. The constructor accepts `pingInterval`, `connectTimeout`, headers, protocols, and custom client. The docs specify that unanswered pings close the socket with a going-away code, and connection errors surface on the channel stream as `WebSocketChannelException` before closing.

## Key passages

- `IOWebSocketChannel.connect(Object url, { protocols, headers, Duration? pingInterval, Duration? connectTimeout, HttpClient? customClient })` creates a new WebSocket connection.
- It connects using `WebSocket.connect`; `url` can be a `String` or `Uri`.
- `pingInterval` controls sending ping signals; if a ping is not answered by a pong, the WebSocket is assumed disconnected and closed with a `goingAway` code.
- The pong must be received within `pingInterval`; `null` disables ping messages.
- `connectTimeout` limits how long to wait for `WebSocket.connect`; if null, connection setup never times out.
- If there is a connection error, the channel stream emits a `WebSocketChannelException` and closes.

## Structural metadata

- Source type: pub.dev API documentation
- Package observed in repo: `web_socket_channel: ^3.0.1` in `app/pubspec.yaml`.
