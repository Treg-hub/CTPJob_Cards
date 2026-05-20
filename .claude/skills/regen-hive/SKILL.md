---
name: regen-hive
description: Regenerate Hive type adapters after modifying @HiveType models (e.g. SyncQueueItem). Runs build_runner then analyzes for generated-code errors.
disable-model-invocation: true
---

```sh
cd "C:/Users/Admin/CTPJob_Cards" && flutter pub run build_runner build --delete-conflicting-outputs && flutter analyze lib/models --no-fatal-infos 2>&1 | tail -15
```
