# Original files attached to agents

Date: 2026-11-18
Branch: codex/agent-source-downloads
Base: d87cc8d933885e2d929ada0606a161a03bc1e114

## Approved scope

Open or download existing original knowledge documents from the agent's
What it knows drawer. No changes to instructions, ingestion, customer knowledge,
commercial behavior, production data or infrastructure. No migration or new env.
Delivery through a separate PR; no merge or manual deploy authorized.

## Access and storage

- Reuse the authenticated account API and autonomia_view permission.
  Existing custom-role semantics, including manage implying view, remain intact.
- Resolve a kept, non-system agent inside the current account, then its own
  source, excluding material attached to posts.
- Generate a one-minute ActiveStorage service URL only on an explicit click.
  Return private/no-store; never add signed URLs to source lists, Vuex or logs.
- One existence check for the selected storage object; no file download,
  read or byte proxy in the application process. Production S3 serves the file.
- Preview PDF and safe raster image types; other types use attachment disposition.
- Keep the operation out of the Guide tool catalog using the existing
  only-on-screen mechanism. The Guide can explain the UI, not issue private links.
- Reuse the existing synchronous-tab-opening pattern from the insurance module
  through a shared helper, including its popup-blocked same-tab behavior.

## Local validation

- Vitest: 41 files, 1,280 passing tests, including original-file interaction,
  missing attachment, failed ingestion, read-only view, unavailable storage,
  API error, double-click prevention and the existing insurance module.
- Scoped ESLint: zero errors. Existing AGENTS catalog-resolution warnings remain;
  actual EN/PT-BR keys are present and checked by the fork translation gate.
- Browser: actual drawer/row components with synthetic sources and mocked API,
  at 1280px and 390px. No horizontal page overflow; action targets stay 44x44px.
  Confirmed opening a new tab, missing-object error, no action on websites or
  attachment-less sources, and Escape closing the drawer. No production requests.
- Screenshots retained outside git in this task's local visualization directory.
- Guide map generated from porques.md; map check reports 278 flows, 233 screens,
  and no unexplained screens.
- Ruby 3.4.4 is not installed locally (only macOS Ruby 2.6). Full request/service
  and Enterprise permission examples must run in the repository CI; local JS
  results are not evidence of Rails integration passing.

## CI and release

Pending CI verification on the PR. No merge, deployment, production Rails,
paid AI test, or direct production access performed for this implementation.
