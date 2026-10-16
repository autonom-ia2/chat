# E3 local implementation and integrated verification

Date: 2026-10-13. Branch: codex/store-checkout-activation.
Chatwoot implementation remains uncommitted alongside the preserved E1/E2 work.
No PR, push, merge, workflow dispatch, manual deploy, AWS or production access.

## Approved delivery

Linked agent instances with live principal instruction, knowledge and tools;
local identity/complements/knowledge; activation only after correlated capacity
grant; safe disabling with data preservation and multiple buyer grants.
Store and contracted configuration remain SuperAdmin-only during validation.
Financial owns presentation/icon/prices and existing subscription/capacity.
No Auth changes or new E3 environment variables.

## Code and schema

Two additive Chatwoot migrations applied only to isolated local PostgreSQL 17.
db/schema.rb regenerated at 20261013161000. Principal FK deliberately restricts
hard deletion; customer instances do not cascade from principal deletion.

Agent target is persisted from a bounded official catalog price lookup, never
browser input. Shared JSON contract is structurally equivalent to Financial's
E3 schema; object formatting/order differs only. Feature actor assertions,
existing replay hashes and event envelopes remain compatible.

Shared Answerer and operating gate deny unlicensed calls before retrieval/AI.
Retriever combines only local and explicitly linked principal scopes. Native
and specialist execution use beneficiary credentials/account/cost attribution;
HTTP credentials remain on principal tools and are not exposed/copied. Request
diagnostics now explicitly filter complementary instructions, prompt fields
and header configuration.

## Verification

- Focused Rails: **131 examples, 0 failures**. Includes E2, activation compensation,
  principal/local KB isolation, native/HTTP/specialist binding, API permissions,
  private field filtering and ordinary-agent runtime regressions.
- Ruby protocol: **91 examples, 0 failures**. Includes both assertion shapes and
  body/return context correlation with unchanged feature paths.
- Vue/JS: **36 tests, 7 files passed**, single worker. Contracted settings save only
  local fields; labels, textarea bound, busy/empty state and tenant switch pass.
- Integrated local: **5 examples, 0 failures**, real Chatwoot/Financial handlers,
  local PostgreSQL and HTTPS callbacks. Identity/JWKS, secret store and gateway
  are fake at the boundaries; no real gateway/provider or paid AI calls.
- Financial peer: **77 focused production tests/9 files** and **8 local harness
  tests**, reported passed. E3 code heads e3bf071/783635a/d52bffa; final documentation
  head **9476bdc**, independently verified clean. No general Financial suite claim.
- RuboCop focused code: **28 files, no offenses**; additional controllers,
  serializer and privacy check: **5 files, no offenses**.
- ESLint new E3 controls: no errors/new warnings; existing AgentPanel dynamic
  i18n warnings remain outside the new component.
- Fork catalogs: **15 catalogs, 21438 messages** compiled and en/pt_BR matched.
- Guide generated fields refreshed locally; map current: **201 flows/191 screens**.
- Diff whitespace check passed.

## Integrated flow observed

The four E2 cases passed again: canonical paid, trial setup, signed failed
payment/cancel return and lost-provider-response recovery without duplication.

E3 paid checkout used the official published agent target. Signed payment
produced one payment and one ledger event; HMAC callback completed the intent.
Reserve/commit/authoritative grant created exactly the beneficiary-linked agent.
A second account hit the one-account limit with no extra instance. Disabling
released occupation and retained local knowledge/complements. Reusing capacity
on another eligible account created its separate instance without leaking the
first account's knowledge. Both reservations were released at the end.

The first combined run completed its business assertions but failed in fixture
cleanup: the harness destroyed an account before its own agent knowledge. The
cleanup order was corrected, exact confirmed disposable local IDs were removed
with database/relationship guards, and the whole five-case run passed afterward.
No production repair or general account-deletion change was made.

## Frontend inspection

Actual contracted settings component was mounted in an isolated mock-only Vite
harness, not the whole application. Desktop and 390x844 mobile showed no
horizontal overflow. Labels, keyboard combobox selection and simulated save
worked; browser error console empty. Own fake state only; no backend save or
production data. Screenshots under .codex/local-test/store-e3-desktop.png and
store-e3-mobile.png. The approved earlier prototype was not changed.

## Remaining gates

No exact-head CI/PR, production migrations, deployment, live user/WhatsApp proof,
real payment sandbox, complete dashboard Vite build or service commissions.
These remain distinct from this completed local E3 evidence. Production native
tools still require the beneficiary integration configuration and its normal
availability/authorization gates; seller authority is never used as a fallback.

Local listeners and database processes are closed after final verification;
the fake Financial commercial history and local test database files are retained.
Final listener check found none on 3008/3009/3010/3011/5191/5192/5193/55439/6397.
