---
id: app-owner-key-version-rollback-hardening
created: 2026-06-28
updated: 2026-06-28
tags: [app, security]
---

# Harden app owner-key mesh version rollback handling

Low-confidence adversarial finding: resetting mesh version watermark to zero after owner-key changes may allow older valid signed blobs to be reaccepted in restore/confusion scenarios. Investigate whether a highest-ever-version per owner key is needed.
