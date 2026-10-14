# E3: linked contracted agents

Human approved E3 on 2026-10-13, including inherited tools. Reuse the local
E1/E2 branch and isolated test services. No PR, push, deploy or production access.
Full dashboard build was deferred at E3; it passed locally on 2026-10-13 after
separate human authorization (docs/audit/store-dashboard-build-local-20261013.md).
Real payment sandbox and commissions remain deferred.

## Contract and implementation

- [x] Extend checkout to the canonical published agent target with Financial;
  preserve legacy feature assertions, hashes and replay.
- [x] Persist principal/instance/activation links and regenerate schema locally.
  One instance per service/principal/account; separate grants per buyer.
- [x] Provision only after confirmed reservation/grant. Retry without duplicate
  instances; disable/revoke without deleting knowledge or other buyers' grants.
- [x] Compose principal rules and local identity/complements live; retrieve only
  local and explicitly linked principal knowledge with existing source gates.
- [x] Inherit HTTP tools server-side without exposing credentials; bind native
  tools to the beneficiary instance/account, not the principal owner account.
- [x] Configure instance identity/complements/knowledge in the existing agent
  panel. Inherited rules/tools are read-only. Keep the store SuperAdmin-only.
- [x] Focused local tests for provisioning/replay/grants, isolation, inheritance,
  tool execution context, API permissions and frontend. Document evidence.

## Safety

No new billing engine, template library or mirrored financial catalog. Redirect
is never permission. Deleted/unpublished system principals are not provisionable.
Principal deletion must not cascade into instances; runtime access is fail-closed.
Inherited HTTP credentials stay on the original tool record; native integrations
must resolve tenant credentials and cannot inherit owner-account authority.

## Verification checkpoint

2026-10-13: 131 focused Rails examples, 91 protocol examples, 36 Vue/JS tests and
5 integrated local scenarios passed. Financial integration code d52bffa, final
documentation head 9476bdc. No production, gateway sandbox or paid AI evaluation.
Inherited specialist functions also use read-through account-bound definitions.
Evidence: docs/audit/store-e3-local-20261013.md.
