---
id: relay-mutex-poison-recovery
created: 2026-06-28
updated: 2026-06-28
tags: [relay, security]
---

# Decide relay mutex poison recovery policy

Adversarial review flagged `Mutex::lock().unwrap()` / `expect` in relay shared state. Decide whether crash-on-poison is acceptable under supervisor assumptions or whether relay should recover from poisoned locks to avoid one panic becoming a full outage.
