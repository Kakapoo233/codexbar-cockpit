# Delivery and acceptance

User-approved scope: all CodexBar providers; complete local statistics, calendar, planning, subjective
feedback, and task receipts; native menu-bar summary and separate detail window; eventual replacement
of the installed CodexBar after acceptance. Project: CodexBar Cockpit, MIT, intended public repository
`Kakapoo233/codexbar-cockpit`.

## Foundation

- [x] Inspect both upstream repositories and licenses.
- [x] Pin latest stable CodexBar v0.82.0 and Cockpit v0.3.4.
- [x] Compile the unmodified CodexBar baseline on Apple Silicon.
- [ ] Verify isolated application identity, settings, caches, and credential namespaces.
- [ ] Validate explicit import of original display settings using synthetic fixtures.

## Integrated behavior

- [ ] Menu-bar entry and persistent native Cockpit window.
- [ ] Existing provider and Usage & Spend capabilities retained.
- [ ] Monthly calendar driven by the same daily ledger.
- [ ] Daily frozen recommendation, personal cap, and cross-reset observation accounting.
- [ ] Subjective feedback records and Token experience chart.
- [ ] Parent/subagent task grouping and deduplicated selected-task receipt.
- [ ] PNG preview, save, and clipboard export, including Chinese and missing-cost cases.

## Verification and release

- [ ] Focused accounting, persistence, identity, and receipt tests pass.
- [ ] `make check` passes, or upstream/tooling blockers are precisely documented.
- [ ] Integrated app compiles and packages with independent identity.
- [ ] Native UI visibly verified on this Mac; original app remains recoverable.
- [ ] User acceptance and final settings migration.
- [ ] Create and publish public GitHub repository (owner deferred sign-in).
- [ ] Release automation/signing/update feed configured for this fork.
