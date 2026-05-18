# Active Decisions and Considerations

Open architectural/design decisions guiding ongoing work.

- **Employee Display Format**: Using `displayName` (name + clockNo + position) + department for clean, non-redundant UI
- **Filtering Logic**: Department filter overrides mech/elec filter for precise assignment control
- **Real-time Updates**: StreamBuilder for live employee list updates in assign dialog
- **Super-Manager Pattern**: Users with `department == 'general'` treated as super-managers with full oversight - no dept filters by default, access to all filters like dept managers, view all jobs on login
