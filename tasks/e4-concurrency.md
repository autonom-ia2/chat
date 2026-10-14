# E4: native PostgreSQL cancellation, reversal and collection concurrency

Human authorized this local-only gate on 2026-10-14, coordinated with
Financeiro - Asaas. No push, PR, deployment, production access or real gateway.

- [x] Confirm Financial ownership of tests and minimal fixes in
  `autonomia-financial-store-checkout`; preserve the Chatwoot E1-E4 working tree.
- [x] Start only the existing isolated PG17 fixture on loopback port 55439,
  with 12 connections, shared_buffers 32 MB and work_mem 2 MB.
- [x] Create a new empty round-owned database
  `financial_store_e4_concurrency_20261014`; preserve both previous test databases.
- [x] Agree the matrix with Financeiro - Asaas: cancellation/collection in both
  orders, canonical capture before finalization, paid-end resume/finalization,
  competing versioned commands, two collectors and settlement/finalize replay.
- [x] Verify actual overlapping backend sessions/locks, not merely sequential
  mocks or Promise.all. Reversal here means resume, not a new refund policy.
- [x] Run both relevant orderings of cancellation versus collection, reversal
  versus end-of-paid-period finalization, competing commands and payment replay.
- [x] Verify state/version/events, paid period, invoice/payment/capture uniqueness
  and capacity retention under the restricted application role.
- [x] If a real defect is found, retain a failing reproduction before a minimal
  fix and repeat native PostgreSQL tests plus focused and full regressions.
- [x] Review exact final Financial source and evidence independently; compare
  shared contracts and record remaining release gates.
- [x] Close all test-owned pools and stop only the PG fixture after the Financial
  owner confirms no pending operations; preserve data, logs and artifacts.

## Domain RED and correction authorization

Financial confirmed a native PG17 reproduction under `financial_api_runtime`:
after invoice/payment/capture of a renewal were committed but before
`finalizePaid` advanced the root, cancellation accepted the previous paid-period
cutoff. Initial harness bootstrap failures are not counted as this domain RED.
Human explicitly authorized the minimum correction and local revalidation on
2026-10-14. Financial owns that source change; no new API, migration or refund
policy is intended. All publication and production gates remain unchanged.

Chatwoot checks: 19 lifecycle/checkout/event protocol examples passed without
booting Rails or accessing a DB. Shared E2/E4 JSON schemas and fixtures match
semantically; E2 schema whitespace/key ordering differs, not its contract.

## Completed gate

Financial source commit `0663c94`: minimum paid-period guard and 13 native tests.
Independent repetition passed 13/13 with ten proven lock waits and one SKIP
LOCKED case; source hashes unchanged. Full Financial regression 1127 passed,
252 opt-in skipped, no failures. Independent lint/build exit 0. Observer audit
found zero other client sessions before successful fixture shutdown, preserving
all data. Evidence: docs/audit/store-e4-concurrency-local-20261014.md.
