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

## Reproduction (operator-confirmed)

The duplicate appears when sending and then leaving the chat screen mid-send:

1. Send a message from a session's chat screen.
2. While it is still sending, press **back** to return to the session list.
3. Re-enter the **same** session.
4. The sent message now appears **duplicated** in the chat.
5. Press **back** again and re-enter the session again — the duplicate clears.

So the duplication is tied to **navigating away from the chat screen and back
while a send is in flight**. The likely cause is that re-entering the session
re-runs the optimistic insert / transcript hydration and re-adds the in-flight
message that was already optimistically inserted before navigation, producing
two copies of the same outgoing bubble. A second back→re-enter cycle then
re-hydrates from a consistent source and the duplicate collapses.

The `send_timeout` earlier may be a related but separate in-flight-send state
that gets orphaned by the back-navigation (the send confirmation never resolves
because the screen/listener that owns the in-flight request was torn down).

## Likely fix surface

Likely touches both `app/` (optimistic insert / echo dedupe / failure rendering
/ in-flight send lifecycle tied to screen navigation) and `pi-extension/`
(send confirmation / ack semantics). Needs reproduction and a look at the
message-id and ack flow before deciding the fix lives on one side or both.
