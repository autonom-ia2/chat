# Store E4 local checkpoint - 2026-10-13

Scope: Chatwoot E4 on `codex/store-checkout-activation`, preserving uncommitted
E1/E2/E3. Cross-system local homologation passed against Financial `cf9e21b`
and the Chatwoot working tree based on `48bb7714`. Implementation and release gates:
`docs/store/e4-lifecycle-recovery.md`.

## Local evidence

- Additive migrations `20261013170000_schedule_store_recovery`,
  `20261013171000_create_store_subscription_commands`, and
  `20261013172000_request_store_checkout_reconciliation` applied only to
  `chatwoot_store_e2_test` on loopback PostgreSQL 55439. Schema regenerated at
  version `2026_10_13_172000`; no unrelated schema changes found.
- Current E4 focused suite: 132 Rails examples passed. Another 56 agent/catalog
  regression examples and two scheduler configuration examples passed (190
  Rails examples in distinct focused files). Covers bounded scheduling, lost enqueue, leases,
  buyer/account/namespace authority, readonly checkout recovery, terminal/stale
  correlation, activation commit/release expiry races, preserved agent instances,
  monotonic suspension/renewal, paid-period commands, explicit reconciliation,
  and confirmed cancellation as a prerequisite to a new purchase.
- On resumption, six new ownership tests reproduced a real local bug: status,
  resolve and reconcile through another account/subject of the same local user
  reached generic error handling, changing an expired intent to reconciling.
  The shared checkout lookup now scopes account and verified buyer before
  assigning the record. All six tests pass with 404, no Financial call/job and
  no state mutation. Proof: `.codex/local-test/e4-ownership-red.log` followed by
  the current 132-example suite. No Auth or commercial permission rule changed.
- 98 protocol examples passed; E2/E3 contracts preserved. E2 structural equality
  checked independently of JSON key order. E4 source/fixture are byte-identical
  to Financial, with SHA256 respectively:
  `246804fbbb13be45abd0a996c4f040b1860e8f2b83394735b028d889fd2e45bf`
  and `ac74139889c49587f000e9f83749a32b64eeaf67b8901c01591cd43269f2060a`.
- 33 Vue/JS tests in seven files passed, one worker. Owned-service, paid-period
  renewal popup, explicit reconciliation and browser intent retention covered.
- Actual renewal popup checked with isolated fake API in IAB at desktop and
  390x844 mobile: no horizontal overflow, async confirmation, focus retained
  after result, Tab, Escape and opener focus return. No console errors/warnings.
  Mock is not Financial integrated evidence. Preview closed, viewport restored.
  Captures: `.codex/local-test/store-e4-renewal-desktop.jpg` and
  `.codex/local-test/store-e4-renewal-mobile.jpg`.
- RuboCop focused production/spec/migration files passed; ESLint changed store
  controls passed. Initial spy setup, formatting and a misplaced template span
  were corrected before final tests; no guard or quality rule weakened.
- Fork i18n: 15 catalogs, 21478 messages compiled; en/pt_BR parameters matched.
- Guide build/check: 201 flows, 191 routes; action formats regenerated and checked
  in the isolated local Rails environment, 570 actions.
- Existing Ruby enum/Rack deprecations, Browserslist notice and Vue test-plugin
  duplicate-registration warnings remain; no new runtime error accepted.

Commands used the allowlisted `.codex/local-test/run.mjs` launcher for all Ruby
test/migration tasks. WebMock denied external traffic; PostgreSQL and Redis were
fictitious loopback services with bounded memory and existing local history.
Focused outputs: `.codex/local-test/e4-combined-tests.log`,
`.codex/local-test/e4-agent-regressions.log` and
`.codex/local-test/e4-protocol-tests.log`.

## Coordination and limits

Financeiro - Asaas implemented temporal versions, paid-period cancellation,
canonical reconciliation and canonical capture recorder composition locally.
The human chose access until the end of the paid period. Neither cancellation
nor reversal purchases again or releases occupied capacity. Financial migration
060/061/062 is restricted to its existing local PG17 fixture, not production.
The peer repaired constructor/rollback expectations and verified the earlier
timing/sandbox failures without weakening assertions or timeouts. It also proved
that removing canonical capture or lease fencing causes regression failures.

## Integrated evidence

The ignored local `gate2_spec.rb` ran eight cases against real handlers on both
sides, real PostgreSQL 17 and signed callback ingestion. Final result on Financial
`cf9e21b`: **8 examples, 0 failures**, 7.32 seconds plus 2.15 seconds boot.
The former five E2/E3 cases were rerun, not relabeled from historical evidence.

1. Paid invoice/payment/capture, explicit beneficiary grant, limit enforcement,
   capacity release and reuse without granting another account.
2. Trial setup, no invented payment/ledger and beneficiary-scoped activation.
3. Declined payment/cancel return does not grant access.
4. Lost provider response retains the checkout intent without another purchase.
5. Linked agent inherits principal instruction, preserves local knowledge and
   complements across disable/reallocation, and respects capacity.
6. Payment confirmed only at the fake provider, no delivered gateway webhook:
   explicit reconciliation uses the original checkout, records one payment/capture;
   authentic late webhook does not duplicate either. Payment alone does not activate.
7. Paid-period cancellation/reversal preserves paid access, occupied capacity,
   monetary history and original command identity; reversal advances version.
8. Canonical paid-end finalization emits a newer signed ended snapshot. Chatwoot
   blocks agent runtime but retains its identity, principal link, knowledge and
   complementary instruction, with no new charge or automatic capacity release.

Two native-driver differences were found and fixed in Financial, not hidden by
changing expected Chatwoot outcomes:

- `invoice_snapshots` JS array became a PostgreSQL array parameter instead of JSONB
  (`22P02`). Explicit JSON encoding fixed the insert; real node-pg encoder regression
  failed before and passed after. Initial run: 6/8; repaired focused run: 2/2.
- A new reconciliation defaulted its deadline to PostgreSQL microseconds but
  compared it with JS milliseconds. One run remained pending with zero attempts,
  no error and no lease. Persisting the initial deadline with the repository clock
  fixes the first claim; replays retain existing backoff. Deterministic injected-clock
  regression passed without sleeps/polling. Repaired focused run: 1/1.

Logs: `.codex/local-test/e4-integrated-tests.log` (final),
`e4-integrated-first-failure.log`, `e4-integrated-repaired-tests.log`,
`e4-integrated-pending-first-attempt.log`, and
`e4-integrated-clock-repaired-tests.log` under the same ignored directory.
Financial owner confirmed final `cf9e21b` full suite: **1127 passed**, 239
preexisting optional integration skips, zero failures (110 files passed/16 skipped),
86.66 seconds; lint/build and six native PG capacity cases green. Local commits
`129de29` and `cf9e21b` hold the JSONB and initial deadline corrections respectively.

## Cleanup

Financial owner closed API/JWKS and DB pools and confirmed no remaining native PG
operations. Chatwoot callback/proxies/test processes and private Redis6397 closed.
Only the isolated PostgreSQL data directory was stopped, not deleted. All ports
55439/6397/3008/3010/3009/3011/5191/5192 were checked after shutdown. Existing user
services and preview5186 were not touched. Shared fictitious Financial history,
certificates and private configuration were preserved; no production credentials
were read or rotated for this work.

## Publication gates

No exact-head CI, PR/push/deploy, AWS, production data, real gateway, paid AI,
commissions or full dashboard Vite build. Auth and production permissions unchanged.
The SuperAdmin pilot gate remains in menu, router, controllers and agent panel.
Local code/homologation is not production or real-payment proof.
