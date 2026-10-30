# Contributing

This project targets a native macOS menu-bar workflow. Discuss changes to quota semantics, task
ownership, storage migration, or cloud sharing before implementation.

Use `Package.resolved` and the repository's build scripts. Add synthetic fixtures for new accounting
behavior; never commit real session logs, account identifiers, credentials, or local usage caches.
Run focused tests for touched modules and `make check` before proposing a change. Keep unknown values
separate from measured zero, and preserve account, provider, currency, and time-zone scope.

Pull requests should explain the visible change, tests, and any remaining limitations. Include a
screenshot for UI changes. Maintain both upstream license notices and document new dependencies.

## Git workflow

`origin` is `Kakapoo233/codexbar-cockpit`; `upstream` is `steipete/CodexBar`.
Keep `main` as the reviewed integration baseline. Create a focused branch for each feature or fix,
commit working increments with a clear purpose, and open a pull request against this repository's
`main`. Preserve the upstream history and pinned provenance; do not force-push shared branches.
Record validation in the pull request and update the acceptance checklist when behavior changes.
Application bundles, personal settings, local usage data, and signing material are not source commits.
