# Registro histórico e retomada

As rodadas abaixo precedem o aditivo sem regex. O resultado vigente da retomada e seus
gates pendentes constam em [continuation-result.md](continuation-result.md).

# QA e aceite — Relacionamentos #757

**Estado: implementação local entregue para revisão; NÃO pronto para release.**
Não há evidência suficiente para afirmar plano completo nem ausência de regressões.
Integração Rails/API, E2E, comparação visual e performance continuam gates pendentes.
Nenhum commit, push, PR, merge, deploy, workflow dispatch, agente ou modelo pago foi executado.

## Base e contratos

- Worktree exclusivo: `/Users/rodrigosilva/dev/worktrees/chat2you-757-relacionamentos`.
- Branch: `feat/757-relacionamentos`; HEAD preservado em `8396d7255e097ba79507a22081701eb41ddb6ce5`.
- Estado inicial: somente `docs/relationships/` sem rastreamento (plano recebido), preservado.
- AGENTS.md e CLAUDE.md lidos; instruções explícitas desta tarefa prevaleceram sobre specs opcionais e inglês exclusivo.
- Node v24.11.0; pnpm 10.2.0; Ruby 3.4.4 via PATH explícito. Dependências globais não instaladas.
- Contratos inspecionados: policies/serviços de conversas core + Enterprise, controllers/models de atributos,
  Company/CompaniesController/Companies::BaseController, stores de contatos/empresas, editor legado,
  ContactPanel/CustomAttributes, rotas/menu, Account.settings/flags, Attachment e ActiveStorage.
- As flags novas ocupam posições adicionais de feature_flags_ext_1: 10 entradas nesse campo;
  feature_flags antigo permanece com 63. Todas as três novas flags têm enabled=false.

## Cobertura funcional entregue

| Bloco | Código entregue | Evidência e limite |
|---|---|---|
| REL-01 | Configuração versionada por conta, três flags independentes off, seleções por superfície, restauração, limpeza de IDs removidos, revisão otimista, gestão por attribute_manage | Specs de serviço/API escritos; isolamento/erro/retry testados em JS. Transações e políticas não executadas contra PostgreSQL |
| REL-02 | Modal Dialog real compartilhado em Central/fichas/lateral; descrição nova obrigatória, chave estável, edição sem troca de tipo/entidade, listas/regex, transação de definição+layout | Componentes testam criar, cancelar, conflito e renomear job_title sem substituir chave/tipo/entidade; backend atômico ainda sem integração |
| REL-03 | Campos centrais antes de seções finais, valores por confirmação, patch de uma chave, 0/false/date-only, rascunho em erro, descarte de resposta antiga; accordion/ordem/mostrar mais preservados | Testes de FieldEditor + apresentação + legado Empresa/opt-out; captura real de ContactPanel pendente. Caminho novo é local; CustomAttribute genérico não foi refatorado |
| REL-04 | API/consulta Enterprise por company_id atual, autorização antes de contar, busca global, filtros combináveis, agrupamento SQL, paginação estável, sidebar e tabela ampla, origem/autor separados | Componente de mídia testado; specs Rails incluem contagem privada, papel personalizado, cross-account, ocorrências, busca além da primeira página, consulta sem N+1. Não executados no banco |
| REL-05 | Preview sob demanda em job low, limites de tamanho/tempo/CPU/concorrência, derivado idempotente, fallback, reautorização e URLs de original de 60 s | Conversões reais locais PDF/vídeo e corrupto passaram. PNG falha por libvips ausente. Docker inclui vips/poppler; ffmpeg não está declarado na imagem. Homologação de runtime pendente |
| REL-06 | Item Relacionamentos, home sem métricas, três destinos com gates, seletor local de views, rotas legadas preservadas, breadcrumbs, pt_BR/en, Guia/Central gerados | Build e geradores passaram. Mobile/teclado/voltar/avançar e combinação de papéis/flags precisam de navegador real |

## Comandos efetivamente executados

Comandos Ruby usam `export PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:$PATH`.
Somente a tentativa de integração e o build carregaram `.codex/relationships/test-env.sh` autorizado.
Nenhum Rails foi executado antes da existência desse arquivo.

### Baseline

```sh
pnpm test app/javascript/dashboard/routes/dashboard/companies/pages/CompanyDetailView.spec.js app/javascript/dashboard/stores/specs/companies.spec.js app/javascript/dashboard/api/specs/companies.spec.js
```

**Passou: 3 arquivos, 16 testes.** Avisos existentes de Browserslist e sourcemap ausente em prosemirror-schema.
Sem screenshot baseline: backend não acessível pelo sandbox.

### JS — extensão e regressão focal

```sh
pnpm test app/javascript/dashboard/components-next/Relationships/specs app/javascript/dashboard/routes/dashboard/companies/pages/CompanyDetailView.spec.js app/javascript/dashboard/stores/specs/companies.spec.js app/javascript/dashboard/api/specs/companies.spec.js app/javascript/dashboard/helper/specs/commons.spec.js app/javascript/dashboard/components-next/Contacts/ContactOptOut/ContactOptOutSection.spec.js
```

Rodada anterior: **9 arquivos / 69 testes passaram**. Depois foram acrescentados dois testes de
CompanyMedia; rodada focal CompanyMedia + FieldConfigurator: **2 arquivos / 6 testes passaram**.
**Rodada consolidada final: 10 arquivos / 72 testes passaram**, incluindo a corrida de fechar/reabrir o modal durante um save pendente. Os testes de componentes usam Dialog, inputs e
ChoiceSelect reais com HTTP simulado; NÃO são E2E nem comprovam autorização/transação do servidor.

### Ruby sem Rails/banco

```sh
bundle exec rspec spec/relationships_unit --options /dev/null
```

**11 exemplos: 10 passaram, 1 falhou.** Falha mantida em preview PNG: loader nativo `libvips.42.dylib`
ausente. A investigação direta `bundle exec ruby -e 'require "vips"; ...'` confirmou LoadError.
PDF e vídeo produziram JPEG com assinatura real e tamanho limitado, usando fixtures sintéticas;
arquivo corrompido preservou original e retornou fallback. Validadores cobrem zero, nil, falso,
links, datas inválidas, lista e regex. A rodada inicial somente de ValueValidator passou 6/6.

### Ruby integração — bloqueado, zero exemplos executados

```sh
source .codex/relationships/test-env.sh
export PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:$PATH
bundle exec rspec spec/services/relationships spec/requests/relationships
```

**Bloqueado:** PG::ConnectionBad, `127.0.0.1:55757`, `Operation not permitted`.
O runner parou em maintain_test_schema; não é falha de asserção nem teste aprovado.
Specs Enterprise/valores/preview/performance acrescentados depois ainda não foram executados.
Não foi tentado servidor existente, socket alternativo, elevação ou bypass do sandbox.

### Estática, build e documentação

```sh
RUBOCOP_CACHE_ROOT=/private/tmp/relationships-rubocop bundle exec rubocop --no-server app/services/relationships app/controllers/api/v1/accounts/relationships enterprise/app/services/relationships enterprise/app/jobs/relationships enterprise/app/controllers/api/v1/accounts/companies/media_controller.rb spec/services/relationships spec/requests/relationships spec/enterprise/services/relationships spec/enterprise/requests/relationships spec/enterprise/jobs/relationships spec/relationships_unit --format simple
pnpm exec eslint --ext .js,.vue app/javascript/dashboard/components-next/Relationships app/javascript/dashboard/composables/useRelationships.js app/javascript/dashboard/routes/dashboard/relationships app/javascript/dashboard/components-next/Companies/CompaniesHeader/CompanyHeader.vue app/javascript/dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue
pnpm exec prettier --check app/javascript/dashboard/components-next/Relationships app/javascript/dashboard/composables/useRelationships.js app/javascript/dashboard/routes/dashboard/relationships tests/playwright/relationships.config.ts tests/playwright/tests/relationships/fields.spec.ts
pnpm exec vite build --mode test --outDir /private/tmp/relationships-757-vite-build
pnpm exec vite build --mode test --logLevel warn
pnpm guia:build
pnpm guia:check
pnpm central:check
```

- RuboCop: **20 arquivos, zero infrações** na última rodada completa. Correções foram limitadas aos arquivos novos.
- ESLint: sem erros após correções; avisos de resolução i18n no arquivo legado de Empresa foram observados.
- Prettier: checagem final passou. Divergências foram corrigidas sem alterar configuração/regras.
- Revisão explícita de todos os 30 JS/Vue tocados encontrou erros que a chamada anterior de diretórios (somente .js) não cobria. Props sem uso, ordem de funções, incrementos e conflitos de espaçamento dos labels foram corrigidos; a checagem final inclui --ext .js,.vue.
- Build completo: **passou**, 6.018 módulos, 1m43s; avisos de chunks grandes/Browserslist.
  vite-plugin-ruby escolheu `public/vite-test` apesar de outDir; diretório ignorado, sem artefatos versionados.
- Guia: **169 fluxos, 170 telas, zero sem explicação**; quatro explicações órfãs e aviso de logger já reportados pelo gerador.
- Central: **174 artigos, 170 telas cobertas**; avisos de evidências antigas/linhas deslocadas permanecem.
  Evidências mal formatadas dos dois artigos novos foram corrigidas antes do resultado verde.
- `git diff --check`: passou. Sintaxe Ruby: **22 arquivos, zero falhas**, por `ruby -c` nos alterados/novos.

RuboCop inicialmente tentou gravar cache fora do sandbox; foi reexecutado com cache em /private/tmp.
A tentativa de criar `.codex/relationships/build.log` foi negada por permissão; não foi contornada.
Logs completos permaneceram na saída das ferramentas; nenhum log ou screenshot foi colocado no repositório público.

### Navegador

```sh
RELATIONSHIPS_TEST_URL=http://127.0.0.1:3000 pnpm --dir tests/playwright exec playwright test --config relationships.config.ts --list
```

**Bloqueado:** executável playwright ausente nas dependências locais de tests/playwright.
Não houve tentativa de instalação global/download nem requisição de produção.
A configuração dedicada recusa host fora de loopback, não carrega .env externo e direciona
artefatos a `.codex/relationships`. O spec usa login e modal reais + respostas do backend;
foi escrito, mas nem sua coleta nem execução foram validadas. Não substituir isto por alegação de E2E.

## Gates obrigatórios ainda pendentes

- NAV-01..03: navegação real, roles/flags, URLs antigas, selector completo, back/forward/account switch.
- ATT-01..04, ATT-07..08, ATT-10..13: transações, concorrência real, cross-account e permissões em PostgreSQL/API;
  há evidência unitária/componentes para parte da lógica, insuficiente para fechamento.
- ATT-05..06, ATT-09, ATT-11..12: repetir fluxo real criar/salvar/recarregar, falha e troca de contexto no navegador.
- UI-01..02: baseline vs flags off/on em ~1630x930, viewport menor e mobile; light/dark, foco, teclado, scroll,
  accordions, mensagem, Resolver, CRM/compositor. Nenhuma captura real produzida nesta sessão.
- MED-01..09/COMP-01: executar specs Rails + cenários de API, metadados restritos, vínculo atual, paginação global,
  origem autorizada e fallback com a imagem runtime real. Corrigir dependência/validar PNG; validar ffmpeg no alvo.
- REG-01..02/ROL-01: regressão de mídias Contato/histórico/notas/vínculos, CRM/Cotação/automações/pré-chat/campanhas/variáveis,
  e desligamento independente das flags sem perda de dados. Não há garantia de zero regressão.
- Performance: executar contagem de queries incluída no spec e medir p95 com 1.000 ocorrências sintéticas,
  conforme limites definidos em company-media.md; nenhum número de latência foi inventado.
- Revisão adversarial independente pelo supervisor; pessoa responsável deve revisar também os blocos do Guia.

## Próxima execução autorizada ao supervisor

No ambiente isolado já provisionado, executar os specs novos e os contratos legados afetados:

```sh
bundle exec rspec spec/services/relationships spec/requests/relationships spec/enterprise/services/relationships spec/enterprise/requests/relationships spec/enterprise/jobs/relationships spec/controllers/api/v1/accounts/custom_attribute_definitions_controller_spec.rb spec/enterprise/controllers/api/v1/accounts/companies_controller_spec.rb spec/enterprise/services/enterprise/conversations/permission_filter_service_spec.rb
```

Preparar duas contas sintéticas e papéis administrador/agente/papel personalizado, flags off/on,
contatos com job_title=CEO e anexos sintéticos. Prover as variáveis RELATIONSHIPS_TEST_* descritas
no spec Playwright sem gravá-las nos documentos. O spec cobre apenas um fluxo; completar a matriz acima.
Não marcar pronto, não publicar, não habilitar em conta real enquanto houver gate pendente.

## Rodadas finais adicionais

- `pnpm test app/javascript/dashboard/components-next/Relationships/specs/FieldConfigurator.spec.js`: 5/5 após correção da resposta tardia em modal reaberto.
- Suíte consolidada acima: 72/72 (10 arquivos), saída às 11:37 UTC.
- `pnpm exec vite build --mode test --logLevel warn`: execução final após os ajustes de lint concluída com **exit 0**; avisos de Browserslist/chunks grandes mantidos.
- Warnings i18n dinâmicos/legados permanecem; nenhuma regra de lint foi enfraquecida.
- ESLint explícito dos 30 arquivos JS/Vue: zero erros, 256 avisos, exit 0.
- Último ajuste: busca de contatos da mídia rejeita `q` em array ou com mais de 200 caracteres; spec de request acrescentado, ainda bloqueado com os demais testes Rails.
- `RUBOCOP_CACHE_ROOT=/private/tmp/relationships-rubocop bundle exec rubocop --no-server enterprise/app/controllers/api/v1/accounts/companies/media_controller.rb spec/enterprise/requests/relationships/company_media_spec.rb --format simple`: 2 arquivos, zero infrações. `ruby -c` em ambos: Syntax OK. `git diff --check`: passou.
