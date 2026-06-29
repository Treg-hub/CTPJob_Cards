# Site Security — Manager Mobile Guide

*For Security Managers — mobile capture plus CTP Pulse desk*

Security managers use **both** surfaces:

- **This app (mobile)** — same scan flows as guards, plus **add company car cost**
- **CTP Pulse** (`/security/*`) — gate log history, on-site overview, reports, deny list (requires `security` boardModules claim)

Guards never use Pulse; you do.

---

## Mobile — what you can do here

### Home and tabs

Unlike guards, you keep the **standard job-card Home** (quick actions, My Work tab) **plus** Waste and Security tabs when those modules are enabled.

### Site Security tab

Same flows as guards:

- Vehicle scan in / out (**SEC-NNNN**)
- On-foot visitor
- Company car exit / return
- On-site list

**Add company car cost** — available to you (`isSecurityCostManager`): pick a registered company car, category, receipt.

### Waste Recovery tab

You can browse **on-site stock**, see **Copper ready to sell**, schedule loads, and begin collections. Pending weighbridge and cost review are completed on **CTP Pulse** — see the Waste Pulse guide there.

---

## CTP Pulse desk (primary for oversight)

Use Pulse for:

| Task | Pulse hub |
|------|-----------|
| Gate log + entry detail | Operations |
| Who is on site (desk view) | Operations → On site |
| Company car register + trips | Vehicles |
| Company car spend | Costing |
| CSV / XLSX exports | Reports |
| Deny list | Setup (admin) |
| Gates, vehicles, settings | Central Settings → Site Security |

---

## Quick checklist

1. **Morning** — Pulse Operations → On site + gate log filter.
2. **During shift** — mobile scans at the gate; optional company car costs on mobile or Pulse Costing.
3. **End of day** — Pulse Reports export if needed for audit.