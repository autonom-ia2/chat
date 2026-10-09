# Email epic 436 — isolated browser UI QA

From the repository root, using existing dependencies and cached Chromium:

```sh
node tests/qa/email-campaigns/run.mjs
```

No install, Rails, database, production service or external API is needed. A full dashboard CSS build must already exist under `public/vite-test/assets/dashboard-*.css`; the most recently modified matching file is selected. The runner creates one Vite server at **127.0.0.1:3437** (strict port), launches a fresh headless Chromium context for each scenario, intercepts API requests with synthetic fixtures, and blocks requests outside that exact local origin. The server PID and selected CSS are recorded in `tmp/email436/visual/server.json` before binding. Normal completion/failure closes this runner's browser and server. A launch/bind failure is reported without changing security settings or trying another port.

The entry mounts the real `CrmCampaignManagementPage.vue` and all of its children, with real Vue Router, Vuex, Pinia, vue-i18n and Axios. Store data is limited to feature flags and an empty inbox list. Locale messages are loaded from the actual complete index for the selected locale with `fallbackLocale: false`. No rendered component is mocked. Before binding, the runner generates current utilities using the repository’s installed PostCSS/Tailwind and production `tailwind.config.js`, supplementing the existing dashboard bundle. There are no handcrafted substitute styles. This prevents a stale bundle from silently omitting newly used utilities. Both stylesheet paths are recorded in `server.json` and checked in the browser. The scope is the real management page, **without the navigation/sidebar shell**. This isolates frontend rendering and interactions; it is **not backend E2E**.

Planned browser coverage: PT-BR desktop interactions and errors; dark theme; Arabic RTL; mobile 390×844 and keyboard access; German and English; unknown, provider-blocked and unfresh protection states. Fixtures contain three campaigns and 120 recipients, including long text and different bounce classes. Five rows per page deliberately exercise pagination independently of full-filter CSV export. The stub combines q/status/problem and preserves campaign options independently of selected report data.

Artifacts under `tmp/email436/visual/`:

- `results.json`: actual check outcomes, fatal errors, screenshots, console/page errors, missing translations, computed dimensions/colors, captured API queries and synthetic responses.
- `*-whole-01-y<scrollTop>-x<tableScrollLeft>.png` and numbered successors: sequential positions of the real page scroll container, with 64 px overlap. The physical viewport is unchanged; mobile stays 390×844.
- `*-protection-*`, `*-recipients-*`, `*-table-left-*`, `*-table-right-*`, `*-focus-*`: viewport-clipped panel segments, both horizontal table extremes, and real keyboard focus. Capture records contain coordinates, viewport, focus, active-request count and file byte size. No offscreen element screenshots or enlarged viewport substitutes.
- `current-utilities.css`: generated production Tailwind utilities, not a fabricated rendering.
- Screenshot counts come only from files successfully written in this run. Older PNGs may remain; use the current `results.json` manifest, not a directory count.
- `*-dom.txt`, `*-aria.yml`: rendered text and accessibility snapshots.
- `filtered-recipients.csv`: actual browser download when the export scenario runs.

Exit code is nonzero for failed assertions or fatal setup/runtime errors. A `BLOCKED` result with no checks is never a PASS. Preserve console failures from deliberate HTTP 500/503 injections separately from unhandled runtime failures and blocked external requests when interpreting the report. Screenshots need visual inspection; automated layout checks do not establish professional visual quality.

## Execution status, 2026-09-16

First run was blocked at bind with `listen EPERM: operation not permitted 127.0.0.1:3437`. Chromium and UI assertions were not reached. No screenshots exist from that run. Syntax and five fixture-only checks passed separately. See `docs/audit/436-visual.md`. A later parent run did execute Chromium: **87 PASS / 5 FAIL / 34 actual screenshots**, reviewed in `tmp/email436/visual-independent-review.md`. The UI/harness corrections following that review have **not** yet been run in Chromium. Rerun them in the parent's already-authorized environment with loopback binding available. No security setting changes are part of this harness.


## Checks added after actual visual review

- Wait for completed fetch/XHR, font readiness and stable DOM geometry before captures; reject empty targets and active requests during screenshots.
- Require mobile email cells ≥180 px, closed rows ≤160 px, internal horizontal overflow and document width ≤391 px. Full long and international names remain available in opened details.
- Check `bdi[dir="ltr"]` direction and `unicode-bidi: isolate` for every visible table address and each opened detail. Localized status cells and summary labels stay RTL.
- Count all exposed enabled buttons, including offscreen actions. Closed details, hidden ancestors, inert and genuinely hidden styles are excluded. Negative-tabindex exposed actions fail, and zero-size actions remain eligible for dimension/focus failure. Require 100% coverage; traverse and open each summary with Tab/Enter, reach its copy button, activate it and verify the exact clipboard value and localized confirmation.
- Preserve error responses, combined filters, pagination, full CSV export, import issues and resume capability scenarios. The new manual/provider scenario retains `resume: true` with a provider block to test precedence. Only a synthetic name was extended for international text coverage; business fixture rules are unchanged.
- Missing translations remain failures, with `fallbackLocale: false`, including labels rendered during interactions. No locale checker/index/JSON belongs to this change.

Offline checks (no server/browser):

```sh
node --test tests/qa/email-campaigns/browser-helpers.test.mjs tests/qa/email-campaigns/fixtures.test.mjs
node --check tests/qa/email-campaigns/run.mjs
node --check tests/qa/email-campaigns/server.mjs
node --check tests/qa/email-campaigns/fixtures.mjs
```

The DOM helper test uses jsdom and controlled rectangles. It verifies expectation selection, **not rendered geometry or real keyboard behavior**. Actual browser checks and visual acceptance belong to the parent rerun.
