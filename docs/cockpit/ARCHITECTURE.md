# Integration architecture

## Product contract

CodexBar remains the native menu-bar shell and provider collector. One transient popover anchored
to the status item hosts Usage, Statistics, Calendar, and Receipts as peer pages. Daily advice and
personal caps appear directly on Usage. There is no independent Cockpit window or second Tauri process.

## Modules and interfaces

- `UsageStore` and `SpendDashboardController` remain the authoritative provider and cost interfaces.
  Cockpit consumes their published snapshots rather than starting a second collector.
- `CockpitPlanState` is a serializable Foundation module. It receives official quota observations and
  produces frozen daily recommendations, manual caps, observed use, and completeness.
- `CockpitPlanStore` adapts existing snapshots to the planning module and atomically persists local
  state. Provider/account identifiers scope each plan. Unknown accounts are not merged.
- `CockpitPersonalUsageModel` provides an optional weekday reference from qualified observed periods.
  Closed-day summaries survive raw-snapshot retention, preserve partial coverage, and remain scoped by
  provider/account/time zone. A separate seven-day holdout gates display; missing periods are not zero.
  This reference does not rewrite frozen recommendations or personal caps.
- `CockpitCalendarPeriod` and `CockpitCalendarLedger` provide page-local period browsing over loaded
  history, with calendar-aware boundaries and separate currency totals.
- `CockpitComfortModel` represents subjective experience against recorded Token use. Its output is
  descriptive and never converted into an official quota percentage. Local Token history belongs to
  the explicit `local-machine` scope, independently of whichever quota account is currently selected.
- `CockpitQuotaComfortModel` restores the upstream fixed smooth-knee quota curve. Weighted least squares
  fits only the knee on a 0.1% grid, with fixed subjective scores and a 14-day recency half-life.
  Its samples use observed account quota changes, including labeled partial coverage and archived daily
  observations. Calendar quota feedback is scoped by provider/account/day/time zone; corrections preserve
  captured measurements. Token feedback is a separate calendar mode and is never converted into quota.
  Missing samples show the 25% baseline curve; fitted output never rewrites frozen plans or personal caps.
- `CockpitTaskLineage` groups already-accounted sessions using bounded session metadata reads. Fork
  baseline deduplication remains owned by CodexBar's scanner. Subagents belong to their root task;
  independent forks remain independent work.
- `CockpitMenuPanelController` owns the menu-bar popover; `CockpitPanelView` owns its peer pages.
  The existing provider menu builders remain the source for provider cards and actions.
- `CockpitPanelLayout` shares screen, column, and native-card widths between the controller and view.
  Wide Usage pages keep the complete provider menu beside an independently scrolling advice column;
  narrow pages use one scrolling column. Native cards are built for the main column before mounting.
- `CockpitUsageProjection` reads the shared statistics publication with page-local filters. Calendar
  and Receipt navigation never writes the statistics page's reporting period or selected day.
- Calendar also owns subjective feedback and the experience chart. Today's feedback can capture a
  fresh, complete ambient Token sample; editing history preserves the original measurement.
- `CockpitResetHistoryClient` reads the public Codex Resets history and status API without credentials.
  Its typed records preserve announcement times and distinguish regular resets, banked resets,
  scheduled announcements, and expiring website forecasts. No public event becomes a quota observation.
- `CockpitResetHistoryStore` is owned by the status controller for the application lifetime, independent
  of popover visibility. History and status refresh independently, retain their last successful caches,
  and publish early notices with durable deduplication. Disabling notices invalidates in-flight delivery.
- Local reset estimates use the median of up to ten recent regular-reset intervals within 180 days.
  They remain explicitly approximate; an overdue estimate is not rolled forward as a new prediction.
  Scheduled times are grouped using the calendar reporting zone; unknown times stay undated.
- Settings remain in the canonical preferences window, including explicit import from CodexBar.
- The optional English status-text preference is scoped to synchronous top-menu-bar rendering and
  its layout preview. Expanded menus, Cockpit pages, settings, and notifications retain the app language.
- Receipt PNG saves use an asynchronous sheet owned by the receipt preview's actual window.
  Saving blocks only that preview; detaching the preview cancels its pending save without writing.
- `CockpitAppIdentity` centralizes fork-owned configuration, cache, defaults, and Keychain namespaces.
  `CockpitSettingsImport` exposes only a whitelist of presentation and provider selection settings.

## Accounting invariants

Use the configured local natural day consistently, including DST. Do not re-label legacy Shanghai
aggregates as local-day data; derive new daily totals from source events. Distinguish missing/partial
coverage from measured zero, and keep currencies separate. Official percentage changes are observations,
not a complete bill; gaps and resets retain uncertainty. The first daily recommendation is frozen;
manual changes affect the personal cap only. Account changes must not reuse another account's plan.

Receipts use stable session identifiers and union selected membership before summing. Parent and
child selection must not double count; unknown cost remains unknown or explicitly partial.
The selected period filters active tasks; totals cover their complete scanned sessions and can include
usage outside that period. Both the selection UI and exported receipt disclose this distinction.

## Delivery

Development bundles are isolated and ad-hoc signed. No upstream automatic update feed is accepted.
Replacing an installed CodexBar happens after user acceptance; local integration testing does not
replace or migrate an existing installation automatically. The public repository is
Kakapoo233/codexbar-cockpit; integration/native-cockpit records the initial integration.
Feature-sized commits and pull requests record each iteration.
