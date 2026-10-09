# Auditoria — mapeamento F1 “Seus agentes”

**Data:** 2026-10-07  
**Issue:** #1130  
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Branch:** `docs/agentes-ia-prd`  
**Escopo:** desenho e leitura estática; nenhum código Vue, teste, banco, produção, commit ou push.

## Resultado

O desenho F1 foi escrito em `docs/agentes-ia-redesign/design/F1.md`, ainda em DRAFT. A lista nova tem
leitor real disponível (`GET autonomia/agents`) e pode reaproveitar o store account-scoped, mas não está
pronta para implementação sem dois contratos: a retomada BE-05 e um campo seguro para o gênero dos textos
da tela. O cartão novo não pode ser apenas uma troca de classes do `AgentCard.vue` legado, porque o legado
decide por `status`, não lê E1–E6 e não possui a projeção de estatísticas/canais do B2.

## Evidências usadas

| Assunto | Prova | Decisão no F1 |
|---|---|---|
| Fonte visual | `docs/agentes-ia-redesign/mockup/src/screens-list.js:1-94`, `data.js:21-74`, `kit.js:71-88`, `styles.css:62-135` | reproduzir lista, vazio, resumo, estados e responsividade; não transportar faixa de protótipo, IDs ou dados da conta do mockup. |
| Critério da lista | `docs/agentes-ia-redesign/PRD.md:150-168`, `864-905` | quatro ações e estados E1–E6, viewer com Abrir, menu apenas em rascunho, contador sem zero para interno. |
| Máquina de estados | `docs/agentes-ia-redesign/PRD.md:420-470` e `design/B2.md:140-160` | `state.code`/`continuation` são a fonte; `status` sozinho nunca escolhe rótulo ou rota. |
| Envelope seguro | `design/B2.md:92-136` | uma lista em lote com `state`, `stats`, `channels`; não expor instruction/scaffold/mensagens/config privada. |
| Projeção atual | `app/controllers/api/v1/accounts/autonomia/agents_controller.rb:16-20`; `app/services/autonomia/agents/list_projection.rb:9-14,37-103`; `app/views/api/v1/accounts/autonomia/agents/index.json.jbuilder:1-12` | GET já organiza a relação, projeção e `meta`; F1 não faz N+1. |
| Privacidade do legado | `app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder:35-52` | na lista com `list_row`, instruction não é serializada; só `has_instruction` permanece. O `AgentsHubPage.vue:30-48` e `AgentCard.vue:21-26,78-118` não leem instruction, então não há dependência oculta desse texto. |
| Cliente/store | `app/javascript/dashboard/api/autonomia/agents.js:5-10`; `api/ApiClient.js:12-59`; `store/storeFactory.js:83-89` | usar `get/update/delete` account-scoped existentes, sem novo cliente para F1. |
| Criação | `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentBuilderPage.vue:40-49,181-207`; `api/autonomia/buildThreads.js:16-35` | o CTA da lista só navega; o POST real nasce na Escolha/Builder. Modelo do vazio usa `route.query.type`. |
| Painel e permissões | `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js:33-40,115-139`; `AgentPanelPage.vue:60-88,140-203` | viewer abre painel e Testar; manage escreve; SuperAdmin não recebe operação nova em F1. |
| Canais | `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:18-35,53-104`; `PRD.md:1130-1131` | nenhum caminho de conexão dentro de Agentes; `settings_inbox_new` continua a Central de Canais. |

## Bloqueios e riscos concretos

1. **Voz/gênero ausente na lista.** D32/PRD exige que `{a}/{ela}` venha de `config.voice`, mas o envelope
   de B2 em `design/B2.md:94-117` não traz `voice` e o jbuilder de lista só seleciona `config` em
   `_agent.json.jbuilder:23-26`, sem essa chave. O front não pode ler o blob inteiro nem deduzir pelo nome.
   A correção mínima de contrato é expor apenas o enum seguro no item da lista, ou entregar os pronomes já
   localizados pelo backend. Sem uma dessas opções, os textos de canal/pausa/exclusão não passam D32.
2. **BE-05 ainda não é uma rota real.** O código atual só declara `resources :build_threads` no topo em
   `config/routes.rb:395`; não há `GET agents/:id/build_thread` em routes/controller. F1 documenta o caminho
   como dependência de B3 e não permite `start` ou thread fictícia para “Continuar”.
3. **PATCH pode apagar a projeção do cartão no store.** `autonomiaAgents.update` usa `EDIT` (`storeFactory.js:78-80`),
   cuja mutação substitui o registro (`app/javascript/shared/helpers/vuex/mutationHelpers.js:18-23`). A resposta
   de `show` não recebe `list_row` (`show.json.jbuilder:1-1`), então não traz `state`, `stats` ou `channels[]`
   (`_agent.json.jbuilder:37-45`). F1 exige GET da lista após todo PATCH; não usar atualização otimista.

Esses pontos são contratos/ordem de implementação, não autorização para alterar B2 ou criar fallback no
front. O legado pode continuar funcionando com sua resposta de `show` porque o painel não depende da projeção
da lista; a tela nova depende.

## Legado confrontado

`AgentsHubPage.vue:37-48` leva qualquer rascunho pelo `status === 'draft'` para `publish`, em vez de usar
`state.continuation`; `:114-120` esconde “Criar agente” quando há zero registros; `:124-146` usa spinner e
erro simplificado, sem o esqueleto normativo; `:165-175` reaproveita uma grade de cartões sem resumo. O
`AgentCard.vue:24-29,31-59,109-118` mostra `human_card`, contador de canais e placeholder “—”, mas não
mostra `state`, stats reais, linha de canal ou interruptor. `:122-144` oferece excluir para qualquer agente
do editor, enquanto CA-LISTA-10 limita o menu da lista a rascunhos. Por isso o F1 reaproveita store,
permissão, Avatar/Button/Dialog e o fluxo de API, mas cria `AgentsListPage`/`AgentRow` novos.

## Método de RuboCop informado ao principal

A evidência de zero offenses disponível nesta rodada foi obtida no checkout M4, não em um novo job M2:

```sh
eval "$(rbenv init -)"
bundle exec rubocop --force-exclusion \
  app/controllers/api/v1/accounts/autonomia/agents/channels_controller.rb \
  app/services/autonomia/agents/copilot_availability.rb \
  app/services/autonomia/agents/mirror_identity_sync.rb \
  app/services/autonomia/agents/operate/engagement_gate.rb \
  spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb \
  spec/requests/api/v1/accounts/autonomia/agents/copilot_availability_spec.rb \
  spec/services/autonomia/agents/copilot_availability_spec.rb \
  spec/services/autonomia/agents/mirror_identity_sync_spec.rb
```

Resultado reportado: `ok ✓ rubocop (8 files)`, 0 offenses. O job M2 anterior no snapshot oficial
`/Users/Shared/maccluster-workspaces/chat2you/20261007-171803-532a5b7b-137087fb42-2b3f3f5e/src` foi uma
varredura maior (`m2-b20d7658e3aa4664b3c543ecd1efb905`) e teve 172 offenses no conjunto; não o apresento
como prova de zero. Para o principal repetir no M2, o método seguro é primeiro `maccluster work plan --cwd`
nesse snapshot e depois `maccluster work run --cwd` com o mesmo comando absoluto do Ruby 3.4.4:

```sh
/Users/Shared/maccluster-tools/ruby-3.4.4/bin/ruby \
  /Users/Shared/maccluster-tools/ruby-3.4.4/bin/bundle exec rubocop --force-exclusion <os-8-arquivos>
```

Não executei esse job, não instalei dependências e não toquei nos serviços de teste nesta subtarefa.

## Limite da validação visual

O navegador local do mockup estava bloqueado pela CUA e não foi contornado com localhost, CDP ou headless.
O desenho usa as fontes rastreáveis e a referência publicada que já havia sido inspecionada pelo fluxo
anterior; isso não é captura de tela real do produto. A tela nova não está implementada/aceita nesta worktree.
As quatro combinações de viewport/tema e os quatro cenários definidos no F1 só podem ser marcados depois
de existir o código real, API local, dados locais e captura Playwright correspondente.

## Validação desta escrita

- leitura estática de PRD, B2/F0, mockup, rotas, store, API, serializer e componentes legados;
- nenhuma execução de RSpec, Vitest, build, browser, banco ou serviço;
- `git diff --check` deve ser executado após a escrita dos dois documentos;
- sem commit, push, PR, merge, fila, deploy ou produção.
