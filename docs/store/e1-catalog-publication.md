# E1: catalog and service publication

## Scope and delivery gate

Local branch: `codex/store-catalog-publication`, built on the E0 store contracts.
No Chatwoot push, PR, merge, deployment, production data change or production
Rails process is authorized by this delivery. Send the PR only at the end of the
approved flow. The Financial team owns its separately authorized release.

This is a SuperAdmin-only pilot. Ordinary account administrators must not see
the store menu, use its direct route, or invoke its account-scoped API. Existing
Subscription and Invoices remain governed by their existing administrator rules.
SuperAdmin access still requires membership in the selected account.

## User-facing flow

- Financial > Store loads the real Financial catalog, grouped into features and
  agents, with server pagination. Details show eligible plans, prices and limits.
- Agent > Service in store allows creation of an inactive Financial service draft
  associated with that principal agent. Deleted and system agents are excluded.
- Feature services uses the backend's closed registry: `prospecting`,
  `email_campaigns`, `whatsapp_api_campaigns`.
- The commercial editor in Financial owns price, plans, product association and
  service icon/logo. Chatwoot displays `service.logoUrl`, with a local icon fallback
  for a missing or broken image. There is no mirrored catalog database.
- After commercial setup, the operator selects a linked service and publishes it
  with its display order. Incomplete eligibility yields a sanitized conflict;
  the UI does not optimistically mark the service published.

Draft creation and publication never buy a service, change entitlements, enable
features, occupy capacity, or create a customer agent instance. These are later
deliveries. No checkout button is presented as working in E1.

## Identity and transport

All Financial calls send the existing OAuth access token from TokenStore plus
an installation/product-scoped API key and a short-lived actor assertion.
Identity `/me` validates the bearer and supplies `user.cognitoSub`. Its internal
UUID (`user.id`), email and local Chatwoot ID are not substitutes for this subject.
No change to Auth `/me/context` or the SSO callback is required.

The backend enforces the local SuperAdmin check before retrieving tokens or
contacting Financial. The browser cannot supply role, operator, namespace or
principal target. Principal agents are selected from the current account; feature
targets come from the closed registry. Financial validates its caller namespace
and feature allowlist independently.

Each outgoing request has a fresh HS256 actor assertion with audience
`financial-internal-store`, 120-second TTL, unique nonce, method, exact path and
SHA256 of the actual request bytes. Service queries also bind the agent or feature
filter in the claims. The assertion signing secret is distinct from the API key.

Financial routes consumed:

- `GET /financial/internal/store/catalog?page=1&pageSize=20`
- `GET /financial/internal/store/services?principalAgentId=<id>` or `featureKey=<key>`
- `POST /financial/internal/store/services`
- `GET|PUT /financial/internal/store/publications/<serviceId>`

Publication replies must match the requested namespace, target and service ID.
Draft retries preserve their idempotency key; assertions are never reused.
Automatic HTTP retries are disabled. Mutation timeouts/invalid replies have an
unknown outcome, not an assumed failure or success. Subsequent reads recover
the authoritative publication state. Error messages and logs omit bearer tokens,
API keys, assertions, upstream bodies and raw provider messages.

## Configuration for later homologation

Empty `.env.example` placeholders only, no credentials committed:

```text
FINANCIAL_STORE_API_KEY
FINANCIAL_STORE_ACTOR_ASSERTION_SECRET
FINANCIAL_STORE_INSTALLATION_ID
FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID
AUTONOMIA_FINANCIAL_API_BASE_URL
AUTONOMIA_AUTH_USER_ENDPOINT # optional explicit HTTPS /me override
```

Use separate scoped callers/namespaces for Autonomia and Hub2You. Missing or
invalid configuration fails closed. Creating callers, secrets, Financial migration
and SDK commercial-editor support are deployment prerequisites, not performed
by this Chatwoot implementation. Financial backend contract: PR 147, head acb7956.

## Verification

Protocol tests run without Rails: 76 passing (E0 + E1), using WebMock only.
Frontend tests: 20 passing, including gate, lifecycle, draft intent retry,
commercial conflict, confirmed unpublication and order bounds.
Full Vite production build passed locally, as did ESLint on changed frontend
files, fork i18n checks and operator-guide generation/check. Existing bundle
size/Browserslist warnings are not changed by this delivery.
Rails request specs are added for role/account/target gates and expired sessions.
They still require the project's Ruby 3.4.4, bundled dependencies and local test
Postgres/Redis; this Mac currently provides system Ruby 2.6, so they are not
claimed as executed. No production Rails command is used as a substitute.

Local preview uses actual E1 components and an explicitly closed in-memory
transport with demonstrative data: `http://127.0.0.1:5190/app/accounts/17/financial/store`.
Its CSP blocks production API calls. Start with
`pnpm exec vite --config docs/store/preview/vite.config.mjs`.
Preview validation is not integrated Financial/Auth or production proof.
