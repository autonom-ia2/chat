# E3: contracted agents linked to a principal

## Boundaries

The local store remains SuperAdmin-only. No PR, push, manual deployment,
production access, or new Auth contract is included. Real gateway sandbox,
commissions and a complete dashboard Vite build remain deferred.

Financial owns commercial services, icon, offers, prices, billing and capacity.
Chatwoot owns the principal agent and its linked account instances. No global
template library or duplicated financial catalog is created.

## Checkout and activation

The browser continues sending only price, limits and a client intent. The BFF
resolves the canonical target in one bounded catalog lookup:
`GET /financial/internal/store/catalog?servicePlanPriceId=<uuid>&page=1&pageSize=1`.
The target is persisted on the first intent. Retry uses that same target even
if the publication subsequently changes. The Financial verifies the canonical
offer again under locks before persisting checkout.

Feature actor assertions retain the E2 featureKey shape and replay hashes.
Agent assertions use a discriminated agent target with installationId and
principalAgentId. Both preserve the return context and nonce/hash binding. Event
envelopes, HMAC, contractVersion and accessVersion streams are unchanged.

Activation uses the single allocation/none metric in the purchased plan,
quantity one and the beneficiary account resource. The subscription and reserve
belong to the buyer. The technical instance is unique per service, principal
and beneficiary account. A different service for the same principal is a
separate technical instance; another buyer of the same service reuses it.

Only a committed reservation and its correlated authoritative grant permit
creation/ready. Technical creation and the ready checkpoint share a database
transaction. Failed checkpoints roll back both; retries reuse the reservation.
If the principal or a deleted instance becomes unavailable after commit, the
runner compensates by releasing the slot rather than silently resurrecting it.

## Inheritance and account isolation

- The instance stores only a principal FK, commercial service FK, local company
  and complementary instruction. It never copies the principal prompt or KB.
- The prompt reads the current principal procedure/scaffold/guardrails/handoff
  and adds local identity/complements. Existing instruction writers cannot
  replace the inherited rules or detach the commercial link.
- Vector and lexical retrieval share a scope restricted to the local agent and
  that exact principal. Existing review and business-scope gates still apply.
  Source-less legacy entries remain eligible; SQL NOT IN must not accidentally
  exclude NULL source IDs when another source is rejected.
- HTTP tool definitions and encrypted headers remain on the principal record.
  Inherited execution stays server-side; telemetry identifies the beneficiary
  agent/account. Local same-slug definitions cannot override a principal tool,
  including a disabled one.
- Native functions retain availability checks and execute with the instance,
  beneficiary account, current delivery and operator. Owner-account authority
  is never inherited.
- Specialist functions are read-through bindings: definitions remain on the
  principal, while AI credentials, costs, tools and delivery use the beneficiary
  instance/account. No specialist rows are cloned.
- The API exposes inherited names/counts, never inherited prompts or headers.
  Local knowledge CRUD stays account-scoped. The store instance pilot is also
  gated in the agent API, not just the store menu.

## Suspension and deletion

The shared Answerer entry point denies unlicensed execution before retrieval or
provider calls. Operate uses the same agent operating predicate for replies and
asynchronous delivery. Projections synchronize mirror bots without deleting
instance content. Disabling one activation does not stop a different valid
buyer grant correlated to that instance. Expired/revoked grants fail closed.

Principal logical deletion suspends linked instances. The self-FK deliberately
restricts hard deletion rather than cascading into customer agents. Deleted
instances are not automatically resurrected by checkout/callback retries.

## Configuration

Meus serviços links a ready agent to the existing agent panel in its beneficiary
account. The contracted configuration edits name, company, complementary
instruction, greeting, fallback and tone. Inherited metadata is read-only.
Own knowledge and channel management reuse the existing account-scoped tabs.

No new environment variables are introduced by E3. It uses the scoped Financial
configuration and access-token/refresh store already implemented in E1/E2.
