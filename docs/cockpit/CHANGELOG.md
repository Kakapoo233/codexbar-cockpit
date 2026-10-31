# Cockpit changes

## 0.7.0 — Live reset-aware daily advice

- Recalculate automatic daily advice from the latest account balance and remaining planning time.
- Use earlier valid announced or estimated reset windows, label their source, and discard expired predictions.
  Predictions never reset the observed quota; manual daily caps remain user-controlled.

## 0.6.3 — Receipts in session history

- Replace the standalone receipt page with a Usage Receipt button in the selected historical session's details.
  Keep the existing PNG preview, copy and save actions.
- Capture only that session's displayed reporting period, currency conversion and partial-data status.
  Respect privacy settings and label the session scope on the exported receipt.

## 0.6.2 — Taller session history

- Increase the Usage & Spend session browser from 600 to 760 points in both the Sessions tab and direct navigation.
- Give the compact history list up to 320 points instead of 190, while retaining at least 55% of the available
  height for session details. Keep the outer page and both inner panes scrollable on smaller windows.

## 0.6.1 — Self-service Cloudflare configuration

- Put self-hosted setup and invitation joining in a guided Settings form with Worker URL, device name,
  space name and the relevant creation secret or invitation. Add examples, hover help and deployment links.
- Add an anonymous service-address check; detect invalid endpoints and unsupported services without sending
  keys, invitations or usage. Clarify that service reachability does not validate the database or membership.
- Clear obsolete check results and unsubmitted secrets when the endpoint or setup flow changes.
- Report the packaged app version in team sync metadata.

## 0.6.0 — Members, devices, and shared plans

- Add a native Members & Devices peer page and canonical connection settings, plus the current member budget on Usage.
- Restore v2 Cloudflare spaces, single-use invitations, member/device assignment, revocation and shared daily plans.
  Budget revisions and reset-cycle checks prevent stale drafts from overwriting another device’s edits.
- Keep team credentials in a separate local Keychain item. Aggregate sharing is opt-in, scoped to explicitly confirmed
  native Codex history from the next complete Shanghai day; identity changes revoke that confirmation.
- Preserve offline data, show partial usage, pause owner connections without losing their only credential, and recover
  received enrollment credentials after local save failures. No provider credentials, tasks or feelings are uploaded.
- Vendor the MIT upstream Worker with migrations, tests and deployment instructions. Real deployment and two-device
  acceptance require a chosen team service; the app does not include a public hosted endpoint.
- Provide English and both Chinese translations for the new team controls; other locales use explicit English fallback.

## 0.5.1 — Feeling icons in the calendar

- Replace weather symbols with feeling faces: relaxed, comfortable, and overwhelmed.
  Keep the same face in selected status buttons and month cells, with a separate selection checkmark.
- Include the recorded feeling in month-cell hover and accessibility descriptions.

## 0.5.0 — Restore the Cockpit comfort curve

- Restore v0.3.4's fixed quota-comfort curve, fitting only its knee from subjective feedback.
  Show the default 25% knee without data, fitted scatter points, hover details, and cumulative
  daily quota use beyond 100%. Recent feedback has more weight; partial observations have less.
- Switch between account-specific quota feedback and the existing local Token experience in the
  calendar. Select a day to record, correct, or clear its feeling. Existing Token records remain intact.
- Save quota samples independently by provider, account, calendar date, and time zone. Missing usage
  stays unknown; changing a feeling preserves its measurement and never changes the daily plan or cap.
- Add the curve, model explanation, and sample-state messages to all 23 existing languages.

## 0.4.2 — Updated Codex Pro plan labels

- Display Pro 100 / Pro Lite as 10x, Pro 200 as 20x, and explicit Pro 500 names as 50x.
  Share the current mapping across menus, CLI output, dashboard scraping, and share cards.
- Preserve server-reported usage percentages and unknown plan names. Do not double the existing
  Pro 200 20x label: the October 29 update brings its lower allowance up to the higher allowance.
- References: [OpenAI Pro tier update](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers)
  and [Tibo's Pro 500 confirmation](https://x.com/thsottiaux/status/2115851811576053881).

## 0.4.1 — Statistics time-zone settings placement

- Keep the statistics time-zone picker and current-Mac-zone action in Settings → Usage & Spend.
  Remove these controls from the menu-bar Statistics page while preserving the saved setting
  and shared calendar/ledger behavior.

## 0.4.0 — Editor help and local Cockpit insights

- Explain menu-bar layout items, presets, display options, and conditional rules on hover in all
  23 existing languages. Disabled line-break items remain hoverable without accepting input.
- Browse the calendar by day, week, month, quarter, or year and switch between Token and cost
  views. Keep personal-state editing and reset markers; separate currencies and disclose missing history.
- Add a local weekday calibration reference with a separate validation period and explicit
  readiness/fallback states. Frozen daily suggestions and manual caps remain authoritative.
- Weight recorded Token-experience trends toward recent days, without treating subjective
  feedback as an official quota estimate.

## 0.3.2 — English text in the top menu bar

- Add an optional English-only text setting under Menu Bar. It affects the screen's top status items
  and their layout preview; the expanded panel and settings keep the selected app language.
- Persist the choice and include it in portable preference exports. Default remains off.
- Separate layout caches by language so toggling restores the correct text and accessibility labels.

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
