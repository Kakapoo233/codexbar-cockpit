# Preserved v2 client contract

All timestamps ending in `At` are ISO 8601 strings unless explicitly described as Unix seconds.
Responses have `ok: true`, or `ok: false, error: <code>`. Non-health routes require configured rate
limiters. Authenticated routes require `Authorization: Bearer ccs_<43 base64url characters>`.
Treat tokens as secrets and never persist them in ordinary preferences or logs.

Use an HTTPS origin. Client-side redirects should be rejected so credentials cannot be forwarded to
another service. Device IDs are stable, distinct for each installation, and match
`[A-Za-z0-9][A-Za-z0-9_.-]{0,127}` (except `.`, `..`, or a trailing dot). Device display names and
person names must be nonempty, control-free, and at most 64 characters after trimming.

## Enrollment and access

| Request | Body | Success response fields beyond `ok` |
| --- | --- | --- |
| `POST /v1/spaces` | `{name, displayName, deviceId}`; header `x-bootstrap-secret` | HTTP 201: `spaceId`, `token`, `inviteCode`, `inviteExpiresAt` (Unix seconds) |
| `POST /v1/join` | `{inviteCode, displayName, deviceId}` | HTTP 201: `spaceId`, `token` |
| `POST /v1/invites` | Owner only; `{maxUses?, expiresHours?}`; defaults 1 and 24 | HTTP 201: `inviteCode`, `inviteExpiresAt` (Unix seconds) |
| `POST /v1/devices/revoke` | Owner only; `{deviceId}` for another active member device | HTTP 200 |
| `GET /v1/me` | None | `space:{id,name}`, `deviceId`, `role`, `members`, `groupSettings`, `sharedSettings` |

`members` is the active **device** roster, not the list of people. Each item has `deviceId`,
`displayName`, `role`, nullable `heartbeatAt`/`updatedAt` (Unix seconds), and nullable
`syncInfo:{protocolVersion:2,appVersion,settingsRevision}`. People are represented by shared groups.
An owner cannot revoke its own device. A revoked token receives 401 and its snapshot is excluded.

Invitation codes begin `CCI-`; create-space invitations last 24 hours and allow one use. Additional
invitations allow 1–20 uses and 1–720 hours. Enrollment has no request-id idempotency contract; do not
blindly retry a create/join after an ambiguous response without explaining recovery to the user.

## Shared settings and people

`sharedSettings` is `{revision:<nonnegative integer>,value:<settings or null>}`. A new space starts
with `value:null`, revision 0. `groupSettings` is the legacy group projection and can also be null.

The owner initializes the complete settings document with `POST /v2/settings`:

```json
{
  "expectedRevision": 0,
  "value": {
    "schemaVersion": 2,
    "groups": {
      "groups": [{"id":"person-a","name":"Member A","deviceIds":["device-a"]}],
      "defaultGroupId": "person-a"
    },
    "pricing": {
      "models": {"example-model":{"in":2,"out":4,"cache_read":1}},
      "aliases": {}
    },
    "costPolicy": "event-context-v1"
  }
}
```

The example rate is synthetic, not a provider price. Rates are USD per million tokens; clients must
initialize actual known rates from their pricing source. `models` must contain 1–2048 entries, each
with finite nonnegative `in`, `out`, and `cache_read` rates no greater than 1e6. An optional
`canonical_slug` and aliases may be supplied. Do not initialize unknown prices as measured zero.

Any active device can then `POST /v2/groups` with `{expectedRevision,groups:<group projection>}`.
The server preserves pricing and increments the settings revision. Without initialized shared
settings this returns 409 `settings_unavailable`. Group IDs and names must be unique; at most 32
people, at most 128 devices per person, and a device can appear in only one person. `defaultGroupId`
is either null or a configured person ID. A default view does not attribute unassigned devices.

`GET /v2/settings` returns `{ok:true,sharedSettings}`. Settings and group mutations return the same
shape. Revision mismatches return 409 `settings_conflict`; refresh and let the user reapply changes.
Only the owner may change full settings/pricing. Renames preserve person IDs.

## Aggregate snapshots

`POST /v1/sync` takes `{deviceId,payload,clientInfo?}`. `clientInfo`, if supplied, is
`{protocolVersion:2,appVersion:<1–64 ASCII alphanumeric . + ->,settingsRevision:<nonnegative integer>}`.
A minimal privacy-preserving, unavailable aggregate is valid:

```json
{
  "deviceId": "device-a",
  "payload": {
    "_device": "device-a",
    "_ts": 1793318400,
    "_cockpit": {"schemaVersion":1,"status":"unavailable"},
    "codex": {"ranges":{}},
    "_ledger": {"v":1,"tools":{"codex":{}}}
  },
  "clientInfo": {"protocolVersion":2,"appVersion":"0.6.0","settingsRevision":1}
}
```

`_ts` must be a positive integer Unix timestamp, no more than 300 seconds in the future; use the
actual collection time, not the fixed example. A device cannot upload another device's identity.
Only the newest `_ts` replaces a stored snapshot; identical payload hashes do not rewrite it.
A successful response is `{ok:true,snapshots:[...]}`. `GET /v1/snapshots` has the same response.
Each snapshot is `{deviceId,displayName,updatedAt:<Unix seconds>,payload}`. This is a complete latest
snapshot per active device, not an increment to sum on every poll.

Optional `codex.ranges` keys are `today`, `yesterday`, `week`, `month`, `all`. Each value has required
`in`, `out` nonnegative integer counts and `models` array, with optional `cached`, `reason` counts
and nullable `cost`. Each range model has required `model_id`, `in`, `out`, optional `name`, `cr`,
`reason`, nullable `cost`. `cr` denotes cached input. Missing prices remain missing/null.

`_ledger.tools.codex` maps valid `YYYY-MM-DD` dates to aggregates with required `in`, `out`, and a
`models` **dictionary** keyed by model ID, with optional `cached`, `reason`, nullable `cost`. Each
ledger model has required `in`, `out`, optional `name`, `cr`, `cw`, `reason`, nullable `cost`.
Dates are the original producer's day buckets; do not silently relabel another time zone's totals.
At most 4096 ledger days and 256 models per bucket are accepted.

`_cockpit`, if present, requires `schemaVersion:1` and may contain `collectedAt` (ISO timestamp),
`status` (`ready`, `partial`, `unavailable`), `retainedDays` (nonnegative integer), and `nativeDays`
(date array). `_range_bounds`, if present, maps the range keys to `{start:<date or null>,end:<date or null>}`.

Snapshot fields are recursively allowlisted. Optional `comfortFeedbackVersion:1` plus
`comfortFeedback` and optional `taskUsage` use the strict schemas in `src/snapshot-schema.js` and
`src/index.js`; omit them for aggregate-only sharing. Do not attach credentials, raw messages, file
paths, arbitrary metadata, account-pool IDs, or measurement-kind fields: v2 rejects those fields.
Only Codex aggregate keys are supported; Claude or provider account meters must not be mislabeled
as Codex device activity. Account attribution and copied-log duplication must be resolved before
using snapshots for shared quota allocation.

## Daily advisory plans

`POST /v2/daily-plan` both reads/creates a plan and optionally modifies it:

```json
{
  "basis": {
    "localDate":"2026-10-30",
    "anchorAt":"2026-10-30T01:00:00.000Z",
    "remainingPercent":80,
    "resetsAt":"2026-11-03T01:00:00.000Z"
  },
  "initialRisk":20,
  "change":{"kind":"person","personId":"person-a","value":12,"expectedRevision":0}
}
```

Use the actual current UTC+8 day and current observation. `anchorAt` must be within that day and no
more than five minutes in the future; `resetsAt` must be future and within eight days. Percentages
are finite 0–100. `initialRisk` is optional/null. `change` is optional. The first request for a
space/day/reset cycle freezes `basis` and initial risk. Equivalent reset timestamps are canonicalized.

Response: `{ok:true,plan:{basis,people:{<personID>:{value,revision}},risk:{value,revision}}}`. Values can
be null. Only a device assigned to the target person can edit that person's value, including owner
devices; each person's revision is independent. `change.kind:"risk"` omits `personId` and can be
edited by any active device. A stale field revision returns 409 `plan_conflict`, normally with the
current `plan`; refresh before retrying. Changes do not automatically redistribute other people's
caps or impose a provider-side limit. The server stores the plan, not a token-to-quota conversion.
