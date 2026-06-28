---
source_handle: android-background-restrictions
fetched: 2026-06-28
source_url: https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions
provenance: source-direct
substrate_confidence: source-direct
---

# Android system restrictions on background tasks

Paraphrased summary: Android documents system restrictions around background processes because they can be memory- and battery-intensive. Restricted apps may be prevented from running jobs, alarms, or network access except while in the foreground. Android recommends using the right background-work API, including WorkManager for scheduled background tasks, and monitoring network connectivity while the app is running rather than relying on manifest connectivity broadcasts.

## Key passages

- Background processes can be memory- and battery-intensive and can affect device performance and user experience.
- User-initiated restrictions may restrict an app's system-resource access when it exhibits bad behaviors such as excessive wake locks or background services.
- On AOSP builds, restricted apps cannot run jobs, trigger alarms, or use the network except when foreground.
- The docs recommend WorkManager to schedule background tasks when trying to avoid these limitations.
- Manifest-registered `CONNECTIVITY_ACTION` receivers do not receive broadcasts; running apps can monitor network conditions with registered callbacks.

## Structural metadata

- Source type: Android Developers documentation
- Relevant domain: mobile background network assumptions.
