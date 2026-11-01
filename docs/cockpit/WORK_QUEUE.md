# Active delivery queue

Updated 2026-10-31. These items are one ongoing local developer-app iteration; source changes alone do not count as installed acceptance.

| Request | Status | Acceptance |
| --- | --- | --- |
| Make statistics time-range choices update Plan Usage | Implemented and installed in 0.8.4; launch pending unlock | The five range choices filter observed plan history in the reporting time zone; Statistics retains the selected points beyond the compact menu's 30-point limit. |
| Enlarge calendar text by 50% | Implemented and installed in 0.8.3 | Calendar dates, values, native selectors and details use 1.5× type sizes; date cells and badges expand with the text, and narrow weekly layouts remain scrollable. |
| Show today's availability relative to the daily allocation, alongside weekly quota percentage | Implemented and installed in 0.8.2 | A 20% weekly daily allocation with 5% weekly consumed displays 75% of today's allocation and 15% of weekly quota. Manual caps select the denominator; partial/unknown values retain their meaning. |
| Correct full-day advice and show available allowance separately | Implemented and installed in 0.8.1 | 90% remaining / 6 days gives a 15% base allocation at 08:00, before reset-risk boost and comfort cap; observed use is deducted once and allowance is bounded by actual balance. |
| Use the original Cockpit comfort curve in daily estimates | Implemented and installed in 0.8.1 | Same-account quota feedback fits the curve; baseline/fitted cap and risk sources are explained. Manual caps retain priority. Token feedback never becomes quota percentage. |
| Unify day/week/month calendar styling, inspired by Apple Calendar | Implemented and installed in 0.8.0 | Shared date/selection/grid styling; all status/reset markers remain reachable at wide and narrow widths. |
| Keep Codex reset announcements above calendar period selection | Implemented and installed in 0.8.0 | Compact pinned announcement first, period selector immediately below; details expand without hiding the calendar. |
| Show a short confirmed reset date and countdown at the top of Usage | Implemented and installed in 0.8.0 | Only fresh dated pending announcements; no banner for estimates, absent dates, cancellation or expired deadlines. |
| Move Plan Usage into Statistics | Implemented and installed in 0.8.0 | Existing account-scoped history and burndown charts embedded directly; remove extra unified-homepage submenu. |
| Increase Usage & Spend session height | Implemented and installed in 0.8.0 | More visible list/detail rows; scrolling remains available on smaller displays. |
| Integrate usage receipts into Usage & Spend | Implemented and installed in 0.8.0 | One action on the selected historical session, preview/export in context, no separate receipt navigation page. |
| Diagnose Usage & Spend not working | Closed by user | User reports the problem is no longer present and requested skipping it; no speculative fix. |
| Update Settings About | Delivered; live-verified | Correct fork identity, version, project/support/changelog links and upstream attribution. |

0.8.4 validation: reproduced Plan Usage receiving all 5 synthetic observations for every range, then verified the selected counts become 1/3/4/2/5. All 40 tests across 8 suites pass, including actual native picker actions in the full statistics pane, retained-page hit testing, reporting-zone/DST bounds, fresh quota samples with costs disabled, and dense chart widths. `make check` passed (3,244 Swift files); final clock and chart-width edits passed targeted format/lint. Packaging, signatures and isolated startup passed. Version 0.8.4 build 24 is installed with a 0.8.3 backup; launching the installed app awaits unlocking the Mac. Live user interaction is not verified.

0.8.3 validation: 9 focused tests across 4 suites passed, including native picker font size, action-to-binding updates, external selection changes and invalid choices. `make check` passed (3,241 Swift files). Synthetic wide/narrow panels and day/week/month/year layouts were visually checked locally. Packaging, signatures and isolated startup passed; developer app 0.8.3 build 23 is installed and verified running with a 0.8.2 backup. Live panel interaction remains unverified because the UI connection times out.

0.8.2 validation: 93 focused tests across 14 suites passed. `make check` passed (3,238 Swift files; 23 locale catalogs). A GitHub compiler error in the comfort chart was fixed with an explicit distance conversion; targeted format/lint and 11 follow-up tests passed. Wide and narrow synthetic panels show both daily and weekly units. Packaging, signatures and isolated startup passed; developer app 0.8.2 build 22 is installed and running with a 0.8.1 backup. Live panel interaction remains unverified because the UI connection times out.

0.8.1 validation: 81 focused tests across 12 suites passed. The original 08:00 regression returned 15.75% with the default risk model instead of 10%. A local-data calculation retained partial coverage. User feedback clarified that today's available percentage must use the daily allocation as its denominator; 0.8.2 adds that display while retaining the weekly equivalent.

0.8.0 validation: 122 focused tests across 18 suites passed, plus 2 follow-up plan-history refresh tests. Packaging and isolated startup passed. About was live-verified; final interactive acceptance of the updated Statistics/session controls is pending opening Settings. Synthetic screenshots remain local. Original CodexBar is not replaced.
