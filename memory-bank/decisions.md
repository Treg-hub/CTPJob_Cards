# Active Decisions and Considerations

Open architectural/design decisions guiding ongoing work.

- **Employee Display Format**: Using `displayName` (name + clockNo + position) + department for clean, non-redundant UI
- **Filtering Logic**: Department filter overrides mech/elec filter for precise assignment control
- **Real-time Updates**: StreamBuilder for live employee list updates in assign dialog
- **Super-Manager Pattern**: Users with `department == 'general'` treated as super-managers with full oversight - no dept filters by default, access to all filters like dept managers, view all jobs on login
- **Off-site write locks deferred (2026-06-28)**: Server-side `isOnSite` write enforcement for floor roles is intentionally deferred until permission health (`DeviceHealthService`, `employees.permissions` merge, admin On Site indicators) is validated in production. Targeted admin broadcast supports permission-fix outreach in the interim.
