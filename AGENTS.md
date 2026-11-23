# Chatwoot Development Guidelines

In this fork `CLAUDE.md` is a separate copy of this file, not a symlink: when you change a fork rule in one, change it in the other. Keep shared, repository-wide instructions here and detailed procedures in linked docs. Add nested `AGENTS.md` files only for subtree-specific differences; avoid duplicating root rules.

## Build, Test, and Lint

- **Ruby setup**: Use the version in `.ruby-version` through `rbenv`. Before Ruby commands, run `eval "$(rbenv init -)"`; use `bundle exec` for Rails, RSpec, and RuboCop.
- **Install dependencies**: `bundle install && pnpm install`
- **Run development**: `pnpm dev` or `overmind start -f Procfile.dev`
- **Lint Ruby**: `bundle exec rubocop <changed Ruby files>`; use autocorrection only when intended and inspect its diff.
- **Lint JS/Vue**: `pnpm exec eslint <changed JS/Vue files>`; `pnpm eslint` checks the full frontend.
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb` (append `:LINE_NUMBER` for one example).
- **Test JS**: `pnpm test <test path>` or `pnpm test:watch`.
- **Seed data**: `bundle exec rails db:seed` for minimal data; `bundle exec rails search:setup_test_data` for search/load scenarios. For richer account data, Super Admin → Accounts → Seed enqueues `Internal::SeedAccountJob`, which uses `Seeders::AccountSeeder`.

## Readability and Scope

- Prefer the smallest production-ready change that solves the current problem. Build for supported callers and realistic production workloads; do not add speculative abstractions, guards, fallbacks, retries, or one-in-a-million edge cases.
- Optimize for understanding on the first read. Use descriptive names, explicit control flow, and ordinary multiline methods/functions. Avoid Ruby endless methods (`def value = expression`), semicolon-packed bodies, and compressed JavaScript functions; do not shorten code merely to fit line or class limits.
- Extract helpers or split files/classes when they clarify responsibilities or remove meaningful complexity. Avoid one-use helpers that only rename an obvious expression.
- Follow RuboCop and ESLint. Refactor responsibilities when size/complexity limits expose a problem; do not disable cops or exclude files to avoid that work. Any unavoidable suppression must be narrowly scoped and explain why the compliant approach is unsuitable.
- Do not introduce `Thread.new` or monotonic-clock APIs such as `Process.clock_gettime(Process::CLOCK_MONOTONIC)` unless necessary and explicitly approved by the user. Prefer existing job/concurrency patterns.
- Remove dead code and superseded implementations; do not keep alternate versions or commented-out logic.

## Dependencies

- Add an npm package, Ruby gem, or other dependency only when necessary. Reuse existing maintained dependencies, standard-library capabilities, or shared utilities first; explain why they or a small, maintainable implementation cannot reasonably meet the requirement.
- Before adding a dependency, verify current upstream maintenance, release activity, community/support health, and security advisories and patch responsiveness. Do not introduce abandoned or unmaintained packages. Prefer a small, readable implementation for behavior we can reasonably own; continue to use maintained, proven libraries for protocol, authentication, and signing rather than hand-rolling them.
- Before upgrading, read release notes, changelogs, and migration guides across the full version jump. Audit every call site, wrapper, configuration, and indirect integration, including framework usage and affected OSS/Enterprise paths, for changed APIs, defaults, error behavior, and deprecations. Update affected code and tests together.
- Verify runtime/framework, peer, and transitive dependency compatibility; inspect manifest and lockfile changes for unintended upgrades. Run focused behavior and integration checks across all affected surfaces to establish compatibility. A successful install or a minor/patch version label is not sufficient evidence that an upgrade is safe.

## Escolha única: sem `<select>` nativo (regra do Rodrigo, 18/09/2026)

- Nunca use `<select>` nativo em tela de produto (nem `v3/components/Form/Select.vue` nem `components-next/select/Select.vue`, que renderizam um por baixo). A lista nativa ignora o design system e muda de navegador para navegador.
- Use `components-next/choice-select/ChoiceSelect.vue`: teclado do padrão WAI-ARIA *select-only combobox* (`dashboard/helper/choiceKeys.js`), leitor de tela e alvo de toque de 44 px.
- Ao tocar numa tela que ainda tenha `<select>`, troque todos os dela.

## Telefone: um campo só (regra do Rodrigo, 18/10/2026)

- Todo campo em que a pessoa digita um telefone no painel usa `components-next/conversa-canal/mais/CampoDeTelefone.vue` (com `telefoneDoPais.js`). Ele traz país com bandeira e DDI, Brasil por padrão, e formata o número no jeito do país enquanto se digita (libphonenumber-js, mesmo modelo do PhoneCountryInput do Orth/google-saas). O valor só sai quando o número é válido para o país, já no formato E.164 (`+5511987654321`).
- Em tela nova, não use `<input type="tel">` solto, máscara feita à mão nem o `PhoneNumberInput` do Chatwoot. Ao tocar numa tela que tenha um desses, troque.
- O servidor continua validando o E.164. O campo não substitui essa validação.
- Exceção: bundle público leve (`public_booking_v2`) tem campo próprio por causa do peso no 4G. Unificar ali só com medida de peso antes e depois, em PR do dono da página.

## Rails, Validation, and Database Queries

- Follow RuboCop (including the 150-character line limit). Use compact namespace declarations such as `class Foo::Bar`, while keeping method bodies multiline.
- Use idiomatic model methods, associations, scopes, and named route helpers. Keep reusable queries and relationship traversal in models/scopes; return an ActiveRecord relation when callers need further filtering or ordering.
- Controllers coordinate requests and responses. Keep request-specific URL generation and presentation in controllers or view helpers.
- Enforce stored-value rules in model validations or existing JSON/JSONB schema validators so all ordinary write paths share them. Do not duplicate the same check in controllers. Validate transient filters, lookups, and service arguments at the request boundary before queries/services use them. Use strong params and existing errors so invalid input returns `422 Unprocessable Entity`.
- Accept only documented input types, shapes, and values. Fix malformed official clients instead of adding compatibility coercions.
- Prefer model-level constraints, associations, and callbacks over new database constraints. Add a database constraint only for a demonstrated integrity need that code-level enforcement cannot adequately cover. For foreign keys, check deletion behavior and production migration/locking risks; existing constraints are not a reason to add more.
- Write application queries, joins, and data migrations with ActiveRecord and Arel. Do not add raw SQL strings, SQL heredocs, `execute`, or raw SQL hidden inside `Arel.sql` to production paths. Keep raw SQL confined to temporary diagnostic or operational scripts; use Rails migration APIs for schema changes.
- Design queries and joins for production scale: use tenant-scoped predicates, appropriate indexes and column order, bounded results/batches, and preloading where needed. Check join cardinality, duplicate rows, N+1 queries, and costly counts/sorts. For material query changes, inspect generated SQL and representative query plans; a small fixture database is not performance evidence.
- Generate migrations with `bundle exec rails g migration <Name>` so their versions are real timestamps. Do not hand-write or round migration versions.
- Enforce eligibility/exclusivity at the earliest shared entry point. Add another guard only for a real independent path that bypasses it.
- Fail visibly for invalid required configuration or impossible setup states. Use required reads (`find`, `find_by!`, required hash keys) for locked/internal configuration; do not silently skip behavior. Add checks only when they meaningfully change behavior, and use existing custom exceptions in `lib/custom_exceptions/` where appropriate.

## Tests and Validation

- Add or update meaningful tests for customer-facing behavior and underlying model, service, job, API, or state changes. Cover the intended success path and relevant failures, permissions, and lifecycle transitions; use enough coverage to establish the behavior, not just the implementation shape.
- For new or changed functionality, map and test every affected surface and consumer, including dashboard, widget/SDKs, APIs, jobs, integrations, real-time events, and OSS/Enterprise paths where relevant. Include shared behavior outside the edited files. Explicitly check whether Super Admin screens, configuration, permissions, or management actions need corresponding changes, and implement and test them when required.
- For a bug fix, add a focused regression that fails for the original behavior and passes with the fix. For core/Enterprise changes, cover the affected edition paths.
- Avoid tests that merely repeat migration declarations, configuration, formatting, or other mechanical changes. Test migration/backfill transformations when they carry meaningful data behavior, and verify operational migration safety separately.
- Run focused specs and linters after code changes. For documentation-only changes, check formatting, links, and the diff. Report checks actually run and any remaining validation gaps.
- Prefer `let` values and direct per-example setup; introduce custom spec helpers only when they remove meaningful repetition or complexity.
- Use `with_modified_env` rather than stubbing `ENV`. In parallel/reloading specs, prefer comparing `error.class.name` over constant class equality when asserting raised errors.
- Keep review-only work read-only unless changes are requested. Use existing specs or temporary probes and report missing regression coverage.

## Code Review Rules

- Apply these checks during implementation and PR review. Report concrete regressions on supported paths, with the trigger, impact, and evidence; distinguish intended behavior from defects. Leave formatting and lint-only findings to CI.
- Name the affected behavior and trace entry points, source of truth, side effects, and consumers across APIs, jobs, supported clients, and Enterprise overlays.
- Inspect unchanged helpers reached by new callers or defaults. Treat valid `false` configuration distinctly from missing values; check repeated reads, cache invalidation, and disabled-feature work.
- Bound database/Redis work, fanout, retries, scheduled jobs, and lock/connection hold time at representative production scale. Green unit tests or the existence of an index do not establish capacity.
- Exercise relevant sequences such as failure → success → failure, new events while quota-held, clock boundaries, and rollback with existing state. Assert exact required values, not merely that something changed.
- Carry deferred concerns through stacked PRs and review the assembled feature when activated. Include scheduled jobs, cached values, and persisted state in rollback/recovery reasoning.
- Review the exact PR head and complete relevant discussion; recheck affected findings if the head changes. A resolved thread is not proof that the failure was fixed.
- Give material findings a failure scenario, disposition, and evidence. Keep the approval/verdict consistent with open blockers. An accepted risk needs an explicit owner, rationale, mitigation, and follow-up or activation condition.
- Read the relevant sections of [Production Reliability](docs/production-reliability.md) when changes affect hot paths, queries, caches, fanout, quotas/retries, recovery, middleware/provider boundaries, or rollout state. Apply checks to actual risks; small changes do not need every protocol.

## Frontend and Styling

- Use Vue Composition API with `<script setup>` at the top, PascalCase component names, camelCase events, and `defineProps` declarations with appropriate types/validation.
- Use existing design-system utilities and shared composables. Use `components-next/` for message bubbles; older message-bubble components are being deprecated.
- Use Tailwind utilities; do not introduce custom/scoped CSS or inline styles. Refer to `tailwind.config.js` for colors and use existing typography utilities.
- Use logical utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts. Use `rem` for arbitrary CSS dimensions, preserving native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants. Use shared request-cancellation utilities instead of local `AbortController` logic.

## Translations and Branding

- Use i18n for user-facing strings; no bare strings in templates. Backend i18n → `en.yml`, frontend i18n → `en.json`.
- For upstream Chatwoot source-string changes, update the English source catalogs; upstream translations are handled through Crowdin and the community. This does not restrict the product's supported languages or the translations of Chat2You-owned features.
- Fork-owned frontend catalogs listed in `config/fork_i18n.json` are a repository-owned overlay excluded from Crowdin. Update their source and `pt_BR` together, preserve existing other languages, and run `pnpm i18n:fork:check`. Fork-owned keys in shared catalogs may also update en/pt_BR together without excluding the shared catalog. Follow `docs/i18n/fork-translations.md` when adding a module.
- Chat2You-owned features require English and Brazilian Portuguese in the same PR. Other supported languages may also be translated; preserve their existing translations and the dashboard's fallback. Updating these translations within an authorized feature does not require a separate approval.
- Crowdin-generated sync PRs may update non-English files; do not flag that alone. Verify that product/brand names, OAuth scopes, API values, and other machine-readable identifiers remain unchanged unless an official localized form exists. Keep newly introduced protected terms in the Crowdin glossary as non-translatable.
- For UI strings that should adapt to branded/self-hosted installations, use `replaceInstallationName` from `shared/composables/useBranding` instead of hardcoded Chatwoot copy.

## Enterprise Compatibility

- Before changing core logic or public APIs, search both `app/` and `enterprise/` for related implementations. Keep request/response contracts compatible and mirror shared-code renames/moves where needed.
- Extend existing OSS functionality for Enterprise through modules (`prepend_mod_with` / `include_mod_with`), hooks, flags, or configuration instead of hardcoding plan/instance-specific behavior in OSS. Put Enterprise-exclusive functionality under `enterprise/`.
- For new endpoints, services, and models, consider the extension points Enterprise needs to avoid hard forks. Put Enterprise specs under `spec/enterprise`, mirroring OSS layout where applicable.
- Follow the [Enterprise development handbook](https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38).

## AI Models

- Before adding/changing an OpenAI model, check the [deprecations page](https://developers.openai.com/api/docs/deprecations). Do not choose a model with a shutdown date; use its recommended replacement. Select models through `config/llm.yml` and `Llm::FeatureRouter`, not hardcoded names.

## Worktrees

- Use a separate worktree and branch per task; reuse the task's existing worktree when available.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for process orchestration.
- The setup in `.codex/environments/environment.toml` should generate per-worktree database names, ports, and Redis DB indexes. Use a distinct Overmind socket/title for each worktree.

## Commits and Pull Requests

- Prefer Conventional Commits: `type(scope): subject` (scope optional). Do not reference Claude in commit messages.
- Every PR must link its GitHub Issue (`Refs #N`; `Closes #N` only when the PR closes the whole Issue). Confirm an existing Issue or create one before opening the PR; do not invent issue references.
- For medium/large features (for example, a new workflow or a change spanning several layers), link the design/PRD/implementation artifact in both the Issue and the PR. Keep those links and the description aligned with the final scope.
- Start the PR description with a short, user-facing explanation of the change. Add a `Closes` section with the relevant GitHub issues.
- Follow applicable repository-template sections. For features, include product/UX `How to test` steps; for bug fixes, include `How to reproduce` when useful. Add `What changed` only when it helps review.
- Do not add a `How this was tested` section listing specs/commands; report automated validation in the task handoff instead.

## Model Routing

- Tarefas críticas ou adversariais não podem sofrer downgrade automático de modelo.
- Se a classe de modelo exigida estiver indisponível, interrompa com `BLOCKED_MODEL_TIER` em vez de usar silenciosamente um modelo mais fraco.
- Evals com provedores pagos ficam desativados por padrão e exigem execução explícita com orçamento definido.

## Audit Trail

- Registre decisões, comandos de validação, resultados e bloqueios em `docs/audit/`.
- Nunca registre prompts completos, tokens, secrets, credenciais ou dados de clientes.
- Merge, deploy, produção, banco de produção, secrets, auth, billing e infraestrutura exigem aprovação explícita do Rodrigo.

## Funções personalizadas (custom roles)

- Módulo novo que é só de admin: gate com `AccountUser#permission_granted?('<modulo>_view' | '<modulo>_manage')`. No OSS responde `administrator?`; o EE soma as chaves da função, e `_manage` implica `_view`. Agente comum sem função continua sem acesso.
- Checklist de uma chave nova: `CustomRole::PERMISSIONS` (e `CustomRole::DELEGATION_KEYS`, se for da lista delegável abaixo), policy/controller, módulo em `settings/customRoles/permissionMatrix.js`, i18n `CUSTOM_ROLE.MATRIX` (en + pt_BR), `meta.permissions` da rota, entrada do menu e `useCanManage('<modulo>_manage')` nos botões de escrita.
- Delegação em duas listas (regra do Rodrigo, 17/10/2026, #1782). Substitui o antigo "nunca delegar por função". "Administrador" aqui é o papel `administrator` da conta.
  - **Só o administrador**, nunca vira chave de função: excluir ou transferir a conta; plano, faturas, pagamentos, forma de pagamento e cancelamento do contrato com a Hub2You (o módulo Financeiro); promover alguém a administrador.
  - **Delegável só com chave própria e as quatro proteções (hoje: só o administrador)**: usuários, equipes e funções; custos da conta (`financial_view`: valores do uso de IA e a autorização de cobranças da Meta; `financial_manage`: ligar e desligar essa autorização, #1969); integrações, webhooks e tokens (`integration_manage`: conectar integrações, webhooks, robôs e importações e trocar a credencial de uma caixa que já existe; `token_manage`: ver e trocar os segredos que a plataforma gera, sem emitir token acima da própria função; credencial colada de outro sistema só volta para o administrador, #2027); Anúncios da Meta (`meta_ads_manage`: conectar, configurar e desconectar, inclusive dar à plataforma acesso à conta de anúncios do cliente, ligar o aviso de vendas no funil e o resumo no WhatsApp, #2070); ferramentas dos agentes de IA (`autonomia_tools_manage`, a partir da #1430; até lá, só a equipe da plataforma: criar, editar, testar, ligar e apagar as ferramentas que mandam dados da conversa para um sistema de fora; não vem com `autonomia_manage` e nenhum modelo pronto a inclui; o valor de um cabeçalho marcado como segredo é só de escrita, ninguém o relê, nem o administrador; levar a ferramenta para outro site (esquema, domínio ou porta) pede o segredo digitado de novo, e `Host` e cabeçalhos de encaminhamento são recusados; a Lia fica de fora); valores de venda em R$ do CRM (`sales_value_view`: valor do card, somas, metas e taxas tiradas do dinheiro; sem ela, a função vê contagens e os próprios cards, e o `crm_admin` não a liga, #2075); login único (SAML) e leitura do histórico de auditoria; configurações gerais da conta (nome, idioma, fuso, horário). As quatro proteções, no servidor:
    1. só o administrador entrega essas chaves;
    2. quem entrega uma função só entrega função cujas chaves ele também tem. Exceção: o ajuste fino "Pode entregar acesso acima do próprio", que só o administrador liga numa função. Com ele, quem tem a função entrega qualquer função da conta, inclusive com áreas desta lista (o RH que contrata o diretor comercial cria o acesso dele). Nem com o ajuste alguém promove a administrador (regra do Rodrigo, 20/10/2026, #1931);
    3. ninguém edita a própria função nem o próprio acesso;
    4. concessão, alteração e revogação de função ou chave ficam no histórico de auditoria da conta (audit log do Enterprise). O histórico é a proteção do ajuste da regra 2: não há aviso extra aos administradores.
  - Enquanto a chave de uma dessas áreas não existir com as quatro proteções, a área continua só do administrador. O que não está listado acima, em segurança e conta, também continua só do administrador.
  - Por quê: em empresa estruturada, pessoas, financeiro e tecnologia têm dono que não é o CEO (CHRO, CFO, CTO). Sem delegar, a única saída era dar administrador, e com ele acesso a tudo.

## Guia da Plataforma — o mapa é gerado, a explicação é escrita

- `lib/operator_guide/guia-produto.md` e `app/javascript/dashboard/helper/guideRouteRegistry.js` são **arquivos gerados**. Não edite nenhum dos dois à mão: a próxima geração descarta a edição.
- O que só nós sabemos — `onde_fica`, `intent`, `passos`, `gotchas` — fica em `lib/operator_guide/porques.md`, um bloco por fluxo. O cabeçalho do bloco é um nome curto e único; o campo `rota` aponta a tela no roteador. Vários fluxos podem apontar para a mesma tela.
- A rota, o endereço e o gate (feature flag e papéis, inclusive funções personalizadas) saem do próprio roteador do painel. Mexeu em rota ou permissão, rode `pnpm guia:build` e envie o resultado junto.
- `pnpm guia:check` falha quando o gerado está fora de dia. Rode antes de abrir PR que toque em rotas, menu ou explicações.
- O formato de cada ação de escrita do Guia (`lib/operator_guide/formatos-das-acoes.json` e o relatório de cobertura ao lado) também é **gerado**, do código (#900). Mexeu em controller, strong params ou validação de um recurso que o Guia alcança? Rode `bundle exec rails autonomia:guia:formatos` e envie o resultado; `autonomia:guia:formatos:check` (e o spec `formatos_spec.rb` no CI) falha quando ele está fora de dia.
- **Tela nova sem explicação não passa no PR** (`.github/workflows/guia-trava.yml`, #535). A IA comenta no próprio PR o rascunho do bloco; a trava só libera quando uma pessoa põe a explicação em `porques.md` — o rascunho da IA não libera sozinho. Há três saídas: explicar; declarar a tela em `_fora_do_guia` com o motivo (definitivo); ou o rótulo `guia-nao-se-aplica` com uma linha `Guia não se aplica: <motivo>` no corpo do PR (vale só para aquele PR).
- Tela que entrou sem explicação mesmo assim (dispensada pelo rótulo, ou push direto no `main`) é pega depois do merge pelo **modo aprendiz** (`.github/workflows/guia-aprendiz.yml`, #537), que abre um PR com o rascunho. Sem tela nova, os dois ficam calados.

## Limpeza depois do deploy: branch, worktree e snapshot (regra do Rodrigo, 09/10/2026)

A entrega só termina depois do deploy, da conferência em produção ("ok, SHA")
**e da limpeza**. Na mesma etapa, pedir e fazer as três:

1. **Branch** — apagar a branch remota, se o merge não apagou.
2. **Worktree** — `git worktree remove` + `git worktree prune`, com as
   verificações do `/Users/rodrigosilva/dev/CLAUDE.md` (seção 2).
3. **Snapshot do MacCluster** — apagar os snapshots da entrega em
   `/Users/Shared/maccluster-workspaces/<projeto>/<snapshot>`.

Como apagar o snapshot (não existe comando `maccluster` de remoção):

- Só os snapshots da própria entrega, pelo **caminho exato**, nunca com curinga.
  O nome traz o SHA curto do HEAD de origem (`<data>-<hora>-<sha>-...`).
- Antes, conferir que nada o usa: `lsof +D <caminho>` sem saída.
- Apagar em cada nó onde houver réplica (`maccluster exec --node m2|m4 -- ...`).
  `maccluster workspace list` pode continuar listando o apagado.
- Snapshot é cópia descartável do working tree: tudo nele está no git. Não
  exige quarentena nem aprovação individual.

**Reaproveite o snapshot.** Um por entrega, não um por rodada de teste: depois
de editar, copie os arquivos alterados para dentro do `src` do snapshot e rode
de novo. Snapshot novo só quando muda a base (outro HEAD, migration nova).

Por que a regra existe: em dois dias as rodadas de teste criaram cerca de 120
snapshots de ~360 MB cada. O disco do M4 chegou a 98% e travou o trabalho.

## n8n: onde está a credencial (regra do Rodrigo, 13/10/2026)

Os robôs de atendimento rodam no n8n em `https://auto.autonomia.site`. Quem
precisar ler fluxo ou execução usa a API do n8n com a chave que já existe:

- Arquivo: `/Users/rodrigosilva/dev/projetos.noindex/api_agger/.env.local`
  (reserva: `/Users/rodrigosilva/dev/projetos.noindex/email_rodrigo/.env.local`).
- Variáveis: `N8N_API_KEY` e `N8N_BASE_URL` (no reserva, `N8N_URL`).
- Uso: cabeçalho `X-N8N-API-KEY` em `https://auto.autonomia.site/api/v1/...`.
- A chave de `projetos.noindex/Fluxo_n8n/.env.local` não vale mais (HTTP 401).

Regras:

- Ler a chave do arquivo dentro do comando; nunca imprimir, colar em chat,
  commitar ou copiar para este repositório.
- Só leitura por padrão. Alterar, ativar ou executar fluxo exige OK do Rodrigo.
- Fluxo exportado pode trazer token real em `pinData` e em nós com valor fixo:
  mascarar antes de mostrar qualquer trecho.
- O ID do número e o token da Meta usados pelos robôs não ficam no n8n: vêm do
  Autonomia Settings (`api-settings.autonomia.site`, campos `api-key-evolution`
  e `token_meta`). Trocar a conta do WhatsApp de uma caixa exige atualizar lá.
