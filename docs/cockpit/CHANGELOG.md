# Cockpit changes

## 0.8.33 — Member usage overview and centralized settings

- Move member, device assignment, invitation, access and budget controls to Settings.
- Make the member page a read-only distribution view with recorded usage, device coverage and explicit missing-data states.
- Apply the same separation in the Windows client while retaining its existing upload and budget limitations.

## 0.8.32 — Remaining duration beside quota headroom

- Append the estimated remaining duration after the 1.5× headroom hint for session and weekly allowances in the Usage card, using the same model's uncapped projected average rate and explicitly ignoring replenishment at reset.
- Keep the menu-bar exhaustion metric and daily recommendation comparison unchanged; invalid or unavailable rates never invent a duration.
- Expand the card's forecast text allowance so longer explanations can wrap, with localized wording across all 23 app languages.

## 0.8.31 — Quota feedback inside calendar dates

- Put personal quota-state selection and clearing inside each date cell for day, week and month views.
- Show provider and feedback type above the grid; preserve the existing quota observations when editing feelings.
- Reject future-day writes and stale menu actions after account changes.

## 0.8.30 — Remove local reset-date estimates

- Remove historical reset-date extrapolation, its calendar markers and notices, and its effect on daily planning.
- Keep historical records, account reset times, confirmed announcements and explicitly labeled website watches.
- Ignore legacy local planning-date hints on Windows; update calendar empty states and notification settings text.

## 0.8.29 — Plain numeric readouts

- Remove comparison-sign prefixes from allowance, pace, statistics, calendar and receipt values across Mac and Windows UI.
- Keep original numbers, rounding, signs/colors, missing/stale states and completeness flags; retain partial-data explanations in prose and hover/accessibility help.
- Update all 23 Mac language catalogs to explain incomplete data without referring to removed symbols; hook and tool-filter comparisons keep their original logic.

## 0.8.28 — Clear daily allowance units

- Replace Daily advice's Weekly remaining metric with Available today as a share of the weekly quota, and remove Observed today from that card.
- Keep the daily-allocation progress bar, show its weekly equivalent once in the separate row, and localize the new label in all 23 supported languages.

## 0.8.27 — Codex weekly warnings persist across restarts

- Keep a local, account-scoped weekly warning ledger so the same threshold cannot repeat after quota rebounds, provider cleanup or application updates.
- Treat an already-low first reading as a quiet baseline; retain lower-threshold alerts and reopen warnings only after a confirmed new weekly reset.
- Cover ordinary and selected-account refresh entry points, reject unproven owners, and record receipts before sound, overlays or OS notifications.

## 0.8.26 — Daily allowance in the advice card

- Move the progress row from beneath weekly quota into the right-side Daily advice card, replacing its duplicate remaining-value presentation.
- Fill it with available-today allowance divided by today's effective allocation; keep the weekly-quota equivalent as a secondary value.
- Reuse provider color, minute updates, manual-cap handling and partial/stale/missing states without changing the automatic recommendation or top menu-bar components.

## 0.8.25 — Stable low-quota warnings

- Keep the already-delivered threshold record when a quota reading temporarily disappears, preventing repeated 50% alerts during continuous use.
- Ignore older observations for the same warning episode, while retaining real recovery, lower-threshold and confirmed next-cycle notifications.
- Preserve independent provider, account and quota-window warning state.

## 0.8.24 — Recommendation beside weekly usage

- Replace the large top summary with a progress row directly below the main weekly quota, using the same bar style and color.
- Show the automatic full-day recommendation as a share of weekly quota, independently of the used/remaining switch and personal caps.
- Preserve account and allowance boundaries, uncertainty, native layout caching and live minute updates.

## 0.8.23 — Daily recommendation at the top of Usage

- Pin a prominent Daily recommendation summary above the Usage page's scrolling content, with provider names, large percentages and full-day weekly-quota units.
- Reuse the current account's automatic plan, preserving uncertainty and distinguishing it from personal caps and today's remaining allowance.
- Keep detailed planning controls in the existing advice card without repeating the recommendation value.

## 0.8.22 — Reset duration without filler

- Omit the leading English "in" after R in menu-bar countdowns, keeping the duration and full spoken description.

## 0.8.21 — Tighter status-item labels

- Reduce the gap between English prefixes and their numbers or meters, including daily T components.
- Simplify weekly reset labels from R W to R while retaining full window descriptions for accessibility.

## 0.8.20 — Compact menu-bar identifiers

- Identify weekly quota with W, session quota with S, resets with R, pace with P and exhaustion estimates with E; retain T for today's components.
- Resolve automatic and direct-lane quota labels from their actual period, including single-window and missing readings, while preserving named provider allowances and balance text.
- Apply labels consistently to numbers and meters, keep full spoken descriptions, and retain the existing label preference.

## 0.8.19 — Status-bar pace signs and colors

- Show native signed daily-pace numbers in the top menu bar, using red and green for the recorded difference from the daily recommendation.
- Dim incomplete observations and explain their uncertainty in hover and accessibility help; retain unknown exact conditional values.
- Refresh help and colors when observation coverage changes, and clear daily explanations when switching to layouts without pace.
- Keep the existing daily calculation, expanded panel and legacy bound text unchanged.

## 0.8.18 — Native pace presentation

- Restore CodexBar's concise deficit, reserve and on-pace labels while retaining the daily-recommendation comparison.
- Keep the original signed menu-bar numbers and independent quota forecast. Move detailed daily units and reference explanations to hover help.
- Preserve partial-data bounds and unknown readings; hiding pace also hides its explanation without removing provider-owned help.

## 0.8.17 — Select main pages on press

- Switch Usage, Statistics, Calendar and Members & Devices when their navigation button is pressed.
- Keep keyboard and accessibility activation, 44-point click targets and the compact icon-only layout.
- Releasing the mouse over the same page does not publish another navigation change.

## 0.8.16 — Open the menu panel on press

- Toggle the Mac menu-bar panel on left or right mouse-down, without waiting for mouse-up.

## 0.8.15 — Mac panel responsiveness

- Coalesce provider-menu updates while Usage is hidden; refresh once before returning to the current provider and settings.
- Apply the panel's column width before its first menu attaches, avoiding an extra native menu measurement and oversized cards.
- Cancel pending refreshes on close and reopen. Keep the existing provider collectors and retained page controls.

## 0.8.10

- Replace the unavailable personal CloudKit settings pane with iCloud Drive file synchronization for allowlisted preferences, menu-bar layouts, personal caps and calendar feedback.
- Preserve account boundaries and device-local measurements; never export provider credentials or raw history.
- Merge per-device revisions and explicit deletions, wait for undownloaded files and distinguish local exchange from Apple upload confirmation.

## 0.8.9 — Today’s available allowance in the menu bar

- Add percentage, continuous bar and bottom-up filled-circle components for today’s available allowance. All three use the effective daily allocation as 100%, respect manual caps and actual balance, and expose the weekly equivalent in accessibility text.
- Preserve upper bounds for incomplete observations and distinguish stale or unknown values. Reuse the shared planner, account checks, minute refresh, localization and English status-text preference.
- Store new components in Cockpit V8 while retaining older-readable layout projections. Existing layouts remain unchanged until edited.

## 0.8.8 — Restore original calendar text size

- Restore calendar typography to its size before the 50% enlargement, including date cells, selectors, details and chart labels. Return the associated cell, badge and chart dimensions to their original sizes.

## 0.8.7 — Daily recommendation in the menu bar

- Add a Daily recommendation component to the menu-bar layout editor. It displays Cockpit's full-day automatic recommendation as a percentage of the weekly quota, with a compact localized label and hover help.
- Share the existing comfort/reset planner with the status item and settings preview. Refresh with quota observations, comfort feedback, public reset changes and the clock, even while the menu is closed.
- Preserve account boundaries, mark incomplete or stale estimates, and keep remote fleet readings separate from local advice. The English status-text setting applies to the new component.
- Keep existing layouts unchanged until the component is added. Store the new layout in a fork-specific generation with older-readable projections for rollback.

## 0.8.6 — Persistent statistics date controls

- Move the reporting-range choices into a fixed left sidebar. Statistics scroll independently, keeping 7/30/90-day, month-to-date and all-history choices available at every scroll position.
- Preserve the selected period and its shared quota/cost filtering, including custom periods already saved in settings.

## 0.8.5 — Date-based quota history

- Give Statistics a quota-history timeline whose date axis follows the selected 7/30/90-day, month-to-date or all-history range, even when every observation falls within the most recent days.
- Show the dates actually covered by quota observations. Leave unobserved dates empty and separate reset cycles instead of connecting unrelated balances.
- Preserve the existing current-cycle burndown and cycle-utilization charts under expandable reset-cycle details.

## 0.8.4 — Statistics range synchronization

- Make Plan Usage history follow the Statistics page's 7/30/90-day, month-to-date and all-history selection, using the configured reporting time zone and observation dates.
- Keep all selected chart points in Statistics while preserving the compact menu chart limit. Exclude future observations without discarding valid samples that have future reset dates.

## 0.8.3 — Larger calendar text

- Increase calendar text by 50%, including dates, values, controls, reset notices and comfort charts.
- Enlarge date badges and cells, keep narrow weekly views scrollable, and wrap reset details and legends to fit the larger type.

## 0.8.2 — Daily and weekly percentage bases

- Show today's available allowance primarily as a percentage of today's effective allocation, with its equivalent weekly-quota percentage alongside it.
- Use the manual cap as the daily allocation when present. Retain partial bounds, unknown values and actual-balance limits without changing the comfort calculation.
- Make the comfort-chart hover distance conversion explicit for the GitHub macOS compiler.

## 0.8.1 — Full-day comfort-aware advice

- Show a full-day quota target separately from the amount still available today, instead of shrinking the target by the hours left until midnight.
- Deduct observed use once, respect manual caps and the actual remaining balance, and retain uncertainty when usage is incomplete.
- Continue recalculating against valid account, announced and estimated reset windows without inventing a renewed balance.
- Use the original Cockpit quota comfort curve to cap automatic advice, with a personal fit from account-scoped quota feedback or the default 25% knee. Keep Token feedback separate.
- Explain comfort limits and reset-risk sources; apply upstream risk boosts and weekend adjustment while preserving manual overrides.

## 0.8.0 — Unified calendar and usage navigation

- Give day, week and month calendars a shared date, selection and grid style; preserve daily usage, personal feedback and reset markers.
- Keep the compact Codex reset announcement above calendar period controls, with expandable details.
- Show an automatically updating homepage countdown only for a fresh, dated, pending reset announcement; hide it when absent or expired.
- Embed the existing plan-utilization and quota-burndown charts in Usage Statistics instead of an extra homepage submenu.
- Increase session list/detail space in Usage & Spend and pin the selected session receipt action above the scrolling detail.

## 0.7.1 — Fork About page

- Show CodexBar Cockpit identity and project description with current version and localized build date.
- Link support and changelog to this repository; list both upstream projects and preserve MIT attribution.
- Localize the development-build update notice while preserving updater preferences and acknowledgements.

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
