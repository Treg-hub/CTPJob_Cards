# Ops checklist — Post Press Specialist

Code ships the role helper, `Post Press Spec` job type (`postPressSpecialist`), and CF auto-assign. Complete these live data steps:

1. **Employee position** — set `employees/{clockNo}.position` to `Post Press Specialist` (title is authoritative; department may be `Post Press` or another).
2. **My Timesheet (optional)** — add their clock to `work_report_settings/config.enabled_clock_nos` in Pulse Settings → Work Report.
3. **notification_configs/global** — after CF deploy, defaults deep-merge `postPressSpecialist` creation recipients + exclusion. Optionally re-save Escalation config from Admin so the stored doc includes the new keys.
4. **Smoke** — with the specialist on-site, create a Post Press / Post Press Spec job → auto-assign; confirm Pre Press Spec still routes to Pre Press.
