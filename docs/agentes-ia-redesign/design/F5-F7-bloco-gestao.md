# F5–F7 — gestão do agente

## Estado final verificado em 08/10 — fonte80

Este registro prevalece sobre os checklists históricos abaixo. Fonte
`20261008-203511-532a5b7b-f42aa58719-03f5a091`, conteúdo
`f42aa58719a8923091ab565bd5903ad5c4d3e5b7e9841aa762a88179cf94c077`,
duas réplicas verificadas. Frontend: **200/200** em 33 arquivos, lint sem erros,
Guia e i18n em dia, build aprovado. Recibos da fonte78 aplicáveis à fonte80 por
comparação integral 78→79→80. Backend79: **276 exemplos, zero falhas** e formatos
em dia. Os sete alinhamentos de spec foram corrigidos na fonte80, com AST Ruby
idêntica comprovada; lint80: **42 arquivos, zero ofensas**. O erro intermediário
de lint permanece registrado na auditoria.

Navegador final: **124/124** cenários nos quatro perfis. Galeria: **196 capturas
originais, 49 estados**, computador/celular e claro/escuro; 40 referências do
mockup identificadas à parte. Portal: **18/18 destinos autenticados** e 236
imagens conferidas. Dados e IA fictícios, aplicação e persistência reais.

R1 encontrou sete achados corrigidos. R2 encontrou dois P1 de contrato de
cotação e distribuição de conversa nativa; causas corrigidas. **O mesmo
revisor aprovou a R3 final**, sem achados acionáveis, em
`../revisoes/F5-F7-r3.md`. Não há R4. Aceite visual do Rodrigo pendente.
Isso é validação local, sem CI, commit, push, novo PR ou publicação.

- Telas reais: http://127.0.0.1:59750/preview-telas
- Jornada interativa: http://127.0.0.1:59750/preview-gestao

Plano de implementação do bloco aprovado do PRD, com escopo, contratos,
ownership e evidências de validação. O root integra os arquivos compartilhados.

## Objetivo e arquitetura

Permitir ensinar, testar, associar canais e ajustar um agente seguindo a jornada
e o visual aprovados. A nova experiência usa componentes sob
`agentes/components/panel`, preserva os componentes legados e consome as APIs
reais. O backend só recebe os complementos necessários para versões, cotação,
alvos de encaminhamento e leitores reais; não há migração nem banco de
produção.

Stack: Vue 3 com `<script setup>`, Tailwind e design system existentes, Rails,
PostgreSQL, Vitest, RSpec e Playwright.

## Aprovação, limites e regras de validação

Issue #1164, épica #1114 e Project 3. Em 08/10, Rodrigo aprovou o PRD/mockup,
aceitou F4 e autorizou este bloco. As referências são PRD §6.3 e §11.4, D1–D35
e os mockups aprovados. A implementação está na worktree
`agentes-ia-prd`, branch `docs/agentes-ia-prd`, inicialmente em
`532a5b7beb56902d2a0168013a3e8b657ba31488`.

Há alterações dirty de outros owners; elas devem ser preservadas. Nesta etapa
não há commit, push, novo PR, alteração da main, release, produção, provedor
pago, dado de cliente, segredo ou limpeza de snapshot. O PR #1115 permanece
congelado.

Cada seção salva apenas o próprio payload. O modo manual começa vazio e só
grava texto não vazio. Instrução guiada, scaffold e prompt nunca aparecem na
interface. A tela usa Tailwind e o design system; não usa `<select>` nativo,
CSS próprio, `window.confirm` ou confirmação nativa. Os catálogos do recurso
existem em inglês e `pt_BR`. A flag desligada continua usando o legado.

Canais são apenas os existentes e podem ser múltiplos por agente; QR e criação
de conexão continuam em Canais. Conta e permissão são sempre revalidadas pelo
servidor. A regra de validação é: R1 → corrigir → repetir exatamente a mesma
R2 → corrigir a causa raiz → repetir exatamente a mesma R3 → se ainda falhar,
parar. Não há R4. Falhas de validação ficam registradas antes da revisão.

## Task 1 — O que sabe

**Owner:** `gestao_conhecimento`.

Componentes novos entregues em
`app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/panel`:

- `PanelKnows.vue` e sua spec;
- `KnowledgeMaterialCard.vue` e sua spec;
- `AddMaterialDialog.vue` e sua spec;
- `FaqReviewList.vue` e sua spec.

`PanelKnowledge`, `SourceAddDialog` e `FaqSuggestionsSection` permanecem
intactos. `MaterialCard` e `MaterialDropzone` da criação só são reutilizados
quando mantêm o contrato e o visual necessários.

Props públicas: `agentId: Number`, `agent: Object` e `canManage: Boolean`. O
painel consome, por agente e conta, `sources.get/create/resync/delete` e
`faqSuggestions.list/approve/ignore`. O root fornece `signal` opcional aos
readers sem quebrar chamadas antigas; não se usa estado global de outro agente
para pintar a resposta.

Contratos de escrita:

```js
SourcesAPI.create(agentId, { url, kind: 'knowledge' });
FaqAPI.approve(agentId, suggestionId, { question, answer });
AgentsAPI.update(agentId, {
  agent: { config: { faq_suggestions: enabled } },
});
```

Para arquivo, o descriptor é `{ file, kind: 'knowledge' }`; `sources.js`
monta o `FormData` com `source[source_type/reference/kind]` e o arquivo. A lista
mostra a contagem real de fontes de conhecimento, com limite de 30; não inclui
mídia de teste. O painel lê `screen_state` e `uses` do backend e não deduz
estado por texto.

FAQ usa 25 itens por página e uma ação explícita de carregar mais. Não há loop
infinito de páginas. A tela cobre carregando, erro com retry, vazio, dados,
limite, permissão, remoção confirmada e resync: são os oito estados projetados.
Arquivos respeitam 25 MB e formatos permitidos, com aviso para Word/Excel quando
aplicável. Cotação usa `PanelQuoteKnowledge` e `quote_branches`; não usa
`insurance/*`.

- [x] Implementação e specs próprias entregues.
- [x] Chaves `REDESIGN_KNOWLEDGE` em inglês e `pt_BR` entregues e aplicadas pelo
  root.
- [ ] Execução runtime deste bloco, ainda pendente na validação final da Task 6.

## Task 2 — Onde atende

**Owner:** root ou `r9_produto`, conforme o slot liberado.

`PanelWhereServes.vue` e spec próprios foram entregues. Props: `agentId`,
`agent` e `canManage`. O reader retorna `payload.connected`,
`eligible_inboxes` e `occupied_inboxes`; IDs já conectados ao próprio agente
são retirados dos ocupados.

Contratos:

```js
ChannelsAPI.get(agentId, { signal });
ChannelsAPI.connect(agentId, inboxId); // { inbox_id }, HTTP 201
ChannelsAPI.disconnect(agentId, inboxId); // HTTP 204, após ConfirmDialog
router.push({ name: 'settings_inbox_new', params: { accountId } });
```

A projeção local é cancelável. POST e DELETE são sequenciais e o GET só é
recarregado depois de sucesso; falha conserva a projeção anterior. Rascunhos e
agentes pausados não associam, agentes internos não buscam caixas e múltiplos
canais são preservados. `inbox_manage` controla o atalho para configurações;
`autonomia_manage` controla escrita. Ocupados ficam desabilitados e a tela
mantém as seções “Onde atende” e “Colocar em outro canal”.

- [x] Implementação, spec e i18n entregues.
- [ ] Execução consolidada da rodada final.

## Task 3 — Ajustes e ferramentas

**Owner:** `f4_abas_visuais`.

Foram entregues `PanelSettings.vue`, as seções
`SettingsIdentity/Instructions/Actuation/Speech/Handoff/Audience/Schedule/Versions/Lifecycle/Quote`,
`PanelToolsV2.vue`, `ToolDialog.vue` e as specs próprias, todos em
`agentes/components/panel`. Não se cria um formulário genérico e o legado
`PanelTune/PanelTools` permanece preservado.

Props: `agentId`, `agent`, `canManage` e `resumeBuild`. Cada seção envia apenas
seu payload:

```js
AgentsAPI.update(id, { agent: { name, voice: 'feminina' } });
AgentsAPI.update(id, { agent: { mode: 'manual', instruction: manualText } });
AgentsAPI.update(id, { agent: { mode: 'guided' } });
AgentsAPI.getHandoffTargets(id); // members e teams
AgentsAPI.update(id, {
  agent: { config: { handoff_target_type: 'member', handoff_target_id: userId } },
});
AgentsAPI.updateQuoteChoices(id, { name, behavior: 'consultivo', horario });
AgentsAPI.getInstructionVersions(id);
AgentsAPI.restoreInstructionVersion(id, versionId);
```

`voice` é um campo superior tipado como `feminina|masculina`; `config` pública
fechada do BE19 continua sem `voice`. O DTO expõe `has_guided_version`. Versões
trazem `origin` e autor; texto só aparece para versão manual. Restaurar guiado
exige uma versão guiada guardada; restaurar manual mantém modo manual e
scaffold manual. Reconversa usa `buildThreads.resume` e o chat existente, sem
rota ou flag legada. Concluir conserva nome, greeting, fallback e tone do
contrato BE05/23. Tons gravam as frases exatas do mockup; tons antigos só são
pré-selecionados, sem UPDATE de produção (D10F9).

Agentes internos ocultam atendimento e greeting; `both` mostra o aviso de
cliente. Cotação mostra somente identidade, estilo, horário, alvo, público,
janela e ciclo. Estados E1–E4 continuam indicando montagem no destino atual;
E2m aponta para o ajuste novo. Versões confirmam restore e nunca exibem texto
gerado. Pausa, remoção e canal usam `ConfirmDialog`/soft delete e explicam a
consequência. Avisos de canais sem horário apontam para as caixas pelo nome.

Tools lê `{ payload: [...] }` em `response.data.payload`. Apenas SuperAdmin
acessa. O formulário começa vazio, estoque só é aplicado por ação explícita,
segredo mascarado não é reenviado e o resultado aceita quebra de linha com
limite 10. O diálogo usa foco, Escape e `ChoiceSelect`; não há endpoint de
cliente ou provedor pago fictício. As specs usam HTTP local fictício quando
precisam representar uma resposta; não apontam para endpoint externo.

- [x] Implementação, specs e catálogos próprios em inglês e `pt_BR` entregues.
- [ ] Fixture do `ToolDialog` e execução final ainda pendentes sob o owner
  correspondente; não há aprovação antecipada.

## Task 4 — Dependências reais de backend

**Owner:** `conferencia_backend`.

O owner pode tocar somente os controllers, serializers, modelos, services,
rotas, locales e specs listados no plano original, verificando antes os
correspondentes de Enterprise. Frontend, APIs JS, catálogos JS e QA ficam fora
deste owner. A lista concreta é: `agents_controller.rb`; os novos
`agents/quote_choices_controller.rb` e `agents/handoff_targets_controller.rb`;
`instruction_versions_controller.rb`; `agent.rb`; os concerns
`instruction_versioning.rb` e, se necessário, `builder_attributes.rb`; views de
`_agent/instruction_versions`; `QuoteAgent::Builder`; os novos
`operate/handoff_router.rb` e, se necessário, `handoff_note.rb`;
`operate/responder.rb`, `aviso_ao_atendente.rb` e `event_logger`; rotas, locales
`config/routes.rb`, locales backend `en`/`pt_BR` e specs próprias. O root regenera Guia e formatos quando
necessário.

### BE23 — versões e instruções

- Versões carregam `origin` e metadata suficientes para restauração.
- Ao entrar em manual, a última versão guiada fica guardada em `before_manual`.
- Voltar a guiado restaura a versão guiada em transação; sem ela responde
  `422 no_guided_version`.
- Restaurar manual mantém modo manual e scaffold manual; restaurar guiada deixa
  o agente em guided.
- Builder, `before_manual` e `kb_refresh` nunca aparecem no serializer.
- Texto só é exposto para autoria manual ou rollback manual; autor inexistente
  é `null`.
- Texto manual é validado na borda da requisição e `actuation` é preservado.
- BE05 mantém o resume apenas com campos autorizados e conclui o registro do
  builder com `Current.user`.

### BE17 e D32 — cotação e voz

PATCH de cotação aceita `{ name?, behavior?, horario? }`, resolve o agente na
conta correta, exige permissão de gestão e rejeita tipo ou campo desconhecido
com `422`, sem coerção. `Builder.public atualizar_escolhas!` reutiliza as quatro
validações existentes em transação e não expõe nome de corretora ou instrução.
O DTO de detalhe expõe `instrucao_mantida` e
`quote_choices{name, behavior, horario}`. Estados legados incompletos falham de
forma explícita. Voz usa enum fechado no topo e merge de `config` preservando o
BE19.

### BE06/24 — encaminhamento

`HandoffRouter` só é chamado nas três portas Responde, skip e Aviso antes de
`bot_handoff`. O padrão é `any=baseline`. Membro precisa de caixa atribuível;
time distribui apenas entre seus membros. Sem distribuição ou membro, cai no
time sem assignee. Alvo inválido vira `any` com log sanitizado, sem vazamento
entre contas. O evento guarda o alvo atribuído no momento.

A nota privada é idempotente por episódio, usa uma única integração existente
de `NotaDoEncaminhamento` e nunca é enviada ao cliente. CRM, funil, pausa,
remoção e remoção de canal permanecem fora. `GET handoff_targets` exige
`autonomia_manage`, cruza pessoas com as caixas e lista times da conta. Não há
migração.

- [x] Implementação e contratos backend entregues.
- [x] Locales backend em inglês e `pt_BR` entregues.
- [x] Prova existente: 260 exemplos e 0 falhas na fonte 5536.
- [ ] Review, aceite visual e execução final; a prova acima não os substitui.

As specs contratuais devem manter branches, choices, permissões, tenant,
transação parcial e reflexo no prompt; voz; origins, contador e privacidade de
versões; e as três portas de alvo, default, fallback, time, nota privada e
ausência de CRM.

## Task 5 — Testar e integração

**Owner:** root.

`PanelAgentTest.vue` foi entregue com `AgentTestPhone` em extensão aditiva:
`mode="creation|panel"`, mantendo `creation` como padrão. No painel, a
apresentação e os controles de criação desaparecem, mas o compositor e a
grade continuam alinhados. Imagens aceitam quatro arquivos de até 5 MB cada.

O teste usa resposta real do endpoint e mostra reply, certeza, material usado,
ferramentas ignoradas, tempos e aviso de escrita externa. A legenda cobre
Certeza, Material e Amarelo; a variante interna não mostra passagem amarela e
a cotação não oferece ensinar. Ensinar só é emitido para quem pode gerenciar e
segue para Conhecimento. Não se infere handoff a partir de confidence.

O wrapper usa `AgentsAPI.test` e o polling oficial com `AbortSignal`. Limpar,
trocar de agente e desmontar invalidam o request. Rate limit, erro, espera de
180 segundos, retry com a mesma pergunta e resposta vazia permanecem visíveis;
um viewer pode testar, mas não ensinar. A criação antiga conserva seu default e
seu wrapper. `resumeBuild` é propagado sem alterar o fluxo legado. O teste não
envia anexos para a pipeline de fontes.

O Page usa os componentes novos de conhecimento, canais, ajustes, ferramentas
e teste. A transição E2m aponta para o novo Tune. APIs e helpers compartilhados
permanecem sob ownership do root: `agents.js`, `channels.js`, `sources.js`,
`faqSuggestions.js`, `buildThreads.js` e `aiRequestPolling.js`, quando houver
necessidade de ajuste aditivo; as specs de API e polling devem continuar
compatíveis com as chamadas antigas.

- [x] Implementação, specs e chaves `REDESIGN_TEST` em inglês e `pt_BR` entregues.
- [ ] Aprovação runtime pendente. Na última execução registrada, o frontend teve
  173 testes passados e 4 falhos: um fixture de `Dialog` em
  `SettingsInstructions` (correção aplicada depois, sem nova execução nesta
  etapa) e três falhas de `ToolDialog`, sob outro owner.

## Task 6 — validação e entrega

**Owner:** root, com QA quando houver slot.

Evidência visual existente: inspeção Chromium isolada no M2 com 72 capturas e 0
erros, SHA
`c0895b0b116de805dbc562ac19be87f38a8a4d7414ca0d012cc1b45f32edb9dc`. As
referências estão em `snapshot49/.codex/preview/gestao56-refs`; a inspeção não
usa o Chrome pessoal. Essa prova é do mockup/inspeção registrada e não encerra
aceite do produto.

Pendências:

- [ ] Repetir as mesmas specs depois das correções, sem declarar RED de TDD que
  não foi registrado. O que existe é prova de specs escritas e da execução
  acima; não há evidência registrada de uma rodada RED anterior à implementação.
- [ ] Rodar a mesma cadeia autorizada: backend wrapper isolado, Vitest, ESLint,
  `i18n:fork:check`, RuboCop, build local, `guia:check` e `formatos:check`.
- [ ] Usar `maccluster work plan/run` e o wrapper RSpec oficial no snapshot
  autorizado; não instalar runtime, copiar checkout ativo ou alterar serviços.
  O planner já apontou M2 elegível, com 195 GB e térmica nominal, e M4 com 19 GB
  e espaço insuficiente. IAB está indisponível.
- [ ] Criar/rodar `gestao.spec.ts` com API e banco fictícios exclusivos, quatro
  perfis e as variantes viewer, manager, admin, internal, both, quote, draft,
  manual e guided. Cobrir fontes, estados por fixtures/projeções, loading, erro
  com interceptação explícita, FAQ, canais, modos, versões, avatar, alvos,
  tools, leituras/escritas e a regressão da criação F4.
- [ ] Conferir galeria real, portal scenarios, SHA individual das capturas e
  regressão F4; manter a fonte única, o preview F4 e o limite de 30 materiais.
  Quando o runtime exclusivo estiver autorizado, usar as portas 59750–59753.
- [ ] Criar o snapshot oficial somente depois de os fixtures e a fonte estarem
  coerentes; não duplicar snapshot por harness nem alterar a fonte F4 congelada.
- [ ] Fazer review independente R1 e aplicar a regra R1→R2→R3 descrita acima.
- [ ] Mostrar as telas e jornadas ao Rodrigo, atualizar Issue/Project e aguardar
  aceite visual. Não há release nesta etapa.

Runtime, revisão independente e aceite do Rodrigo permanecem pendentes mesmo
com a implementação e os catálogos entregues.

## Conferência de consistência

CA-SAB, CA-OND, CA-AJU, CA-FER e PTES estão distribuídos nas Tasks 1–5 e na
matriz da Task 6. D7 é exclusivo de Canais; D20 não permite mídia; D1 não usa
régua; D24 preserva E5/E6; D32 mantém dados tipados e não interpreta nome por
regex; D22, D25 e NR10 cobrem writer, serializer e teste. C1–C15 seguem
registrados na auditoria por controle, variante e evidência local.

As dependências B4 (BE23), B5 (BE06/24) e B6b (BE17) foram implementadas neste
bloco sem transformar isso em prova de produção. A revisão de backend, a
execução runtime frontend, o review independente e o aceite visual continuam
separados e pendentes até a validação final.
