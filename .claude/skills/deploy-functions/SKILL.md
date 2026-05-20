---
name: deploy-functions
description: Deploy Cloud Functions with pre-flight safety checks — verifies scheduled functions are in europe-west1, then deploys and tails logs.
disable-model-invocation: true
---

```sh
cd "C:/Users/Admin/CTPJob_Cards/functions" && echo "=== Checking scheduled function regions ===" && grep -n "schedule\|runWith\|region" index.js | head -30 && echo "" && echo "Scheduled functions (escalateNotifications, autoCloseMonitoringJobs) must have region: 'europe-west1'" && echo "" && read -p "Regions look correct? Deploy? (y/N) " confirm && [ "$confirm" = "y" ] && firebase deploy --only functions && echo "" && echo "=== Recent logs ===" && firebase functions:log --limit 20
```
