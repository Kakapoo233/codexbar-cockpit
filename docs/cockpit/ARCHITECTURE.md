# Integration architecture

## Product contract

CodexBar remains the native menu-bar shell and provider collector. One transient popover anchored
to the status item hosts Usage, Statistics, Calendar, and Members & Devices as peer pages. Daily advice and
personal caps appear directly on Usage. There is no independent Cockpit window or second Tauri process.

## Modules and interfaces

- `UsageStore` and `SpendDashboardController` remain the authoritative provider and cost interfaces.
  Cockpit consumes their published snapshots rather than starting a second collector.
- `CockpitPlanState` is a serializable Foundation module. It receives official quota observations and
  produces live daily recommendations, manual caps, observed use, and completeness.
  Advice uses the latest same-account balance and remaining time to an account reset or an earlier
  valid announced/estimated reset. Predictions never create quota.
  The target is a full local day's share, not a fraction based on hours remaining until midnight.
  Current-cycle observed use is added back before allocating that share, then deducted once from
  today's available allowance. Earlier cycles stay consumed; manual caps and the actual remaining
  balance bound the allowance. Missing/partial observation retains its uncertainty.
  The UI shows available allowance as a percentage of the effective daily allocation (manual cap when
  present), together with the equivalent percentage of the weekly quota. For example, 15% of weekly quota
  remaining from a 20% daily allocation is shown as 75% of today's allocation and 15% of weekly quota.
  A known zero daily allocation displays 0%; missing measurements remain unknown in both units.
- `CockpitPlanStore` adapts existing snapshots to the planning module and atomically persists local
  state. Provider/account identifiers scope each plan. Unknown accounts are not merged.
  The status controller shares its planner with `UsageStore` for menu-bar layout and preview rendering;
  previews never instantiate another collector or persistence store. The optional Daily recommendation
  component reads `suggestedPercent`, the full-day automatic share of the weekly quota, independently
  of manual caps and the used/remaining presentation switch. Matching provider/account/organization is
  required; remote fleet sources do not use the local plan. Planner and reset metadata participate in icon
  observation, and a placed component uses the existing minute refresh scheduler. The three Available today components read `remainingDailyBudgetPercent` and retain
  `remainingSuggestedPercent` as their weekly equivalent. Incomplete observations remain upper bounds;
  missing values are never drawn as zero. Bars and bottom-up filled circles represent remaining daily
  allowance independently of the global used/remaining switch. Cockpit V8 layout keys
  retain V7-and-earlier projections so rolling back does not invalidate the existing layout.
- Codex's main weekly menu-bar Pace comparison reads the same account-matched automatic daily
  recommendation as the homepage. Expected use is that full-day target multiplied by the elapsed
  fraction of the local natural day (including DST); the target itself is not reduced. Deviation is
  today's observed use minus that reference, in weekly quota percentage points. Manual caps remain
  independent. Incomplete observations yield a one-sided lower bound and do not drive exact numeric
  conditions or colors; missing/stale/account-or-cycle-mismatched plans remain unavailable. Session
  lanes and other providers retain their window pace. The daily comparison never supplies a cumulative
  weekly progress stripe or an account exhaustion ETA; the latter remains separately labeled as a quota
  forecast. Placed pace components and their editor preview observe planner changes and minute ticks.
- `CockpitPersonalUsageModel` provides an optional weekday reference from qualified observed periods.
  Closed-day summaries survive raw-snapshot retention, preserve partial coverage, and remain scoped by
  provider/account/time zone. A separate seven-day holdout gates display; missing periods are not zero.
  This reference does not rewrite automatic recommendations or personal caps.
- `CockpitCalendarPeriod` and `CockpitCalendarLedger` provide page-local period browsing over loaded
  history, with calendar-aware boundaries and separate currency totals.
- Day, week and month reuse the same calendar date cells and reset/feedback markers. A compact reset
  announcement and period toolbar remain above the scrolling calendar and selected-day details.
  Calendar typography uses the original native text sizes; date badges, cell heights and chart areas
  match those sizes. Narrow weekly strips retain horizontal scrolling.
- The Usage homepage displays a countdown only for a fresh, pending public announcement with an exact
  future date. Estimates, undated announcements and expired deadlines never create a homepage banner.
  Plan Usage charts are embedded in Statistics and retain the existing account-scoped history selectors.
  They filter captured observations using the shared statistics period, reporting date and bucket time zone;
  Statistics charts retain all selected points, while compact menu charts keep their 30-point limit.
  The primary Statistics quota timeline uses observation timestamps on the complete selected date axis,
  with actual observation coverage shown separately. Missing dates remain empty and reset cycles are
  separated. The original current-cycle burndown and cycle-utilization views remain in expandable
  reset-cycle details; their cycle-based axes are not presented as the global reporting-period timeline.
  They are available independently of local cost tracking.
- `CockpitComfortModel` represents subjective experience against recorded Token use. Its output is
  descriptive and never converted into an official quota percentage. Local Token history belongs to
  the explicit `local-machine` scope, independently of whichever quota account is currently selected.
- `CockpitQuotaComfortModel` restores the upstream fixed smooth-knee quota curve. Weighted least squares
  fits only the knee on a 0.1% grid, with fixed subjective scores and a 14-day recency half-life.
  Its samples use observed account quota changes, including labeled partial coverage and archived daily
  observations. Calendar quota feedback is scoped by provider/account/day/time zone; corrections preserve
  captured measurements. Token feedback is a separate calendar mode and is never converted into quota.
  Missing samples use the 25% baseline knee. Automatic advice uses the fitted knee as a comfort cap;
  it never changes a user's manual cap. The personal planner adapts upstream `planRemainingQuota`,
  not v0.3.4's shared-account override (which removes the comfort cap).
  For current-cycle balance plus observed use P, the full-day allocation is A = P × min(1, day duration /
  remaining horizon). Reset-risk boost is (P − A) × p². Earlier-cycle use is added once before applying
  the full-day comfort cap K × (1 + 1.5p), multiplied by 0.75 on local weekends. Available allowance then
  subtracts all observed use once and cannot exceed the actual balance. Partial observations remain bounds.
  Codex's default p = 0.1 is explicitly a model assumption; fresh numeric community watch estimates may
  replace it. A fresh dated regular announcement uses p = 1 only within the next 24 hours and before the
  account reset. More distant announcements still shorten the planning horizon. Other providers use p = 0.
  A history-derived estimated date is not treated as a probability. Stale public risk metadata falls back
  to the explicit default, independently of notification settings.
  Source: [upstream personal planner](https://github.com/HouSiyuan2001/codex-cockpit/blob/cefcbc9efe03071150431645b4ebb51e7faac574/src/lib/dynamicQuota.ts).
- `CockpitTaskLineage` groups already-accounted sessions using bounded session metadata reads. Fork
  baseline deduplication remains owned by CodexBar's scanner. Subagents belong to their root task;
  independent forks remain independent work.
- `CockpitMenuPanelController` owns the menu-bar popover; `CockpitPanelView` owns its peer pages.
  The existing provider menu builders remain the source for provider cards and actions.
- Statistics keeps its reporting-period choices in a fixed sidebar outside the scrolling content.
  The sidebar uses the same controller binding as cost and quota history; direct session-detail
  navigation retains its captured context and restores the sidebar when returning to Statistics.
- `CockpitPanelLayout` shares screen, column, and native-card widths between the controller and view.
  Wide Usage pages keep the complete provider menu beside an independently scrolling advice column;
  narrow pages use one scrolling column. Native cards are built for the main column before mounting.
- `CockpitUsageProjection` reads the shared statistics publication for the Calendar without changing
  the statistics page's reporting period or selected day. Receipts are an action on the selected historical
  session in `SessionUsageBrowser`, using that browser's reporting range, currency and privacy settings.
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

## Windows presentation

The independent Windows client keeps one `widget` WebView and one React App data owner. A local
display preference selects the existing tray panel or a compact floating Codex summary. Switching
surfaces reuses quota observations, planning and refreshes. Native presentation events carry the
target page so a settings request received while compact cannot be lost during mounting.
The compact surface remains visible on blur; closing or blurring its full panel restores the compact
surface. Explicit hide is recoverable from the tray. Generation checks invalidate old blur callbacks.
Compact geometry is scaled with text and monitor DPI, clamped to the work area, and stored in a
separate local floating-window document. Preview and smoke builders retain their credential-free
isolation and never start real collectors or cloud synchronization.

## Personal iCloud Drive synchronization

The fork uses `ICloudDriveSyncCoordinator` and `ICloudDriveReplica` for credential-free personal document synchronization. The old CloudKit engine remains available for its protocol tests but is not activated by this app. Each device owns one versioned JSON file; per-key Lamport revisions and tombstones merge edits without shared-file overwrites. A local journal acknowledges only successfully applied typed projections. First-join defaults cannot overwrite existing cloud values. Undownloaded, corrupt or newer documents stop the exchange rather than becoming empty state.

Settings use an explicit field whitelist and an atomic menu-layout/rule bundle. Planner synchronization includes personal caps and subjective records only, preserving quota/account boundaries and excluding raw observations. Local-machine Token measurements remain device-local even when the feeling is shared. Application startup, activation and a 15-second timer drive exchanges. Apple upload metadata is separate from the last successful local file exchange. See [setup and limits](ICLOUD_DRIVE.md).

## Team synchronization

`CockpitTeamStore` is owned by the app delegate and shared by the menu panel and canonical settings.
Its polling and account-identity observation continue while the popover is closed. It is separate from
CodexBar's personal iCloud sync: no provider credentials or its account snapshot payloads are reused.
`CockpitTeamClient` uses a typed allowlist compatible with the original v2 Cloudflare Worker, strict
HTTPS origins, no redirects/cookies/HTTP authentication, bounded responses, and no automatic mutation retry.
Team credentials use a fork-owned, non-synchronizing, ThisDeviceOnly Keychain entry with no-UI reads.
Only connection metadata and typed caches are persisted to `team-sync.json`; invitations stay in memory.
A received enrollment token is retained in memory until Keychain and connection metadata saves succeed.
Owner disconnection is intentionally a pause because v2 cannot restore or transfer ownership.

One v2 space is one Codex shared-account planning pool. A person can own several devices but receives
one default share. People, device assignments, and per-person daily caps use server revisions; stale
budget drafts must also match the day and reset cycle. The team's risk-tolerance formula and independent
personal overrides follow upstream; they never alter local automatic recommendations or provider limits.
The v2 server's natural day is explicitly Asia/Shanghai. Existing calendar reporting remains independent.

Activity export requires an explicit account binding and an independent-source declaration. It accepts
only native live-system Codex data already published by the existing collector, in USD with compatible
provenance and Shanghai day buckets. Remote account meters, enrichment/mixed sources, other providers,
paths, identities, titles, prompts, credentials and subjective feedback are excluded. Day aggregates
start at the next Shanghai midnight after confirmation, with current-day/partial coverage preserved.
Known account identity changes permanently invalidate the binding, including changes without quota data.
Shared snapshots replace older versions per random device ID with monotonic timestamps; they are never
summed with this Mac's local ledger. Copied logs require only one publishing device; summaries cannot
prove cross-device deduplication. Account quota observations are one plan basis, never additive device use.

The MIT upstream Worker, schema migrations and tests live in `cloud/usage-sync-worker/`. Deployment is
self-hosted and is a separate acceptance step; local cloud configuration, bootstrap secrets and runtime
state are ignored by Git. See [team setup](TEAM_SYNC.md) and the Worker's protocol reference.

## Accounting invariants

Use the configured local natural day consistently, including DST. Do not re-label legacy Shanghai
aggregates as local-day data; derive new daily totals from source events. Distinguish missing/partial
coverage from measured zero, and keep currencies separate. Official percentage changes are observations,
not a complete bill; gaps and resets retain uncertainty. Automatic advice recomputes from observations
and valid reset horizons, including minute-by-minute time changes. Manual changes affect the personal cap only. Account changes must not reuse another account's plan.

The receipt action snapshots exactly one selected session in the displayed reporting period. It does not
expand task descendants or reload all history. Unknown cost remains unknown; source lower bounds remain
partial. Hidden account labels and session titles are excluded from the preview and PNG. The existing
task-grouping helpers retain stable source/session identities and union membership before summing.

## Delivery

Development bundles are isolated and ad-hoc signed. No upstream automatic update feed is accepted.
Replacing an installed CodexBar happens after user acceptance; local integration testing does not
replace or migrate an existing installation automatically. The public repository is
Kakapoo233/codexbar-cockpit; integration/native-cockpit records the initial integration.
Feature-sized commits and pull requests record each iteration.
