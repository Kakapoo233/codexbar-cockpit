# Contributing

This project targets a native macOS menu-bar workflow. Discuss changes to quota semantics, task
ownership, storage migration, or cloud sharing before implementation.

Use `Package.resolved` and the repository's build scripts. Add synthetic fixtures for new accounting
behavior; never commit real session logs, account identifiers, credentials, or local usage caches.
Run focused tests for touched modules and `make check` before proposing a change. Keep unknown values
separate from measured zero, and preserve account, provider, currency, and time-zone scope.

Pull requests should explain the visible change, tests, and any remaining limitations. Include a
screenshot for UI changes. Maintain both upstream license notices and document new dependencies.
