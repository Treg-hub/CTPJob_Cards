# CTP Job Cards - Project Progress Tracker

**Repository:** Treg-hub/CTPJob_Cards
**Last Updated:** May 07, 2026 11:56 SAST
**Current Branch:** feature/escalation-fix-v2

## Executive Summary
This document tracks all major initiatives for the CTP Job Cards app.

## Current Notification Architecture (Final Version - May 07, 2026)

### 3-Stage Escalation Model

| Stage | Time | Who Gets Notified | Purpose |
|-------|------|-------------------|---------|
| Job Created | Immediate | Onsite Mechanics / Electricians | Base technicians who do the work |
| 2min Escalation | 2 minutes | Onsite Managers + Foremen + Creator | "No action taken yet" |
| 7min Escalation | 7 minutes | Onsite Dept Managers + Workshop Manager + Creator | "Urgent - senior management needed" |
| 30min Escalation | 30 minutes | **Empty for now** | Ready for future offsite managers |

**Key Rules:**
- Escalation **stops immediately** if someone is assigned
- Each stage escalates to **more senior people**
- Fully dynamic via `escalation_recipients` in Firestore
- All scheduled functions run in `europe-west1`

## Geofencing System (Updated May 07, 2026)

### Status: **FIXED**

**Changes Made:**
- Added native Android geofence implementation (Kotlin)
- Added `GeofenceBroadcastReceiver.kt`
- Added `MainActivity.kt` with full geofence support
- Updated `location_service.dart` with proper logging to `geofence_logs` collection
- Added automatic logging for: `enter`, `exit`, `registered`, `enter_forced`, `exit_forced`

**Company Location:**
- Latitude: -29.994938052011612
- Longitude: 30.939421740548614
- Radius: 800 meters

**Logging:** All geofence events are now written to `geofence_logs` collection in Firestore for full history tracking.

## Initiative Status

### 1. Dynamic Notification Configuration (Plan 1) - COMPLETED
**Branch:** feature/escalation-fix-v2
**Status:** Fully implemented and pushed

### 2. Geofencing Fix - COMPLETED
**Branch:** feature/escalation-fix-v2
**Status:** Native Android implementation + logging added

### 3-5. Other Initiatives
- Role-based manuals: Completed
- AI Preventative Maintenance: Planning phase
- AI Chatbot: Planning phase
- Firebase Cost Optimization: Ongoing best practices

## Next Actions
1. Pull branch `feature/escalation-fix-v2`
2. Rebuild APK
3. Test geofence by walking in/out of 800m radius
4. Check `geofence_logs` collection for entries
5. Decide who to notify at 30min stage

**End of Tracker**