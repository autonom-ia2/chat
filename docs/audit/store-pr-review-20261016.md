# Store PR review follow-up - 2026-10-16

## Scope and release gate

Follow-up to the orchestration comment on PR #1577. Updated the existing
`codex/store-checkout-activation` branch against main `5fd0efc86d00ce3f2613c341b7e7afd48f66cadc`.
No merge to main, deploy, production Rails, production database operation,
payment, AWS write or Financial code change is authorized or performed here.
The store remains SuperAdmin-only; no account feature flag was introduced.

Six migration versions were requested from orchestration in PR #1577 and
issue #1322, comments 6216862245 and 6216915620. Their current timestamps are
not a reservation. Renumbering awaits that response; do not release this PR
with this gate outstanding. Their dependency order is:

1. CreateAutonomiaStoreRuntime
2. LinkStoreAgentInstances
3. StoreCheckoutTargets
4. ScheduleStoreRecovery
5. CreateStoreSubscriptionCommands
6. RequestStoreCheckoutReconciliation

## Corrections

- Preserved main's helper-agent eligibility and per-turn budget while retaining
  inherited specialists and the contracted-agent access check in Answerer.
- Excluded only `autonomia/financial/store` from the executable/readable Guide
  catalog. Existing invoice/subscription reads remain unchanged. The existing
  test excluding checkout and subscription mutations is not relaxed.
- Corrected the soft-delete rollback spec's dependency boundary: reverse later
  store migrations and the inbox-role migration inside the test transaction,
  compare the complete schema before/after the target migration, then roll
  back the enclosing transaction. This preserves the full-string assertion
  without treating physical column order as a product regression or resetting
  preserved local fixtures. Preliminary runs exposed the expected order and
  PostgreSQL expression-deparsing differences; they are not passing evidence.
- Fixed the HTTP executor's compact namespace style. Sibling tool constants
  are fully qualified to preserve Ruby constant lookup; tool behavior and
  security protections are unchanged.
- Registered Store among the new sidebar's known Financial children. Added
  SuperAdmin test coverage; ordinary administrator menu expectations stay
  unchanged for both sidebar modes.
- Regenerated the Guide map, action formats and schema using local tooling.
  The schema diff against main is additive store fields/tables only.

## Validation

All Ruby integration uses the preserved loopback PostgreSQL 17 / Redis fixtures,
RAILS_ENV=test and a launcher that clears inherited environment and blocks
non-loopback HTTP. No production runtime was started.

| Gate | Result |
| --- | --- |
| Focused Guide / rollback / audit / HTTP tools / helpers / store agents | 67 examples, zero failures |
| Store API / jobs / callbacks / agents / Account regression | 324 examples, zero failures, one existing quarantined example |
| Financial protocol contracts | 98 examples, zero failures |
| Sidebar / settings cards / store frontend | 63 tests, zero failures across 10 files |
| Scoped Ruby lint | HTTP executor, route resolver and regression specs pass |
| Scoped JavaScript lint | Sidebar map and regression specs pass |
| Guide map and action formats | Generated and check passed |
| Central help | 197 articles, 205 screens; check passed |
| Fork localization | 20 catalogs, 30,926 messages compiled; check passed |
| Complete local Vite production build | 7,559 modules; 56.08 seconds; exit zero |

Build output was redirected to the ignored local directory, with the same
6 GB Node heap limit already configured by main. This does not publish an
image or verify browser/provider behavior in a deployed environment.

The membership-audit failure reported by the previous remote CI was not
reproduced in either the focused or expanded suite. Its model, audit concern
and assertions were not changed. Remote CI at the new head must still verify
suite-order behavior; this is not a claim that the historical failure was fixed.

Known inherited diagnostics: the full merge delta includes a trailing blank
with spaces in main's `docs/agentes-ia-redesign/tema14-subagente.md:71`; that
unrelated document is not reformatted. The store-only delta is checked instead.
Vue registration warnings and the dependency's missing ProseMirror source map
do not fail the frontend tests. No test was skipped to bypass these findings.

Ignored local evidence: `.codex/local-test/store-pr-20261016-*`.
