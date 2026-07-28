# CTP Job Cards — Floor Onboarding (Speaker Run Sheet)

**Purpose of this deck:** Floor operators — transparency on what we collect, how modules work, buy-in on **permissions**, and key job-card functions.  
**Not:** Board status pack (that is the monorepo Director Status Briefing PDFs).

**Format:** HTML deck · tick departments on slide 1 · `→` / `←` · `F` fullscreen · `Home` / **Change selection** returns to picker  
**Runtime:** ~15–35 min depending on departments ticked (Factory overview longest)

---

## Opening

1. Leave the deck on the **department picker**.
2. Tick every department **in the room** (e.g. Pre Press + Pressroom).
3. Tick **Managers in the room** if foremen/managers need escalation & Pulse callouts (otherwise foreman callouts show on operator slides).
4. **Start presentation** — or **Factory overview** for every slide.

Opening line:

> "This is how the factory phone app works — Job Cards. We'll be clear about what data we collect and why, especially permissions. Then the factory map, and whatever applies to your departments today."

**Foremen** = operators (same Job Cards path). **Technicians** share that path so both sides hear the full create→fix lifecycle when Pressroom / Pre Press / Post Press is ticked.

---

## How slides are chosen

| You tick | Extra deep dive (on top of shared spine) |
|----------|------------------------------------------|
| **Pressroom, Pre Press, or Post Press** | Full Job Cards lifecycle (ops + tech) |
| **Pre Press** | Also **Lurgi & Copper** slide (Copper = managers) |
| **Lurgi** | Lurgi & Copper slide (Lurgi section) |
| **Ink Factory** | Ink floor capture |
| **Waste** | Waste floor capture |
| **Site Security** | Gate module |
| **Fleet** | 3-tap report, urgency, daily check |
| **Factory overview** | Every slide |

**Shared spine (always):** Who uses the app → Get app → Six permissions → Notification path → Geofence → All floor modules map → Accountability → Behind the scenes → Three asks.

**Job Cards block order:** Anatomy → Priorities → Lifecycle → Notify levels → Escalation → Ops/Tech matrix → Closure notes → Note payoffs → Dark mode.

---

## Example combinations

| Room | Typical ticks | ~slides (excl. picker) |
|------|---------------|-------------------------|
| Pressroom only | Pressroom | Spine + JC (~17) |
| Pre Press + Pressroom | Both | Spine + JC + Copper/Lurgi slide (~18) |
| Security guards | Site Security | Spine + Security (~9) |
| Ink floor | Ink Factory | Spine + Ink (~9) |
| Mixed maintenance tour | Pressroom + Post Press | Spine + JC |
| Full factory | Factory overview | All (~25) |

---

## Speaker notes — corrected facts

| Topic | Say this |
|-------|----------|
| Busy | Stops escalation; does **not** keep chasing someone else. P5 full-screen Busy is after-hours; shade Busy still on P3–P5. |
| Dismiss | Escalation continues; logged. **No** push to the operator. |
| Auto-close Monitor | Status/notes only — **no** notify both sides. |
| Silent types | Maintenance (+ building / specialist / postPress by default). |
| Note payoffs | Live = similar jobs + reoccurrence on Pulse. Chatbot / auto-PM push = **roadmap**, not live. |
| Lurgi | **Live** for Lurgi dept. |
| Copper | **Admin or Pre Press manager** only — included when Pre Press is ticked. |
| Escalation | 5 / 10 / 30 / 60 min; stages 1–2 ON; every **5 minutes, 24/7**. |
| Geofence | ~400 m **default** (site setting can change). |
| Foremen | Same operator tiles; extra quality oversight; may be Stage 1 on-site for their dept. |

Always keep **permissions** and **geofence transparency** — never soft-skip those.

---

## Behind the scenes — numbers to say out loud

| Fact | Value (through 2026-07-27) |
|------|----------------------------|
| **Lines we wrote** (first-party authored) | **~228,000** — product + tests + map/docs |
| **Runs in production** | **~179,000** — see breakdown below |
| Engaged development time | **~985 hours** |
| FTE-months | **~6.2** |
| In work hours | **~298 h** (07:30–16:00 weekdays) |
| Outside work hours | **~687 h** (evenings + weekends) |
| Active days | **110** (2026-04-07 → 2026-07-27) |

Say out loud: *“About **228 thousand lines** of our own work went into this — and about **179 thousand** of that is what runs on your phones, Pulse, and the cloud every day.”*

Source: Time Review + monorepo `tools/count-shipped-loc.ps1` (hours not double-counted).

### ~179k — runs in production

| Component | ~lines |
|-----------|-------:|
| Mobile app (`lib/` Dart) | 97,830 |
| Job Cards Cloud Functions (JS) | 3,338 |
| CTP Pulse (`src`, excl. tests) | 66,503 |
| wastetrack-overtime CF (`src`) | 5,342 |
| `shared-ts` contracts | 227 |
| Firestore + Storage rules | 1,775 |
| APK landing page | 1,127 |
| Android native (`main/`) | 2,420 |
| **Total** | **~179,000** |

### ~228k — authored beyond runtime (included in headline)

| Component | ~lines |
|-----------|-------:|
| Mobile unit tests | 7,877 |
| Firebase rules tests | 5,106 |
| Pulse tests in `src` | ~4,400 |
| Mobile presentation + `docs/` | 8,791 |
| Components + monorepo `docs/` | 20,205 |
| Canvases map | 4,123 |
| `tools/` | 889 |
| **Extra (approx.)** | **~49,000** |

Recount: `pwsh tools/count-shipped-loc.ps1` from monorepo root.

---

## Close

> "Grant the permissions — they exist so a P5 and your real work reach the right people. Use the tiles you have. Write notes like the next person needs them. That's how this system works for the floor, not only for management."
