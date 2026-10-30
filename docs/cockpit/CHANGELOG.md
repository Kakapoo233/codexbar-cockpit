# Cockpit changes

## 0.3.1 — Complete existing language support

- Translate planning, calendar feedback, reset history and previews, task receipts, and import/error
  messages across all 23 existing app languages, without adding language choices.
- Format planning percentages, calendar numbers, and receipt dates using the selected app language.
- Keep retained error and preview messages in the current language and apply right-to-left layout
  to exported Arabic and Persian receipts.

## 0.3.0 — Reset history and early previews

- Sync public Codex Resets history into the calendar with distinct regular and banked reset markers,
  announcement-time grouping, original source links, and offline caches.
- Surface scheduled announcements and expiring website AI forecasts as soon as available. When no
  source preview exists, show an explicitly labeled local median-interval estimate.
- Send deduplicated early notifications with a calendar destination and a persistent Notifications
  setting. Public records never alter personal quotas, daily budgets, or subjective state.
- Keep synchronization active while the menu is closed and usable when local usage tracking is off.

## 0.2.2 — Responsive wide menu layout

- Use the expanded panel's width for a native usage column and a separate daily-advice sidebar.
- Keep provider cards, account controls, and their original actions together in the main column.
- Fit original card widths to the available column, including the submenu indicator.
- Fall back to one scrolling column on smaller screens and compact navigation when needed.

## 0.2.1 — Receipt save window ownership

- Attach the PNG save dialog to its receipt preview instead of blocking every application window.
- Prevent duplicate save dialogs and clean up an unfinished save when the preview disappears.

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
