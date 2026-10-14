# Store E4: local cancellation, reversal and collection concurrency

## Scope and result

Human authorized native local PostgreSQL concurrency tests with Financeiro -
Asaas on 2026-10-14, then explicitly approved the minimum correction after a
domain failure was reproduced. No PR, push, deployment, AWS, RDS, production
credentials, real gateway or production Rails operation was performed.

**Complete local gate: 13/13 native scenarios passed and were independently
repeated, with 1,127 Financial regressions passing.** Financial source commit:
`0663c94` (`fix: protect paid store periods during cancellation races`).
Chatwoot retains its uncommitted E1-E4 working tree based on `48bb7714`; no
Chatwoot application source was changed in this round.

## Ownership and fixture

- Financeiro - Asaas owned the Financial reproduction, minimum source fix,
  native tests, gateway fake, regressions and local source commit.
- Chatwoot AWS owned the fixture lifecycle, independent source review/test run,
  shared-contract checks, connection audit and final shutdown.
- PostgreSQL 17.11 on `127.0.0.1:55439`, new empty database
  `financial_store_e4_concurrency_20261014`, owner `store_e2_test`.
- Original databases `chatwoot_store_e2_test` and
  `financial_store_e2_integration` were not reset or changed by these tests.
- Resource limits verified: 12 connections, shared_buffers 32 MB, work_mem 2 MB.
- Domain calls used independent connections under `financial_api_runtime`,
  verified NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOBYPASSRLS. Ledger and cancellation
  receipts remained without UPDATE privilege.
- Gateway and customer/payment references were fictitious. All external gateway
  methods not used by the fake were rejected. No HTTP application server,
  container, Redis or Rails boot was needed for the native gate. A separate
  existing Financial regression test used its local JWKS server.

## Reproduced defect and minimum fix

A renewal invoice, payment and capture could be committed while its contract
still had the old period, before `finalizePaid`. Cancellation then accepted the
old cutoff and could truncate a period that had already been paid.

The fix in `src/store-cancellation-repository.ts` includes paid invoices whose
period ends after the current contract period in the existing scoped query.
Their presence yields the existing `payment_processing` eligibility block until
canonical finalization advances the contract. This is independent of the paid
invoice's starting boundary, covering a deliberately constructed overlapping
period too. Cancellation after finalization uses the new paid cutoff normally.

No new API, migration, financial policy, refund behavior or automatic capacity
release was introduced. Invoice reads retain their scope, transaction locking
and existing maximum row bound. Harness bootstrap errors and a TypeScript union
error in the new test were fixed separately, not claimed as domain failures.

## Native coverage

1. Aligned renewal captured before contract finalization: cancellation denied.
2. Overlapping paid extension: same denial without relying on future-start filter.
3. Cancellation holds invoice first: stale collector makes no new gateway call.
4. Collector reserves first: cancellation waits and then gets 409.
5. Two collectors: one renewal gateway write/payment/capture/next invoice;
   finalization replay leaves the full snapshot unchanged.
6. Competing versioned cancellation commands: one winner, one 409 and immutable
   replay receipt.
7. Resume owns root before cutoff finalizer: SKIP LOCKED, renewal preserved.
8. Cutoff finalizer wins before resume: waiter revalidates, 409; late finalization
   does not reactivate the ended contract.
9. Resume restores invoice before claim: collector reserves the restored version.
10. Paid finalization wins before cancellation: stale version denied; new request
    uses the full renewed paid period and cancels only the subsequent invoice.
11. Collector owns a canceled invoice first: claim denied; waiting resume safely
    restores the original invoice.
12. Cancellation wins before late settlement: unapplied money is recorded once,
    with no new capture or active period on replay.
13. Resume waits across cutoff: eligibility is checked after acquiring the lock,
    using a scenario-local clock, without changing the global clock.

The overlap is a controlled synthetic DB stimulus, not a claim that prorated
commercial offers were integrated in this round. Reversal means resuming renewal,
not refund or chargeback.

## Verification

| Check | Result |
| --- | --- |
| Financial native suite | 13 passed, 0 failed |
| Independent native repetition | 13 passed, 0 failed, exit 0, 2.04 s |
| Financial full regression | 1,127 passed, 0 failed, 252 skipped |
| Financial lint and build | Each independently repeated with exit 0 |
| Chatwoot lifecycle/checkout/event protocol | 19 examples, 0 failures |
| Shared E2/E4 schemas and fixtures | Semantically equal |
| Guard mutation | Both paid-window cases failed as expected; guard restored |
| Final read-only connection audit | No other client sessions; restrictions intact |
| PostgreSQL shutdown | exit 0, no server running; data/logs preserved |

The 252 skipped regressions comprise 239 existing opt-in cases and the 13 native
cases executed separately above. The initial regression attempt was blocked by
sandbox permission for a local JWKS listener, not a business failure; the allowed
rerun passed. No test was weakened to bypass that restriction.

Independent native execution proved ten PostgreSQL lock waits with
`pg_blocking_pids` and one SKIP LOCKED case. Runtime backend PIDs were 87360/87361;
the clock-crossing case also used observer/blocker 87359. Full snapshots compare
root versions, invoices, money, captures, reservation IDs/quantities, immutable
commands, outbox payloads and stream versions to detect hidden replay effects.

Source SHA256 before/after independent execution, reconfirmed after local commit:

- Cancellation repository:
  `04fd4a72a68659ac840e3f16ceb4447f9cc235943e2e436eddc654e47c6e87f5`.
- Native fixture:
  `8ccfa00002181c2cfd1a2202d9bac3c3db082aef0d55f84f102b0f8850423a58`.
- Native tests:
  `166c673600f592ea223a19ff4a925109845de3317ea9e30e2f677e29abed489b`.
- Wrapper:
  `7efbfac80fbc62c6843e5b08e3609ff5c0fce7b48fa4f56aba4733e36ef31636`.

E2 schema differs only in whitespace/definition order between the projects;
E4 schema and E2/E4 fixtures are also byte-equal. No schema normalization was
performed during this task.

## Reproduction and preserved evidence

From the Financial worktree, after the coordinator starts the guarded fixture:

```sh
npm run test:postgres:store-e4-concurrency
```

The checked-in wrapper clears the inherited environment, bounds workers and
uses a hardcoded, read-back-verified local fixture. It does not start/stop/reset
PostgreSQL or read production secrets. The shared cluster is stopped now.

Financial ignored evidence: `.codex/store-e4-concurrency/green.log`, `green.json`,
`independent.json`, `full-suite.log`, `full-suite.json`, `red-mutation.log` and
`red-mutation.json`.

Chatwoot ignored evidence under `.codex/local-test/`:

- `e4-concurrency-independent-20261014.log`.
- `e4-concurrency-contract-tests-20261014.log`.
- `e4-concurrency-financial-lint-20261014.log`.
- `e4-concurrency-financial-build-20261014.log`.
- `e4-concurrency-postgres-20261014.log` (including sandbox-denied initial start
  and confirmed successful startup/shutdown).

## Release limits

This closes the local concurrency validation gate, not real payment/gateway
homologation, browser integration, remote exact-head CI, AWS setup or deployment.
The prior complete local Vite build remains a separate recorded proof; this
round changed no frontend source. SuperAdmin pilot permissions are unchanged.
PR/push/deployment and any real-provider/production work still require separate
human authorization.
