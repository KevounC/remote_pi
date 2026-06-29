---
id: idea-mobile-message-duplication-send-timeout
created: 2026-06-29
updated: 2026-06-29
tags: [app, pi-extension, bug]
---

# Mobile: message duplication + send_timeout confirmation bug

Operator-observed sequence on the mobile app:

1. Sent a message.
2. The same message appeared **duplicated** in the mobile chat (two copies of the
   outgoing message rendered).
3. The second copy then hit a send-confirmation failure with the error:
   `send_timeout: Message was not confirmed by the Pi. It may not have been
   delivered.`
4. After the timeout, the duplicate message then appeared (again).

So the UI both duplicates the outgoing bubble *and* surfaces a `send_timeout`
delivery failure for the duplicate, then re-renders it — confusing and likely
wrong. Worth investigating:

- Is the duplication purely a UI/render issue (the outgoing message is added to
  the transcript twice — e.g. optimistic insert + echo from the extension/relay),
  or is the message actually being sent twice over the wire?
- The `send_timeout` ("not confirmed by the Pi") suggests the send-confirmation /
  ack path from the pi extension is not acking one of the copies, which then
  times out. Is the extension confirming by message id, and is the mobile client
  reusing or duplicating that id?
- Final re-appearance after the timeout suggests the failure path is re-inserting
  the message into the transcript rather than just marking the existing bubble as
  failed.

Likely touches both `app/` (optimistic insert / echo dedupe / failure rendering)
and `pi-extension/` (send confirmation / ack semantics). Needs reproduction and a
look at the message-id and ack flow before deciding the fix lives on one side or
both.
