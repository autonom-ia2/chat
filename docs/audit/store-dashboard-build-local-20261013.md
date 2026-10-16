# Store: full local dashboard build (2026-10-13)

## Scope and outcome

Human authorized the full local dashboard build only: no push, PR or deploy.
The existing `codex/store-checkout-activation` working tree was used, including
uncommitted E1/E2/E3/E4, based on `48bb7714d081c29577693140baeb3dfaefa45590`.
No application source, dependency, lockfile or production setting was changed.

The complete Vite production build passed with **exit code 0**, transforming
**6,909 modules** in **1m 13s**. All ten entrypoints discovered by the existing
configuration were compiled; this was not the isolated store-preview build.
Runtime: Node `v24.1.0`, pnpm `10.2.0`, Vite `6.4.2`.

## Reproduction

From the worktree root:

```sh
env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
  NODE_OPTIONS=--max-old-space-size=4096 RAILS_ENV=production \
  VITE_RUBY_PUBLIC_DIR=.codex/local-test/dashboard-full-build-20261013 \
  VITE_RUBY_PUBLIC_OUTPUT_DIR=vite \
  pnpm exec vite build --mode production

env -i HOME="$HOME" PATH="$PATH" NODE_OPTIONS=--max-old-space-size=4096 \
  node scripts/compress-vite-assets.mjs \
  .codex/local-test/dashboard-full-build-20261013/vite/assets
```

The public directory override changes only the local artifact destination, not
the checked-in Vite configuration. The asset base remains `/vite/`. Environment
inheritance was cleared except for local runtime paths and explicit build flags.
No Rails process, container, DB, Redis, application server, AWS operation or
Financial/provider request was started by this validation.

The first attempt compiled successfully in 1m 21s, but the optional macOS
`/usr/bin/time -l` wrapper returned 1 when sandbox restrictions denied its
`sysctl kern.clockrate` measurement. An attempted `nice` priority adjustment was
also denied. The confirmed second run omitted both wrappers and exited 0.

## Artifact checks

- Manifest: 595 entries; all referenced output files and static/dynamic imports
  exist, with no unresolved manifest references.
- Traversing static and dynamic imports from `entrypoints/dashboard.js` reaches
  396 manifest entries, including `StoreCatalogPage.vue` and `AgentPanelPage.vue`.
  Both remain dynamic entrypoints.
- Generated sourcemaps confirm the store includes checkout return, activation,
  owned services and renewal components; the agent panel includes `PanelStore`
  and `PanelContracted`.
- Existing production compression script: 542 source assets, 1,084 `.br`/`.gz`
  outputs. Every compressed file was decompressed and compared byte-for-byte
  with its source: zero failures.
- Output: 2,117 files, 115,135,485 bytes including maps and compressed variants.
- Manifest SHA256:
  `f65d8065af7432c2b10ab1be1ae5d6d67401352f666ac9cc10dc054982b44910`.

| Bundle | Raw bytes | Brotli bytes | Gzip bytes |
| --- | ---: | ---: | ---: |
| dashboard-CjxFtwy-.js | 2,108,478 | 534,909 | 626,355 |
| StoreCatalogPage-10wrg0My.js | 37,119 | 10,203 | 10,798 |
| AgentPanelPage--U57aaz4.js | 79,766 | 19,913 | 21,404 |

These are individual bundle sizes, not total first-navigation transfer sizes.
The current entrypoint discovery also includes the existing `sdk.spec.js`; this
validation did not change that discovery rule or execute that spec.

Ignored local evidence:

- `.codex/local-test/dashboard-full-build-20261013.log`: first build and wrapper
  measurement error.
- `.codex/local-test/dashboard-full-build-20261013-confirmed.log`: successful build.
- `.codex/local-test/dashboard-full-build-20261013-compression.log`: compression.
- `.codex/local-test/dashboard-full-build-20261013/vite/`: generated artifacts.

## Non-blocking warnings and remaining gates

Browserslist reports an outdated `caniuse-lite` database. Vite reports that
`FirstSteps.vue` has both static and dynamic imports and that some minified
chunks exceed 500 kB. No dependency update, chunk refactor or warning suppression
was performed in this build-only task.

This completes the full dashboard compilation/compression gate deferred in E3/E4.
It does not prove browser navigation, OAuth callbacks, served encoding
negotiation, image/container packaging, remote exact-head CI, Financial
cancellation/collection concurrency, real gateway behavior or AWS operation.
Those keep their separate validation and authorization gates. No frontend/Rails
test suite was rerun here. No push, PR, deploy or production access occurred.
