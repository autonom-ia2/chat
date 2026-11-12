# CRM ↔ n8n Integration Guide

This guide shows how to connect the CRM Kanban to [n8n](https://n8n.io) (or any
automation/HTTP tool) in **both directions**:

- **TRIGGER (CRM → n8n):** signed outbound webhooks for card lifecycle events.
- **ACTION (n8n → CRM):** authenticated REST calls that create, move, and close
  cards using a **scoped, revocable API token**.

> Discovery card: in Chatwoot go to **Settings → Integrations → n8n (CRM
> Connections)**. It deep-links to the two setup screens described below.

---

## Requirements

> **n8n must be reachable at a public HTTPS URL.**
>
> Outbound webhooks are sent through Chatwoot's SSRF-protected fetcher, which
> **blocks private/loopback/link-local IP ranges** (e.g. `10.0.0.0/8`,
> `192.168.0.0/16`, `127.0.0.1`, `localhost`, `*.internal`). A self-hosted n8n
> on a private network will silently fail to receive deliveries.
>
> Expose n8n through a **public HTTPS endpoint** before subscribing — for
> example a reverse proxy, a cloud-hosted n8n, or a tunnel
> (`ngrok`, Cloudflare Tunnel, etc.). This is a global process-level guard;
> there is no per-connection allowlist to bypass it.

Two feature gates must both be ON for the integration to appear and function:

1. The `crm_integration` account feature (drives the connection card visibility).
2. `CRM_KANBAN_ENABLED=true` (the CRM Kanban itself).

---

## Part 1 — TRIGGER: CRM events → n8n (outbound webhooks)

### 1.1 Create the webhook

1. In Chatwoot: **Settings → Integrations → Webhooks → Add new webhook**.
2. Set the **Webhook URL** to your n8n **Webhook** node's *Production URL*.
3. Under **CRM events**, subscribe to the events you care about (see below).
4. Save. Chatwoot generates a per-webhook signing secret used for HMAC.

### 1.2 Events (MVP)

| Event (canonical) | Fires when |
| --- | --- |
| `crm.card.created`  | A card is created. |
| `crm.card.moved`    | A card moves to a different stage. |
| `crm.card.won`      | A card is closed as **won**. |
| `crm.card.lost`     | A card is closed as **lost**. |
| `crm.card.reopened` | A previously closed card is reopened. |
| `crm.card.archived` | A card is archived. |

### 1.3 Delivery envelope

Each delivery is an HTTP `POST` with a JSON body and these headers:

| Header | Meaning |
| --- | --- |
| `X-Chatwoot-Signature`  | `sha256=<hex>` HMAC of `"{timestamp}.{body}"` (see 1.5). |
| `X-Chatwoot-Timestamp`  | Unix epoch seconds when the request was signed. |
| `X-Chatwoot-Event-Id`   | **Stable** logical event id (`crm_activities.id`). Use this to **dedup**. |
| `X-Chatwoot-Delivery`   | **Per-attempt** UUID. Changes on every retry — do NOT dedup on this. |

> Deliveries are retried on transient failures (timeout / connection error /
> 5xx) with backoff. Retries reuse the same `X-Chatwoot-Event-Id` but get a new
> `X-Chatwoot-Delivery`. Treat delivery as **at-least-once** and dedup on
> `event_id`.

### 1.4 Payload shape

Top-level envelope (identical for every event):

```json
{
  "event": "crm.card.won",
  "event_id": 90431,
  "account_id": 7,
  "timestamp": "2026-06-10T12:34:56Z",
  "data": { /* card object, see below */ },
  "changed_attributes": null
}
```

The `data` object (PII is **excluded by default** — no contact email/phone, no
owner email, no AI summary/value, no raw conversation content):

```json
{
  "id": 1234,
  "pipeline_id": 3,
  "stage_id": 12,
  "contact_id": 88,
  "conversation_id": 540,
  "inbox_id": 2,
  "owner_id": 15,
  "team_id": 4,
  "title": "Acme renewal",
  "status": "won",
  "value_cents": 1200000,
  "currency": "BRL",
  "lost_reason": null,
  "source": "n8n",
  "priority": "high",
  "score": 80,
  "external_id": "lead-abc-123",
  "entered_stage_at": "2026-06-09T10:00:00Z",
  "last_activity_at": "2026-06-10T12:34:00Z",
  "last_message_at": "2026-06-10T12:00:00Z",
  "expected_close_at": "2026-06-15T00:00:00Z",
  "next_follow_up_at": null,
  "closed_at": "2026-06-10T12:34:56Z",
  "created_at": "2026-06-01T08:00:00Z",
  "updated_at": "2026-06-10T12:34:56Z",
  "is_standalone": false,
  "pipeline": { "id": 3, "name": "Sales" },
  "stage":    { "id": 12, "name": "Won", "position": 5 },
  "contact":  { "id": 88, "name": "Maria Silva" },
  "owner":    { "id": 15, "name": "Joao Sales" },
  "inbox":    { "id": 2, "name": "Website", "channel_type": "Channel::WebWidget" }
}
```

Per-event notes:

- `crm.card.moved` — `data.stage` reflects the **new** stage; `changed_attributes`
  may carry the diff when available.
- `crm.card.won` / `crm.card.lost` — `status` is `won`/`lost`, `closed_at` is set;
  `lost_reason` populated for losses.
- `crm.card.reopened` — `status` returns to an open value; `closed_at` cleared.
- `crm.card.archived` — `status` is `archived`.
- Null fields are omitted from `data` (the payload is compacted).

#### Opt-in contact PII

If (and only if) the webhook has **Include contact PII** enabled, the `contact`
block additionally contains `email` and `phone_number`:

```json
"contact": { "id": 88, "name": "Maria Silva",
             "email": "maria@example.com", "phone_number": "+5511999999999" }
```

Nothing else is ever added (no owner email, no AI fields).

### 1.5 Verifying the signature (and rejecting replays)

Compute `HMAC_SHA256(secret, "{X-Chatwoot-Timestamp}.{raw_request_body}")` and
compare (constant-time) to the hex after `sha256=` in `X-Chatwoot-Signature`.
Then **reject stale timestamps** and **dedup by `X-Chatwoot-Event-Id`**.

n8n **Code** node (run right after the Webhook node):

```js
const crypto = require('crypto');

// Configure these:
const SECRET = $env.CRM_WEBHOOK_SECRET;       // the per-webhook signing secret
const TOLERANCE_SECONDS = 300;                // reject anything older than 5 min

const headers = $input.first().json.headers || {};
const sigHeader = headers['x-chatwoot-signature'] || '';
const timestamp = headers['x-chatwoot-timestamp'] || '';
const eventId = headers['x-chatwoot-event-id'] || '';

// n8n must be configured to expose the RAW body. With the Webhook node option
// "Raw Body" enabled, the raw bytes are available; otherwise re-stringify the
// parsed JSON EXACTLY as received (key order must match — prefer Raw Body).
const rawBody = $input.first().json.rawBody
  ?? JSON.stringify($input.first().json.body);

// 1) Signature check (constant-time)
const expected =
  'sha256=' + crypto.createHmac('sha256', SECRET)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex');

const a = Buffer.from(sigHeader);
const b = Buffer.from(expected);
if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
  throw new Error('Invalid HMAC signature');
}

// 2) Reject stale timestamps (replay protection)
const ageSeconds = Math.floor(Date.now() / 1000) - parseInt(timestamp, 10);
if (Number.isNaN(ageSeconds) || Math.abs(ageSeconds) > TOLERANCE_SECONDS) {
  throw new Error('Stale or invalid timestamp');
}

// 3) Dedup by stable event_id (at-least-once delivery → may repeat)
//    Use n8n static data (or an external store / data table) as the seen-set.
const store = $getWorkflowStaticData('global');
store.seenEventIds = store.seenEventIds || {};
if (store.seenEventIds[eventId]) {
  return [];               // already processed this logical event — drop it
}
store.seenEventIds[eventId] = Date.now();

return $input.all();
```

> The raw-body caveat matters: HMAC is computed over the exact bytes Chatwoot
> sent. Enable the Webhook node's **Raw Body** option and sign against those
> bytes. Re-serializing parsed JSON can change whitespace/key order and break
> verification.

---

## Part 2 — ACTION: n8n → CRM (REST API with a scoped token)

### 2.1 Mint a scoped token

1. In Chatwoot: **CRM → Settings → Integration tokens** (or the **Create CRM API
   token** button on the n8n connection card).
2. Give it a name, select the **scopes** it needs (least privilege), and create.
3. **Copy the token now — it is shown only once.**

Recommended scopes per use case:

| Use case | Scopes |
| --- | --- |
| Create / upsert cards | `crm_manage_cards` |
| Move cards between stages | `crm_move_cards` |
| Close (win / lose / reopen) | `crm_manage_cards` |
| Read-only sync | `crm_view` |

The token is **CRM-only**: it cannot touch conversations, contacts (outside the
CRM card surface), admin, or native reports. Revoking it invalidates the secret
immediately.

### 2.2 Authentication

Send the secret in the `api_access_token` header on every request.

In n8n: add a **Header Auth** credential — `Name: api_access_token`,
`Value: <your token>` — and attach it to your **HTTP Request** nodes.

Base URL: `https://<your-chatwoot-host>/api/v1/accounts/<ACCOUNT_ID>/crm`

### 2.3 Idempotency (important for retries)

n8n retries are **at-least-once**. Two mechanisms keep retries from duplicating
work:

- **`external_id` (upsert):** pass a stable `external_id` on `POST /crm/cards`.
  A repeat with the same `external_id` **updates** the same card (HTTP `200`)
  instead of creating a duplicate (`201` on first insert). A genuine conflict
  returns `409` `crm.card.external_id_conflict`.
- **`Idempotency-Key` header:** for writes without an `external_id` (move /
  close), send a unique `Idempotency-Key`. A replayed key returns the stored
  response with header `Idempotency-Replayed: true`; an in-flight duplicate
  returns `409`.

### 2.4 Examples

#### Create / upsert a card (idempotent)

```bash
curl -sS -X POST \
  "https://chat.example.com/api/v1/accounts/7/crm/cards" \
  -H "api_access_token: $CRM_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 2f1c9a8e-create-lead-abc-123" \
  -d '{
    "external_id": "lead-abc-123",
    "title": "Acme renewal",
    "pipeline_id": 3,
    "stage_id": 9,
    "source": "n8n",
    "value_cents": 1200000,
    "currency": "BRL"
  }'
```

- First call → `201 Created` (card inserted).
- Same `external_id` again → `200 OK` (card updated, no duplicate).
- `pipeline_id` without a stage of that pipeline (no `stage_id`, or a `stage_id`
  from another pipeline) → the card goes to the pipeline's entry stage (the
  first by position), on create and on upsert. On upsert the move goes through
  the stage automations, like `/move`; if the card is already in that pipeline,
  it stays in its stage. The card history says why, and the response carries
  the chosen `stage_id`. Only a pipeline with no stages at all returns `422`
  `crm.upsert_stage_of_pipeline_required`.

#### Move a card to another stage

```bash
curl -sS -X POST \
  "https://chat.example.com/api/v1/accounts/7/crm/cards/1234/move" \
  -H "api_access_token: $CRM_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 7b3e-move-1234-to-12" \
  -d '{ "stage_id": 12 }'
```

#### Close a card as won

```bash
curl -sS -X POST \
  "https://chat.example.com/api/v1/accounts/7/crm/cards/1234/close" \
  -H "api_access_token: $CRM_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 9a1d-close-1234-won" \
  -d '{
    "result": "won",
    "value_cents": 1200000,
    "currency": "BRL"
  }'
```

For a loss, send `"result": "lost"` with an optional `"lost_reason"`. To reopen,
send `"result": "reopen"`.

### 2.5 n8n HTTP Request node settings

| Field | Value |
| --- | --- |
| Method | `POST` |
| URL | `https://<host>/api/v1/accounts/<ACCOUNT_ID>/crm/cards` (or `/cards/{id}/move`, `/cards/{id}/close`) |
| Authentication | Header Auth credential (`api_access_token`) |
| Send Headers | add `Idempotency-Key` (an expression that is **stable across retries** of the same logical action, e.g. derived from the trigger's record id) |
| Send Body | JSON, as in the examples above |
| Options → Retry On Fail | On (the upsert / idempotency mechanisms make this safe) |

> Make the `Idempotency-Key` deterministic for a given logical action (e.g.
> `move-{{$json.cardId}}-{{$json.targetStage}}`). A random key per retry defeats
> the purpose.

### 2.6 Rate limiting

CRM token requests are rate-limited per token. On `429`, honor the `Retry-After`
response header (seconds) before retrying.

---

## Quick reference

| Direction | Transport | Auth | Dedup mechanism |
| --- | --- | --- | --- |
| CRM → n8n (trigger) | Outbound webhook (HMAC) | per-webhook secret | `X-Chatwoot-Event-Id` |
| n8n → CRM (action)  | REST `POST` | `api_access_token` header | `external_id` upsert / `Idempotency-Key` |
