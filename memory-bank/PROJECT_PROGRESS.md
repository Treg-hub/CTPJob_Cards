# CTP Job Cards - Project Progress Tracker

**Repository:** Treg-hub/CTPJob_Cards
**Last Updated:** May 06, 2026 20:52 SAST
**Current Commit:** f08493886c5cb7a6e4528e16795628c634b289df

## Executive Summary
This document tracks all major initiatives, decisions, and implementation status for the CTP Job Cards app. It serves as the single source of truth for project state. All plans are designed around the existing codebase (Flutter + Riverpod + Hive + Firebase + Cloud Functions in africa-south1).

## Key Architectural Decisions (Scaling Mindset)
- Keep everything configurable via Firestore where possible (no more hard-coded business rules in Cloud Functions).
- Maintain lean Firebase costs: client-side compression, efficient queries, configurable scheduler intervals.
- Use existing admin_screen.dart and notification infrastructure as the foundation for new features.
- All AI features will leverage Gemini/Vertex AI via Cloud Functions for minimal added cost.

## Initiative Status

### 1. Dynamic Notification Configuration (Plan 1)
**Status:** Ready to implement (high priority)
**Goal:** Allow editing escalation times (2min/7min → any value) and recipient rules without redeploying Cloud Functions.
**Key Files to Modify:**
- functions/index.js (add getNotificationConfig() + update escalateNotifications and recipient helpers)
- lib/screens/admin_screen.dart (add "Notification Rules" section)
- New Firestore doc: notification_configs/global
**Dependencies:** None
**Scaling Benefit:** Instant rule changes, no downtime, easy to add new escalation levels or recipient groups.
**Next Action:** Detailed code implementation (full updated functions + admin UI code)

### 2. Full Role-Based User Manuals
**Status:** Completed (delivered May 06, 2026)
**Details:** Separate manuals created for Operators/Technicians and Managers based on actual screens (HomeScreen, JobCardDetailScreen, ManagerDashboardScreen, MyAssignedJobsScreen, etc.) and features (offline sync, geofencing, priority 5 fullscreen alerts, copper workflows).
**Location:** Included in previous response.
**Next Action:** None (ready for use or minor tweaks)

### 3. AI Preventative Maintenance
**Status:** Planning phase
**Goal:** Analyze completed job cards → suggest recurring maintenance to Mechanical/Workshop/Electrical Managers.
**Approach:**
- Phase 1: Scheduled Cloud Function + Gemini prompt on closed job_cards data
- Phase 2: RAG / Vector Search for better pattern detection
**Key Data:** job_card.dart model (machine, part, notes, status, priority)
**Next Action:** Detailed implementation plan + sample function code when ready

### 4. AI Chatbot for Equipment Manuals
**Status:** Planning phase
**Goal:** In-app chatbot for technicians to query uploaded manuals ("How do I replace the belt on Pump X?")
**Approach:** Firebase Storage (manuals) + Gemini RAG via Cloud Function + new chat screen/widget
**Integration:** Context-aware from current Job Card (pre-fill machine/part)
**Next Action:** Detailed plan + cost estimate when needed

### 5. Firebase Cost Optimization at Scale
**Status:** Ongoing best practices
**Current Strengths (already in codebase):**
- Client-side image compression (flutter_image_compress)
- Hive offline queue (reduces reads/writes)
- africa-south1 region for Cloud Functions
- Existing firestore.indexes.json
**Recommendations Applied:** Configurable scheduler intervals (Plan 1), proper pagination, denormalization, lifecycle rules for old photos.
**Monitoring:** Use Firebase Console Usage dashboard + budget alerts
**Next Action:** Add simple usage/cost dashboard card in AdminScreen after Plan 1

## Completed Work (as of May 06, 2026)
- Full deep dive of every file, screen, service, model, and Cloud Function (via GitHub connector)
- Comprehensive manual covering all screens and notification system
- 5-point strategic plan delivered and accepted
- Project progress tracker created (this file)

## Open Items / Next Priorities
1. Implement Plan 1 (Dynamic Notifications) – Start immediately
2. Add usage/cost monitoring to AdminScreen
3. Begin Phase 1 of AI Preventative Maintenance
4. Create dedicated Notification Rules editing UI in admin_screen.dart

## Notes & Decisions
- All changes must preserve existing notification priority levels (1-5 → full-loud / medium-high / normal)
- TestNotificationScreen.dart remains the primary testing tool
- Future AI features should reuse the existing notification sending helpers (sendNotification, logNotification)
- Memory-bank/ will be used for all long-term project memory

## How to Update This File
Run the GitHub connector tool to append new sections or update statuses after each major milestone.

**End of Tracker**