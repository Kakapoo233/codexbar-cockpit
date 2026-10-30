# Cockpit changes

## 0.2.0 — Unified menu-bar panel

- Replace the intermediate Cockpit window with Usage, Statistics, Calendar, and Receipts in one menu-bar panel.
- Show daily usage advice and editable personal caps directly above the provider details.
- Merge subjective feedback and the Token experience chart into Calendar.
- Keep Calendar and Receipt filters separate from the Statistics selection.
- Move explicit CodexBar settings import into General preferences.
- Preserve provider action context on first open, refresh routing, and expandable card heights.
- Keep calendar state controls visible at the top and localize month/weekday labels.


## 0.1.1

- Add personal-state controls to the selected calendar date, with a visible selected state and a clear action.
- Allow historical corrections and today's feedback while disabling future dates.
- Keep records separate by provider, local calendar date, and time zone. Editing a feeling preserves an existing Token measurement and never changes official quota.
- Add regression coverage for calendar selection, persistence, clearing, and measurement preservation.
- Add an explicitly opt-in local-data acceptance test for native calendar and receipt rendering. Private inputs and generated images stay outside the repository.

## 0.1.0

Initial native integration based on CodexBar v0.82.0 and Codex Cockpit v0.3.4: independent menu-bar app identity, local planning, usage statistics, calendar, comfort records, and PNG task receipts.
