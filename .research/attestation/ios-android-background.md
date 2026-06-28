---
source_handle: ios-android-background
fetched: 2026-06-28
source_url: https://developer.android.com/training/monitoring-device-state/doze-standby and https://developer.apple.com/library/archive/technotes/tn2277/_index.html
provenance: source-direct
---

# iOS/Android background behavior attestation

1. Android Doze/App Standby docs state Doze reduces battery use by deferring background CPU and network activity when the device is unused, and App Standby defers background network activity for apps with no recent user activity.
2. Android power/resource-limit docs state jobs, alarms, and network access can be limited based on the app standby bucket.
3. Apple TN2277 says iOS multitasking allows apps to enter the background and then be suspended, which can affect network applications.
4. Apple WWDC25 background-task search result says by default backgrounded apps are suspended and do not get CPU time.
5. Apple developer forum search result for networking states WebSocket tasks are not supported in background sessions, and the key distinction is running vs suspended: once suspended, networking stops.
