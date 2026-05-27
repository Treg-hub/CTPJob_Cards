# Pre-Flight Checklist — Boardroom Setup

**Do all of this 15 minutes before the meeting starts.** Nothing on this list is optional. If something fails on stage you lose the room.

---

## 1. Hardware (5 min)

- [ ] **TV powered on**, set to the correct HDMI input.
- [ ] **Laptop connected** via HDMI or wireless display. Confirm the laptop screen mirrors / extends to the TV.
- [ ] **Display resolution** set so the browser is full-screen, no taskbar visible. (Windows: `Win+P` → Extend or Duplicate, whichever shows the deck best.)
- [ ] **Audio**: if the TV has speakers, confirm laptop audio is routed there. Test with a YouTube clip — you want sound for the P5 alarm demo.
- [ ] **Demo phone** charged, signed in as a technician with all permissions granted. Sound and vibration ON. Phone unmuted.
- [ ] **Phone mirroring** to TV — optional but powerful for the permissions and P5 demo. Use scrcpy (Android) or Quick Share / built-in cast. **Test it works before the meeting.**
- [ ] **Pointer or remote** — even if it's just having the laptop within reach so you can tap arrow keys.

## 2. Browser setup (3 min)

- [ ] Open **Chrome** (not Edge, not Firefox — Chrome is the most stable for live demos).
- [ ] Sign out of any personal Google accounts that aren't relevant.
- [ ] **Tab 1**: Open `presentation/presentation.html` from the project folder. Hit `F` to fullscreen. Hit `Home` to go to slide 1.
- [ ] **Tab 2**: Open the live web app. Sign in as an **admin** account so you have full visibility (audit log, escalation config, test alerts).
- [ ] **Tab 3** (optional): A second instance of the web app signed in as a **technician** — useful for the lifecycle demo (Slide 9) so you can show "Assign Self" happen from a separate user.
- [ ] **Tab 4**: The **Firebase Firestore console** — sign in, open the project, pre-navigate to the **`notifications`** collection. This is the first collection you'll show on Slide 13. Have **`job_cards`**, **`geo_fence_logs`**, and **`employees`** bookmarked or one click away.
- [ ] Confirm `Ctrl+Tab` cycles between tabs cleanly. Practice it twice.
- [ ] Close every other tab. Close other apps. **Slack, Outlook, Teams — kill them.** No notifications during the talk.

## 3. Seed the test data (3 min)

- [ ] In the live web app (admin tab), **create one test job card** on a fake test machine. Department: "Test", Area: "Test", Machine: "DEMO_MACHINE_1", Part: "DEMO_PART".
- [ ] Add a description like: "Pre-demo seed for accountability slide".
- [ ] Set priority to **P2** (low enough not to alarm anyone, high enough to show in lists).
- [ ] Open the audit log to confirm the entry shows up. This is what you'll show on Slide 13.

## 4. P5 alarm dry-run (2 min)

- [ ] On the demo phone, confirm the app is in the foreground or recently used.
- [ ] From the admin tab in the web app, send a **test P5 notification** to that phone.
- [ ] Confirm: full-screen alarm fires, loud sound, vibration. Dismiss it.
- [ ] If the alarm DID NOT fire as full-screen — check the phone's permissions again (Display Over Other Apps, Schedule Exact Alarms, Do Not Disturb access, Battery Optimisation off). Fix and retest. **Do not skip this.**

## 5. Connectivity (1 min)

- [ ] Confirm laptop has internet. Open `https://www.google.com` to verify.
- [ ] If the boardroom Wi-Fi is patchy, **tether the laptop to your phone**. The whole demo collapses without internet — the live app talks to Firebase on every click.
- [ ] If tethering, confirm signal in the boardroom is at least 3 bars.

## 6. Last 60 seconds before walk-in

- [ ] Press `Home` to make sure the deck is on slide 1.
- [ ] Press `F` to make sure it's fullscreen.
- [ ] Phone in pocket, screen on, app open.
- [ ] One sip of water.
- [ ] Walk in.

---

## During the talk — what to watch for

- **Press `→` (or click) to advance.** Don't click on links/buttons — that won't trigger advance.
- **If the deck goes weird**: press `Home` to go to slide 1, press `F` to refresh fullscreen.
- **If a live demo fails**: don't fight it. Move on, say "the audit log shows this entry — I'll show you afterwards." Demo failures look bad; demo struggles look worse.
- **If a question comes mid-slide**: answer it, then say "let me continue and we'll cover more questions at the end."

---

## After the talk

- [ ] Delete the test job card seeded earlier (or move it to a "demo" department).
- [ ] Make a note of any questions you couldn't fully answer — those are tomorrow's first follow-ups.
- [ ] Send a one-liner to managers: "Briefing done. [N] employees attended. Next: every employee signed in by [date]."

---

## Emergency fallbacks

| If this fails... | Do this... |
|------------------|------------|
| Wi-Fi dies mid-talk | Tether to phone, reload tabs. ~30 seconds. |
| TV won't show laptop | Use the laptop screen directly. Everyone gathers closer. |
| P5 alarm refuses to fire | Skip the live alarm demo. Describe verbally and show the persistent banner one instead. |
| Web app errors / crashes | Close the tab, reopen, sign in again. Have credentials at hand. |
| The HTML deck won't load | Open `presentation/presentation.html` directly in Chrome from File → Open. |
