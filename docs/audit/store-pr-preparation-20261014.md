# Store E1-E4: coordinated PR preparation

## Authorization and scope

On 2026-10-14 the user approved final review, integration with main, affected
validations, coordinated PRs/CI, and AWS/sandbox readiness verification.
Merge, deployment, production migrations and real payments remain unauthorized.
The store remains a SuperAdmin-only pilot at menu, router and API boundaries.

## Git integration and review

- Preserved the complete local E1-E4 work in commit `ed87c8b641` before merging.
- Integrated main `75c4705a2c` in commit `c7101401f8`, without rebase, force push
  or editing another checkout. Nine conflicting files were resolved.
- Kept main's typed HTTP arguments, escaping, request deadline, redirect limits
  and sanitized provider errors. Inherited HTTP tools only add beneficiary
  execution context for audit attribution.
- Preserved native-tool flow allowlists, scheduling support, activation/channel
  validation and the current agents form. Store inheritance and the commercial
  operating gate live in the store concern.
- Updated the fictitious native-tool test to declare its permitted flow; added
  a regression denying inherited platform-guide tools. No production allowlist
  was widened and no assertion was removed.
- Regenerated the schema from the existing isolated test DB after applying main
  migrations there. Relative to main, schema changes are only store tables,
  linked-agent columns, indexes and foreign keys.
- Regenerated the Guide map and action formats. The PR does not change workflows,
  deployment defaults, dependencies or lockfiles relative to main.

The preservation commit exposed local hook setup problems: missing Husky runtime,
then a missing scss-lint PATH and a denied default RuboCop cache directory. Husky
was initialized locally, scss-lint and ESLint were run successfully, and Ruby
checks used the existing isolated launcher. The merge commit did not run the
auto-fixing hook over thousands of imported main files; feature-scoped lint and
tests were run explicitly. No lint rule or CI gate was disabled.

## Local validation

| Check | Result |
| --- | --- |
| Selected final Rails store/agent regressions | 266 examples, zero failures on c7101401f8, sequential run |
| Concern/activation/native-tool regressions | 79 examples, zero failures after extraction |
| Ruby protocol contracts | 98 examples, zero failures |
| Vue/JS store and router | 52 tests in 10 files, zero failures |
| Store Ruby lint | 68 files, zero offenses |
| Extracted model/controller/concern lint | 3 files, zero offenses |
| Changed frontend ESLint | 37 files, zero errors; 89 existing localization warnings |
| Fork localization | 19 catalogs, 29,056 messages compiled |
| Guide map | 219 flows, 203 routes; no unexplained screen |
| Shared E2/E4 schemas and fixtures | Structurally equal between both repositories |
| Full production Vite build | Exit 0, 7,415 modules, 1m 18s |
| Generated manifest | 640 entries; zero missing files/imports |
| Asset compression | 583 inputs, 1,166 Brotli/Gzip variants round-trip verified |
| Integrated real local backends | 8 examples, zero failures on Chatwoot c7101401f8 / Financial 5a4651d |
| Financial native concurrency | 13/13 repeated by its owner; 10 lock waits and one SKIP LOCKED |

The first build used the old 4 GB heap and failed at the heap limit. Current main
already requires 6 GB in Docker and CI; repeating with that same bound passed.
No Vite/dependency configuration was changed to conceal the failure.

An extra regression run overlapped the integrated callback harness on the same
local database. Three assertions on global event/entitlement counts observed
the other run's temporary records. This is not counted as a passing run. Both
processes finished, the integrated scenario cleanup left those tables empty,
and the selected regression suite was repeated sequentially without changing
assertions. The sequential rerun passed: 266 examples, zero failures, 25.73 s
plus 4.35 s boot. Both event/entitlement tables were confirmed empty beforehand.

Guide action formats were regenerated again after the strong-params extraction;
the final `autonomia:guia:formatos:check` passed. The sole remaining core lint
offense is the nested module style of main's existing HttpExecutor; it was not
introduced or suppressed by the store patch. The store's new Ruby files and
the changed model/controller passed their scoped lint checks.

All test services are loopback-only. Identity, credentials and gateway behavior
are fictitious at the integration boundaries; Rails controllers, contracts,
PostgreSQL, signed callbacks and capacity state machines are real local code.
No real payment, production Rails, EC2 command or production database operation
was used. This is not browser/provider/production proof.

Ignored evidence is under `.codex/local-test/store-pr-*20261014*`. Older phase
audits remain historical checkpoints, not claims about the current remote CI.

## Publication and operational gates

Coordinated Financial PR: https://github.com/autonom-ia/autonomia-financial/pull/148.
Both PRs remain drafts until release gates are addressed; no merge queue or
automatic merge is requested. A merge to main starts the existing deploy
workflows and therefore requires a separate human authorization.

AWS read-only verification found all five store settings absent in both
Chatwoot installations. The Financial owner found no HML or store-worker
deployment in its scoped inventory. Real sandbox payment and public callback
verification cannot be claimed before isolated infrastructure is published.
Read `docs/store/aws-sandbox-readiness.md` and the Financial release review.

Financial also reports four high-severity runtime dependency advisories inherited
from its main. Those need separate reachability/repair review before production;
the store PRs do not automatically upgrade unrelated dependencies.

## Central help CI correction

The first remote CI run rejected the new `autonomia_financial_store` route
because it lacked a Central help article. Article 17.03 and its chapter map
entry now document the current labels, account activation, paid-period
cancellation and SuperAdmin-only pilot. No coverage waiver was added.
Local `pnpm central:check` passes: 195 articles and 203 covered screens.
Existing evidence warnings in older articles remain outside this change.
Remote CI must be checked again at the documentation correction's new head.
