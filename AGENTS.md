# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## Escolha única: sem `<select>` nativo (regra do Rodrigo, 18/09/2026)

- Nunca use `<select>` nativo em tela de produto (nem `v3/components/Form/Select.vue` nem `components-next/select/Select.vue`, que renderizam um por baixo). A lista nativa ignora o design system e muda de navegador para navegador.
- Use `components-next/choice-select/ChoiceSelect.vue`: teclado do padrão WAI-ARIA *select-only combobox* (`dashboard/helper/choiceKeys.js`), leitor de tela e alvo de toque de 44 px.
- Ao tocar numa tela que ainda tenha `<select>`, troque todos os dela.

## Telefone: um campo só (regra do Rodrigo, 18/10/2026)

- Todo campo em que a pessoa digita um telefone no painel usa `components-next/conversa-canal/mais/CampoDeTelefone.vue` (com `telefoneDoPais.js`). Ele traz país com bandeira e DDI, Brasil por padrão, e formata o número no jeito do país enquanto se digita (libphonenumber-js, mesmo modelo do PhoneCountryInput do Orth/google-saas). O valor só sai quando o número é válido para o país, já no formato E.164 (`+5511987654321`).
- Em tela nova, não use `<input type="tel">` solto, máscara feita à mão nem o `PhoneNumberInput` do Chatwoot. Ao tocar numa tela que tenha um desses, troque.
- O servidor continua validando o E.164. O campo não substitui essa validação.
- Exceção: bundle público leve (`public_booking_v2`) tem campo próprio por causa do peso no 4G. Unificar ali só com medida de peso antes e depois, em PR do dono da página.

## General Guidelines

- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- Enforce eligibility and exclusivity rules at the earliest shared entry point. Do not repeat backup guards across downstream jobs, callbacks, services, or writes unless a proven independent path bypasses that point.
- Validate request parameters at the controller or request boundary, reusing existing errors so invalid input returns `422 Unprocessable Entity` instead of reaching models or Sentry.
- Accept only the documented type, shape, and value. Do not add compatibility coercions for malformed client values; fix official clients instead.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - For upstream Chatwoot source-string changes, update the English source catalogs; upstream translations are handled through Crowdin and the community. This does not restrict the product's supported languages or the translations of Chat2You-owned features.
  - Fork-owned frontend catalogs listed in `config/fork_i18n.json` are a repository-owned overlay excluded from Crowdin. Update their source and `pt_BR` together, preserve existing other languages, and run `pnpm i18n:fork:check`. Fork-owned keys in shared catalogs may also update en/pt_BR together without excluding the shared catalog. Follow `docs/i18n/fork-translations.md` when adding a module.
  - Chat2You-owned features require English and Brazilian Portuguese in the same PR. Other supported languages may also be translated; preserve their existing translations and the dashboard's fallback. Updating these translations within an authorized feature does not require a separate approval.
  - Crowdin-generated translation sync PRs may update non-English locale files; do not flag those changes solely for modifying translated locale files
  - Preserve product and brand names, OAuth scopes, API values, and other machine-readable identifiers unless an official localized form exists
  - When reviewing Crowdin syncs, verify protected terms remain unchanged. Add newly introduced product names, brand names, and machine-readable identifiers to the Crowdin glossary as non-translatable, and keep the glossary current
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Frontend Conventions

- Prefer existing design-system utilities and shared composables.
- Use typography utilities instead of manually recreating font styles.
- Use logical Tailwind utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts.
- Use `rem` for arbitrary CSS dimensions; preserve native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants.
- Use shared request-cancellation utilities instead of local `AbortController` logic.

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

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
- Checklist de uma chave nova: `CustomRole::PERMISSIONS`, policy/controller, módulo em `settings/customRoles/permissionMatrix.js`, i18n `CUSTOM_ROLE.MATRIX` (en + pt_BR), `meta.permissions` da rota, entrada do menu e `useCanManage('<modulo>_manage')` nos botões de escrita.
- Delegação em duas listas (regra do Rodrigo, 17/10/2026, #1782). Substitui o antigo "nunca delegar por função". "Administrador" aqui é o papel `administrator` da conta.
  - **Só o administrador**, nunca vira chave de função: excluir ou transferir a conta; plano, faturas, pagamentos, forma de pagamento e cancelamento do contrato com a Hub2You (o módulo Financeiro); promover alguém a administrador.
  - **Delegável só com chave própria e as quatro proteções (hoje: só o administrador)**: usuários, equipes e funções; custos da conta (`financial_view`: valores do uso de IA e a autorização de cobranças da Meta; `financial_manage`: ligar e desligar essa autorização, #1969); integrações, webhooks e tokens (`integration_manage`: conectar integrações, webhooks, robôs e importações e trocar a credencial de uma caixa que já existe; `token_manage`: ver e trocar os segredos que a plataforma gera, sem emitir token acima da própria função; credencial colada de outro sistema só volta para o administrador, #2027); Anúncios da Meta (`meta_ads_manage`: conectar, configurar e desconectar, inclusive dar à plataforma acesso à conta de anúncios do cliente, ligar o aviso de vendas no funil e o resumo no WhatsApp, #2070); valores de venda em R$ do CRM (`sales_value_view`: valor do card, somas, metas e taxas tiradas do dinheiro; sem ela, a função vê contagens e os próprios cards, e o `crm_admin` não a liga, #2075); login único (SAML) e leitura do histórico de auditoria; configurações gerais da conta (nome, idioma, fuso, horário). As quatro proteções, no servidor:
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
