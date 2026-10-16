# Store E1 local implementation audit

- Date: 2026-10-09.
- Scope authorized by the user: E1 local implementation; SuperAdmin-only pilot;
  no Chatwoot PR until the end of the flow.
- Branch: `codex/store-catalog-publication`.
- E0 parent: `48bb7714d081c29577693140baeb3dfaefa45590`.
- Boundaries: no production Rails, AWS, RDS, secrets, data changes or deployment.
- Financial is the commercial source of truth. No Chatwoot migration or local
  catalog mirror is introduced.
- API gates are applied before Identity/Financial calls. Server-derived targets
  and independently verified Cognito subject prevent signing browser-provided
  principal IDs or using the internal Auth UUID as an OAuth subject.
- Protocol and frontend tests use fake credentials/data and no external backend.
- Local preview uses the same Vue components with a closed mock transport, not
  real customers, checkout or entitlements.
- Audit messages for successful mutations identify the local actor, selected
  account, action and server-derived principal/feature; Rails logger timestamps
  provide when. Sensitive upstream payloads are not logged.
- Remaining gates: Rails request specs under Ruby 3.4.4; integrated homologation
  with the scoped Financial caller and commercial editor; user review of E1;
  later approved PR/workflow release.

See `docs/store/e1-catalog-publication.md` for endpoints and configuration.
