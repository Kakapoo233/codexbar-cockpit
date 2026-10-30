# CodexBar Cockpit team synchronization service

This optional, self-hosted Cloudflare Worker stores shared-space membership, the latest aggregate
snapshot from each device, member/device assignments, and daily budget plans in D1. It is a service
for mutually trusted small teams. A Cloudflare account is needed only by the operator; invited
members use the service URL and invitation code in the native app.

The service is copied from [Codex Cockpit v0.3.4](https://github.com/HouSiyuan2001/codex-cockpit/tree/v0.3.4/cloud/usage-sync-worker),
commit `cefcbc9efe03071150431645b4ebb51e7faac574`, under the included [MIT license](LICENSE).
The v2 HTTP contract is preserved. The package and Worker example retain the upstream service name
for compatibility; an operator may choose a different Worker and database name in local configuration.
The original Tauri client, credentials, and local deployment state are not included.

## Local verification

Node.js 24 or later is required. The tests use built-in Node modules and in-memory SQLite; they do
not need installed npm dependencies, Cloudflare access, provider accounts, or real usage data.

```sh
node --test test/*.test.mjs
```

The suite covers migrations, request limits, recursive snapshot field validation, member/device
binding, invitations, space isolation, settings conflicts, independent personal-plan revisions,
stale uploads, and revocation. See [PROTOCOL.md](PROTOCOL.md) for client integration.

## Deploy to your own account

The commands below create resources in the operator's account. Use an existing service's database
and reviewed migrations when upgrading; do not create a replacement database over existing data.
The service does not deploy when the desktop app is built or installed.

```sh
npm ci
WRANGLER_SEND_METRICS=false npx wrangler login
WRANGLER_SEND_METRICS=false npx wrangler whoami
cp wrangler.example.toml wrangler.local.toml
WRANGLER_SEND_METRICS=false npx wrangler d1 create codex-cockpit-sync
```

Confirm the intended account in the browser. Fill in the returned database ID/name only in
`wrangler.local.toml`. Keep `binding = "DB"`, the migration directory, and both rate-limit bindings.
Choose two namespace IDs unique within the account. The local configuration, `.dev.vars`, Wrangler
state, and installed dependencies are ignored by Git.

```sh
WRANGLER_SEND_METRICS=false npx wrangler d1 migrations list codex-cockpit-sync --remote --config wrangler.local.toml
WRANGLER_SEND_METRICS=false npx wrangler d1 migrations apply codex-cockpit-sync --remote --config wrangler.local.toml
WRANGLER_SEND_METRICS=false npx wrangler secret put BOOTSTRAP_SECRET --config wrangler.local.toml
WRANGLER_SEND_METRICS=false npm run deploy
```

Replace the database name in these commands if customized. Enter a strong generated bootstrap
secret at Wrangler's prompt; keep it in a password manager, outside source, shell arguments, logs,
and chat. It authorizes creating spaces. It is separate from Cloudflare credentials and member
invitation codes. No purchased domain is required: the deployed `workers.dev` HTTPS origin is enough.

`GET /health` proves only Worker reachability. Before claiming complete synchronization, verify two
devices can join the same space, receive each other's group changes and aggregates, preserve missing
costs, reject conflicting edits, and lose access when revoked. After creating the required spaces,
operators can disable new space creation with `wrangler secret delete BOOTSTRAP_SECRET`; invitations
and existing-space synchronization continue working.

## Data handling and operating limits

- D1 holds the latest snapshot per device, shared settings, plans, hashed access tokens, and hashed
  invitation codes. Space members and the server operator can read shared data. It is not end-to-end
  encrypted. Do not send provider credentials, raw conversations, or filesystem paths.
- The protocol can carry optional task names and subjective feedback. Native-client consent and
  allowlisted projection decide whether those fields are sent. Their protocol support does not
  authorize uploading them. Aggregate-only snapshots omit them entirely.
- Revoking a device removes its access and hides its snapshots from active peers. It does not erase
  database rows or peers' caches. There is no general data-deletion or space-deletion API in v2;
  the operator is responsible for retention, backups, restoration, and deletion.
- Each space has at most 32 active devices. Request bodies are limited to 1 MiB, or 8 KiB for daily
  plans. Both rate-limit bindings are required; missing bindings fail closed. Limits are approximate
  regional protections, not a global billing cap.
- Daily plans use a fixed UTC+8 natural day. Their percentages are advisory planning values; the
  service does not move or enforce provider quotas. v2 has no account-pool isolation field.
- Keep a D1 backup before schema changes. Free-plan resources have limits; review the account's
  billing and usage before enabling paid services.

Official references: [D1 setup](https://developers.cloudflare.com/d1/get-started/),
[D1 migrations](https://developers.cloudflare.com/d1/reference/migrations/),
[Wrangler commands](https://developers.cloudflare.com/workers/wrangler/commands/),
[D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/), and
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/).
