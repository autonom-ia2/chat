# QA local — Zoom do Kanban (#839)

Estes testes renderizam a aplicação real com Rails, Vite, Vue e a API do CRM. Não substituem o Kanban por HTML estático nem simulam as respostas de movimentação de oportunidades.

## Segurança e preparação

Use uma worktree exclusiva e um banco descartável **local** com nome `chat2you_839_*`. Os scripts Ruby recusam produção, hosts remotos e bancos fora desse prefixo. O script de navegador aceita somente `localhost`/`127.0.0.1`. Nunca aponte estes testes para contas ou oportunidades reais.

Pré-requisitos: dependências do `package.json`/`Gemfile.lock`, dependências de `tests/playwright`, Chromium do Playwright, PostgreSQL com as extensões do schema e Redis isolado. O ambiente desta validação utilizou Rails em `127.0.0.1:3839`, Vite em `127.0.0.1:35839`, Redis em `127.0.0.1:6839` e banco `chat2you_839_dev`.

Crie `.codex/839/env.sh` ignorado pelo Git, com as variáveis do ambiente local. Use `RAILS_ENV=development`, `FRONTEND_URL=http://127.0.0.1:3839`, `POSTGRES_HOST=127.0.0.1`, banco/usuário locais, `REDIS_URL` local isolado, `VITE_RUBY_HOST=127.0.0.1`, `VITE_RUBY_PORT=35839`, `CRM_KANBAN_ENABLED=true`, `CRM_CALENDAR_MEETINGS_ENABLED=true`, `CRM_AI_ENABLED=false`, `FORCE_SSL=false` e uma `SECRET_KEY_BASE` sintética. É possível usar `DISABLE_MINI_PROFILER=true` para retirar o profiler de desenvolvimento da captura. Não copie credenciais de produção.

Depois de carregar o schema nesse banco descartável, execute o seed uma única vez:

```sh
source .codex/839/env.sh
bundle exec rails runner tests/qa/kanban-zoom/seed.rb
```

O seed cria duas contas, um operador, funis, etapas, contatos/empresas sintéticos e cards. A credencial aleatória e os IDs são gravados com permissão `0600` em `.codex/839/fixture.json`, nunca no repositório ou nos relatórios públicos. Reutilize esse arquivo; não execute seed novamente no mesmo banco.

Inicie Redis isolado, Rails (`bundle exec rails s -b 127.0.0.1 -p 3839`) e Vite (`bundle exec vite dev`) com esse ambiente.

## Matriz principal

```sh
node tests/qa/kanban-zoom/browser.mjs
```

Valida os nove níveis 70/80/87/90/100/110/117/120/130; geometria fixa da interface externa; escala de cards/colunas; ambos os eixos de scroll; ausência de requisições CRM causadas pelo zoom; cinco presets; limites; arraste real entre etapas com resposta HTTP e persistência após reload; arraste real por toque no Chromium; preferência por conta; troca de funil; Lista/Calendário; teclado; Escape; clique externo; resoluções 1600/1366/1024/390.

Os artefatos vão para `.codex/839/browser-chromium/`: relatório JSON e capturas PNG. Para execução exploratória em outros motores instalados, use `KANBAN_QA_BROWSER=firefox` ou `KANBAN_QA_BROWSER=webkit`. Um motor não deve ser considerado validado apenas porque seus binários foram instalados: confira o relatório, erros e código de saída.

## Repetição e testes complementares

Os testes movimentam os cards sintéticos. Antes de repetir uma matriz, restaure **somente** as etapas dos cards criados pelo seed:

```sh
bundle exec rails runner tests/qa/kanban-zoom/reset.rb
```

Não execute matrizes mutáveis simultaneamente contra o mesmo fixture. A regressão complementar cobre os nove níveis: ordenação automática preservada, arrastar e retornar sem abrir o card, arraste até a última etapa com auto-scroll e drawers fora da escala. Também verifica busca e reabertura real do navegador:

```sh
node tests/qa/kanban-zoom/interaction-regression.mjs
```

Seu perfil de navegador persistente fica em `.codex/839/interaction-regression/browser-profile`, ignorado pelo Git. Nunca publique o perfil nem `fixture.json`, `auth.json` ou `env.sh`.

## Testes e build

```sh
pnpm test app/javascript/dashboard/routes/dashboard/crm app/javascript/dashboard/components-next/popover app/javascript/dashboard/store/modules/specs/crmKanban --maxWorkers=2 --minWorkers=1
pnpm i18n:fork:check
RAILS_ENV=production NODE_OPTIONS=--max-old-space-size=6144 bundle exec vite build
```

O build é apenas de assets locais; não publica release nem executa deploy. Confirme no CSS do dashboard que as 61 classes de zoom e as 61 regras do preview de toque foram preservadas. A auditoria em `docs/audit/2026-10-02-839-kanban-zoom.md` registra as execuções realizadas; o fato de haver um roteiro não equivale a um teste executado.
