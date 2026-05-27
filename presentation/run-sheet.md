# CTP Job Cards — Speaker Run Sheet

**Total runtime: ~25 minutes including questions**
**Format**: HTML deck in browser (left tab) + live web app (right tab). Press `Ctrl+Tab` to switch.
**Navigation**: `→` next slide · `←` previous · `F` fullscreen · `Esc` exit fullscreen · `1`–`9` jump to slide

---

## Opening — before slide 1

Walk into the room. Greet everyone. Wait for quiet.

> "Good morning. Today I'm walking you through the CTP Job Cards app — what's expected of you, what the app does for you, and most importantly, why the way you fill in job cards is about to become the most important thing in this workshop. About 20 minutes, then we'll take questions."

Press `F` to fullscreen. Press `→` to advance.

---

## Slide 1 — Cover quote (30 sec)

Read it out loud, slowly. Let it sit.

> "Every job card you fill in today becomes the brain of tomorrow's preventive maintenance."

Pause. Then: *"That's the whole reason we're here. Let me show you how it works."*

---

## Slide 2 — The four roles (90 sec)

Walk through each card. Punch the operator/technician distinction:

> "Operator and Technician are separate roles. The operator is the person who **finds** the fault. The technician is the person who **fixes** it. We're going to make sure both of you know exactly what the app does for you."

---

## Slide 3 — Getting the app, 5 steps (2 min)

Walk through each step on the slide, in order. This is the **one-time onboarding**.

> "Step 1: I'll send you a link. Click it, enter your email — that adds you to Firebase App Distribution. That's the channel we use to ship the app to your phone.
>
> Step 2: Firebase emails you a download link for the app. Open the email on your phone.
>
> Step 3: tap the link, download, install. Grant the six permissions when prompted — we'll cover those next.
>
> Step 4: first time you open the app, you register. Enter your email and **create a password**. That step links your account to your clock number in the employee collection — it tells the system who you are.
>
> Step 5: sign in with **your email and the password you just created**. From now on, that's all it takes."

Address the password question proactively:

> "Forgot your password down the line? Just hit Forgot Password on the sign-in screen. Reset email comes through. We don't need to involve anyone."

> "If you don't get the invitation email or the download email, check spam first — then see me or the admin to confirm your email was entered correctly."

---

## Slide 4 — Six permissions (3 min) — ▶ LIVE DEMO ON PHONE

**PICK UP THE PHONE.** (Mirror to TV if possible.)

Walk through each of the six prompts on a fresh install — or open the Permissions Onboarding screen if a fresh install isn't possible.

For each one, point to the slide as you grant it.

End with the line:

> "Five of these six exist specifically to make sure a P5 — production standing — actually reaches you."

**PUT PHONE DOWN. BACK TO SLIDES.**

---

## Slide 5 — How a notification reaches you (3 min)

The most technical slide. Slow down.

Point at the diagram as you talk:

> "A fair question came up while we were preparing this: doesn't the phone's operating system handle notifications? Why does our app need to be 'awake'?"

Walk through Path A:

> "For normal banners — P1 to P4 — you're right. The OS shows the banner itself. The app doesn't need to be running."

Walk through Path B:

> "But for a P5 — the full-screen alarm — we deliberately send a 'data-only' message. There's no built-in banner. The app itself has to wake up and fire the alarm, override Do Not Disturb, play the loud sound."

Land the punchline:

> "If Android has put our app to sleep to save battery, the alarm silently fails. That's why battery optimisation has to be off."

---

## Slide 6 — Geofence (2 min)

Read both columns. The "what it's NOT" column is the important one — read it word for word:

> "Not used to track movements off site. Not used to log where you eat lunch. Not used to check on you."

Then explain the two real reasons it exists. Make the safety angle clear:

> "A P5 cannot be assigned to anyone off site. The server refuses. That protects you from being held responsible for a job you physically can't reach."

---

## Slide 7 — Anatomy of a job card (2 min) — ▶ LIVE DEMO

**SWITCH TO LIVE WEB APP.** Open **Create Job Card**.

Click through every field on the create side: department → area → machine → part → description → priority → type.

> "Operator side: Dept, Area, Machine, Part, Description, Priority, Type. If you skip a field or pick the wrong machine, that data is lost to us forever. Pick wrong = the wrong machine 'fails' in the data = we service the wrong machine."

Then open an existing job card to show the technician side:

> "Technician side: Notes you add along the way, photos you take of the part or damage, and the **Complete — corrective action** field at closure. That last one is mandatory. The app won't let you close without it."

> "We'll come back to Complete on Slide 14 — that's the field that feeds the preventive maintenance system."

**SWITCH BACK TO SLIDES.**

---

## Slide 8 — Priority levels (90 sec)

Read each priority. Emphasise P5:

> "P5 is for production has stopped. Not slow. Not annoying. **Stopped.**"

> "Crying wolf with P5 numbs the team to the real ones."

---

## Slide 9 — Lifecycle (3 min) — ▶ LIVE DEMO

**SWITCH TO LIVE WEB APP.**

- Create a test job card (use the test machine you pre-seeded).
- Show how the status flips to **Open**.
- Have a second device or tab logged in as a technician → tap **Assign Self** → show the status auto-flip to **In-Progress**.
- Walk to the Job Card Detail → add a note → mark as **Closed** with a proper corrective action note.
- Mention that the operator just got a "Job Completed" notification.

While doing this, point out the three notification responses:

> "Three options on every notification. Assign Self, I'm Busy, or Dismiss. Two of them stop escalation. One — Dismiss — keeps escalation running, and your name goes on the log."

Important clarification on **I'm Busy**:

> "I'm Busy is only available **after hours** — night shifts, Saturdays, and Sundays. During normal weekday shifts, the only valid options are Assign Self or Dismiss. The reasoning: during normal hours you're at work, you're on the floor, you're expected to take the job. After hours, you might be sleeping, off-shift, or unavailable — that's when Busy makes sense."

**SWITCH BACK TO SLIDES.**

---

## Slide 10 — Three notification levels (90 sec) — ▶ LIVE P5

**PICK UP THE PHONE.**

From the admin screen on the web app, fire a real P5 test alert to the phone.

When the alarm goes off in the room, let it play for 5 seconds. Don't rush to silence it.

> "That's a P5. That alarm will go off on every phone of every on-site technician of the matching trade. Even on the lock screen. Even in Do Not Disturb. That's why those permissions matter."

Tap to dismiss the alarm. **PUT PHONE DOWN. BACK TO SLIDES.**

---

## Slide 11 — Escalation (2 min)

Walk through the table. **Name the actual people** at each stage — this is what makes it real:

> "Stage 1 — that's [foreman name], [foreman name]. Stage 2 — that's [dept manager], [workshop manager]. Stages 3 and 4 are off by default, but admin can turn them on."

Punchline:

> "Escalation stops the moment any technician taps Assign Self or I'm Busy. The way out is simple — just respond."

---

## Slide 12a — Notifications for operators & technicians (90 sec)

Walk through the table column by column. Pause on the maintenance row:

> "Maintenance jobs are silent. Planned work, not breakdowns. They never alarm, never escalate. Important when the AI later proposes preventive maintenance jobs — they'll appear in the system without waking anyone up."

---

## Slide 12b — Notifications for managers & admin (90 sec)

Walk through the table. Reinforce:

> "Off-site = no jobs. P5 cannot be sent to anyone off-site. The Cloud Function refuses."

---

## Slide 13 — Accountability (3 min) — ▶ LIVE FIRESTORE BACKEND

This is a sensitive slide. The intent is to **demystify** the audit log and reassure them that there's a formal procedure around any review of their data. **Tone matters here — open, not defensive.**

### Step 1 — Read the bullets

Walk through the four checks on the slide. Keep it factual.

> "Every tap, every accept, every busy, every dismiss, every status change, every close — recorded with your clock number and a timestamp to the second. Nobody on the workshop floor — including managers — can delete this."

### Step 2 — Read the green protection card slowly

Point at the green card. This is the key reassurance:

> "Here's the important part. Any review of tracking data from your device follows a **formal, documented procedure**. You will be **notified in advance** before any inspection of your activity. Audit data is not accessed casually, and it's not accessed without process."

> "This isn't a 'managers watch everything you do all day' system. This is a 'when there's a dispute, we have a clean record' system. There's a difference, and the procedure protects you."

### Step 3 — Show the actual Firestore backend ▶ LIVE

**SWITCH TO LIVE WEB APP / FIREBASE CONSOLE.**

Open the Firebase Firestore console in a browser tab. Walk through **four real collections** in this order:

1. **`notifications`** — open a few entries. Point at the fields: `sentTo`, `triggeredBy` (created / self_assigned / closed / dismissed / escalation), `level`, `priority`, `initiatedByClockNo`, `initiatedByName`, the timestamp. Say:
   > "This is the dispatch log. Every notification the system has ever sent, who it went to, what triggered it, and at what level. If someone tapped Dismiss, you'll see it here as a separate entry."

2. **`job_cards`** — open one card (the test card you seeded). Scroll down to the **`assignmentHistory`** array. Each entry has `clockNo`, `action` (selfAssigned / busy / handoff), and timestamp. Say:
   > "The job card carries its own history. Every accept, every handoff, every busy response — recorded in this array, on this document, forever."

3. **`geo_fence_logs`** — show a few entries. Point at `eventType` (enter / exit), `source` (geofence / workmanager_30min / app_open_check), `clockNo`, timestamp. Say:
   > "Every time the system detects you crossing the boundary — in or out — one entry. That's the entire location footprint. Not where you went. Just: in or out."

4. **`employees`** — open your own record. Show the fields: `clockNo`, `position`, `department`, `email`, `isOnSite`, `fcmToken`. Say:
   > "This is the **entire** employee record. Clock number, position, department, email, whether you're on site, and the token your phone uses to receive notifications. That's it. There is no hidden tracking field, no movement log."

Optional — if time allows, open **`settings/geofence`** and show the single lat/lng/radius:
   > "This one document is the only location anchor the system has. It's where the boundary is. The system does not store where you go — only whether you crossed this circle."

> "Everything the system knows about you is in these collections. Nothing more. If something isn't on this screen, it isn't being recorded."

### Step 4 — Close the loop

**SWITCH BACK TO SLIDES.**

> "If there's ever a dispute, we come here. The log is the final word. And the procedure makes sure you're part of that conversation, not the subject of it."

---

## Slide 14 — Closure notes (3 min) — **THE BUY-IN PITCH**

This is the most important slide. Slow down.

Read the hero quote:

> "Operators describe symptoms. Technicians record cause and cure. That's the difference."

Walk through the bad/good comparison. Point at the good side:

> "60 seconds of writing this — gives the next technician hours of head-start when this happens again."

> "And it will happen again. Until we put a PM in place. Which we cannot do without these notes."

---

## Slide 15 — Three payoffs (2 min)

Walk through the three cards. The deal at the bottom is the slide:

> "60 extra seconds at closure. In return — fewer 2am callouts, fewer repeat breakdowns, the next tech gets your solution handed to them on their screen. That's the deal."

---

## Slide 16 — Dark mode (45 sec) — ▶ FLIP IT LIVE

**SWITCH TO LIVE WEB APP. Open Settings.** Flip dark mode toggle. Theme changes.

> "Default dark for the workshop and nights. Toggle to light if you're outside in sunlight. Remembered per device."

**SWITCH BACK TO SLIDES.**

A small moment of levity before the close. Don't dwell.

---

## Slide 17 — Behind the scenes (90 sec)

Read the stats out loud. Don't read the bullets — paraphrase them as casual trivia.

> "The escalation engine that watches your job cards literally lives in Belgium. The database is in Johannesburg. Your notification bounces between two continents — under 2 seconds — to reach your pocket."

Audience usually laughs at the "shout at someone" line. Let them.

---

## Slide 18 — Three asks (90 sec) — THE CLOSE

Read each ask. Point at each one.

End with the callout, slowly:

> "Garbage in, garbage out. Truth in — and the workshop starts to feel different."

> "Any questions?"

---

## Q&A — common questions to expect

| Question | Answer |
|----------|--------|
| "What if I don't have a smartphone?" | We will issue a company phone. See admin. |
| "Will you track me at home?" | No. The geofence only ever checks: inside boundary or outside boundary. We have no record of where you go off site. |
| "What if I make a mistake on a job card?" | The technician or manager can edit it — the edit is logged in the audit. Don't worry, just be honest. |
| "What if I'm on leave and a P5 fires?" | If you're off-site (which you are on leave), you won't get it. The server blocks P5 to off-site phones. |
| "Will the AI replace technicians?" | No. The AI suggests; the technician decides. It's a head-start, not a replacement. |
| "How do I get my Gmail linked?" | Send your Gmail address to the admin. Takes 30 seconds to add. |
| "What happens if my phone is offline?" | The app queues everything. As soon as you have signal or Wi-Fi, it syncs. You don't do anything. |
| "Can I see my own audit history?" | Yes — your assigned jobs list shows your history. Managers can see everyone's. |

---

## After Q&A

> "Anyone who hasn't got the app installed and signed in by end of shift today — see me or [admin name]. Tomorrow we go live."

End. Switch off projector.
