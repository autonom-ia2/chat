# E4: recovery and lifecycle

## Implemented locally in Chatwoot

The existing Sidekiq scheduler invokes `RecoverySweepJob` every five minutes.
Only the configured installation/product namespace is selected. Each sweep
claims at most 20 activations, 20 checkout intents, 20 subscription commands
and 20 inbox events. Claims
advance `next_recovery_at` atomically before enqueue; a lost enqueue is due again
after its interval. An active activation lease is never stolen. Queues reuse the
existing workers; no extra Rails process is started per operation.

Pending work is revisited after five minutes. Ready activation projections are
revisited after fifteen minutes. These are eligibility intervals, not a delivery
SLA: queue backlog, unavailable credentials and upstream outages can delay work.
Callbacks remain the primary update path. The four partial recovery indexes
and timestamps are additive; schema was regenerated using only the local test DB.

Default checkout recovery resolves the saved intent or reads its known session.
Only an explicit Verify payment action persists `reconciliation_requested` and
asks Financial to reconcile that existing session with a stable idempotency key.
Financial owns canonical capture/payment confirmation; Chatwoot does not grant
access from the reconciliation receipt and rereads checkout state after completion.
Recovery never calls checkout creation, hosted start, payment or purchase. Responses pass
the existing buyer/namespace/intent/price checks. Local identifiers and terminal
states cannot be replaced by a stale result. The original buyer must still be a
SuperAdmin and administer the active beneficiary account. Missing refreshable
OAuth authority pauses recovery; it never switches to a broader machine identity.

Activation recovery retains the original reservation/commit/release keys. Before
commit or release it reads the known reservation. Already committed or released
operations are recognized without repeating the mutation. An expired reservation
becomes `failed/RESERVATION_EXPIRED`, or completes a pending disable locally.
A conflict racing the read is resolved by reading that same reservation again.
Only an explicit Enable with a new client intent can restart an expired activation,
after the existing Financial subscription/beneficiary checks. This does not buy
the service again. The UI explains expiry and does not offer an invalid resume.

Ready projections continue to require a matching subscription/reservation grant,
a strictly increasing version and a future `effectiveUntil`. Expiry blocks runtime
locally without waiting for Financial. Mirrored bots are synchronized before a
ready refresh, even if the remote call subsequently fails. Versioned suspension
and renewal preserve the same linked instance, local knowledge and complements.
Other buyers' grants and manual feature configuration remain independent.

## Paid-period cancellation

Meus serviços exposes Gerenciar renovação only inside the SuperAdmin pilot.
Cancellation is owned by the buyer's service contract, not the current account.
It affects all accounts enabled under that contract. The human selected
`at_period_end`: scheduling stops renewal but retains access until the confirmed
paid boundary. It does not release occupied capacity or delete linked agent data.
Resume is offered only when Financial confirms it is still eligible. Trial policy
is not invented: unsupported trial/unconfirmed periods remain blocked explicitly.

Commands are saved before enqueue with an immutable expected version and key.
One unresolved command can occupy each owner contract. Unknown outcomes are
retried using that exact command; the browser never silently rebases its version.
The worker uses a fenced lease and refreshable buyer OAuth, not machine authority.

Expired/failed checkout intent is cleared for a new purchase only when the
readonly canonical service root confirms cancellation. A new explicit plan
selection is still required; timeout/expiry alone never creates another purchase.

## Contract alignment with Financeiro - Asaas

The separate E4 schema and fixture are byte-identical across repositories:
`config/autonomia_store/lifecycle.v1.json` mirrors `contracts/store-e4.v1.json`.
E2/E3 interfaces remain unchanged. E4 defines cancellation capability/commands,
explicit checkout reconciliation, signed actor actions and strict owner/namespace
checks. GET reservation may persist the expiration
of the original reservation; it is not a new allocation. `RESERVATION_EXPIRED`
is a Chatwoot code, not a new Financial response code.

Financial implemented temporal snapshot materialization, paid-period commands
and canonical reconciliation locally. The final combined eight-case run passed
against Financial code `cf9e21b` and the preserved Chatwoot working tree. It used
real PostgreSQL 17, real handlers and signed local callbacks; only provider and
identity boundaries were fictitious. Chatwoot never weakens monotonic snapshot
checks. Evidence and remaining publication gates are in
`docs/audit/store-e4-local-20261013.md`.

## Gates

Pilot access remains SuperAdmin-only. No Auth changes, new production secret,
PR, push, deploy, AWS access or production Rails/SQL. Full dashboard build, real
gateway sandbox and commissions remain deferred. Local integrated homologation
does not prove production configuration, actual gateway behavior or exact-head CI.
