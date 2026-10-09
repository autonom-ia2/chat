# F0 — mapa executável do kit, das entradas e das rotas

**Estado: DRAFT — não aprovado; aguardando revisão.** Este documento é um desenho de integração. Ele não afirma que as telas reais existem, não aprova o protótipo para produção e não autoriza merge, deploy, produção, banco ou fila. A fonte visual continua sendo `docs/agentes-ia-redesign/mockup/src`; a faixa de protótipo, o mapa e o seletor de perfil nunca entram no produto.

## 1. O que F0 precisa deixar pronto

F0 prepara a fundação que permite implementar as telas da jornada sem criar uma segunda versão do Chat2You:

1. o gate do redesign e as entradas nova/antiga, derivados do contrato de BE-00;
2. as peças comuns extraídas do #993, sem quebrar seus imports, teclado, foco, locale ou specs;
3. `n-navy` no tema Tailwind comum, conforme D4, sem hex repetido em componente;
4. o namespace de i18n em inglês e pt-BR e os checks do catálogo;
5. o kit da nova área, somente com componentes reais do design system;
6. as specs de rota, a configuração Playwright local e o helper de acessibilidade que serão usados desde a primeira tela real.

O código novo da área deve ficar em `app/javascript/dashboard/routes/dashboard/autonomia/agentes/{pages,components,composables}/`, como determina PRD §8. A pasta antiga permanece utilizável enquanto a flag existir (`PRD.md:642-655`). Nenhum import faltante pode ser resolvido com página vazia, mock ou stub: se uma API, uma peça compartilhada ou um estado de backend ainda não existir, a fatia fica bloqueada e volta ao PR/BE responsável.

### Dependências e causa de cada uma

| Pré-requisito | Por que vem antes | O que fica bloqueado se faltar |
|---|---|---|
| B2/BE-00 | A entrada precisa distinguir o gate antigo (`autonomia_agents_enabled`) do gate novo por conta (`autonomia_agents_redesign_enabled`). Sem o payload booleano e o default `false`, o guard não pode escolher a tela nova com segurança (`design/B2.md:64-89`). | Todas as entradas e o fallback, F1 e as specs de isolamento entre contas. |
| B2/BE-01/08/11/27/28/32 | A lista, o estado E1–E6, a ocupação, os materiais, a gaveta e o ajudante devem ler códigos/projeções tipadas do backend. A camada visual não pode inferir estado por texto (`design/B2.md:606-621`). | F1 e qualquer cenário real de lista, cartão, rascunho, canal, material ou ajudante. |
| B3/BE-05 | A retomada guiada do legado, exceto E2m manual, precisa do leitor escopado `GET agents/:agent_id/build_thread`: última thread guiada do agente, `autonomia_manage`, 401 sem permissão e 404 para outro agente/conta/ausência. O retorno precisa hidratar o store antes de montar `PanelTune`; este contrato não é fornecido pelo B2. | Fallback de Conte, Teste, Ligue e Pronto; qualquer F5/deep link sem criação de thread. |
| D9/#993 | `StepsBar`, `LabeledSwitch`, foco de gaveta e locale serão importados pelas páginas novas e já são usados pela jornada de Campanhas. Extrair depois faria a nova UI depender de cópias ou quebraria os imports existentes. | Kit de etapas, interruptores, gavetas e formatação de números/datas. |
| D4 | As telas claras e escuras precisam consumir o mesmo token semântico desde o primeiro componente; um hex local cria divergência visual e impede a revisão do tema. | Heróis, resumos e demais superfícies que usam azul-marinho. |
| i18n + a11y | O PRD proíbe texto fixo, exige en/pt_BR, papéis reais e foco navegável. O catálogo e o helper `expectNoSeriousA11y` precisam existir antes da primeira captura, para que uma tela “pronta” já tenha evidência verificável. | F1/F2 e o gate visual das 13 famílias. |

As dependências acima são de contrato, não autorização para fabricar dados. A ordem de implementação deve parar no primeiro contrato ausente; não deve mascará-lo com fallback visual.

## 2. Inventário factual do que pode ser reaproveitado

| Necessidade da jornada | Fonte existente e prova | Uso no redesign |
|---|---|---|
| Lista, cartão, carregando, vazio, erro e confirmação | `routes/dashboard/autonomia/pages/AgentsHubPage.vue` e `components/AgentCard.vue`; componentes-next `Button`, `EmptyStateLayout`, `Dialog`, `Spinner` e `Icon` | Reaproveitar lógica de carregamento, permissão, estados e exclusão. A composição visual nova será feita em F1, com `AgentsListPage`, `AgentRow`, `AgentsSummaryChips`, `AgentsEmptyHero` e `AgentModelCard` do Apêndice A (`PRD.md:1397-1401`). |
| Escolha e Construtor | `AgentBuilderPage.vue` e `components/builder/{BuilderStepBar,BuilderChat,ChatComposer,BuilderKnowledgePanel,BuilderReview}.vue`, mais `AgentTypePicker.vue` | F2 separa Escolha e Conte em páginas da rota nova, mas preserva a criação de thread/rascunho e o comportamento assíncrono do Construtor. A página antiga continua sendo o fallback da rota antiga. |
| Conversa e materiais | `components/builder/{BuilderChat,ChatBubble,ChatComposer,MaterialCard,MaterialDropzone}.vue`, `components/panel/{PanelKnowledge,SourceAddDialog}.vue` | F2 usa essas peças e os composables existentes para mostrar apenas o que a API devolve: respostas fora de ordem, link sugerido, material pendente/falho e retomada. Não transformar uma resposta do modelo em estado por regex. |
| Painel | `AgentPanelPage.vue` e `components/panel/Panel{Test,Knowledge,Channels,Performance,Tune,Publish,Tools}.vue` | F4–F7 reconstroem a casca e os leitores da jornada, reaproveitando regras e chamadas quando o contrato for igual. A ordem visual nova é Como está indo, Testar, O que sabe, Onde atende, Ajustes e Ferramentas; a URL continua sendo a fonte da aba. |
| Escolhas únicas | `components-next/choice-select/ChoiceSelect.vue` e `helper/choiceKeys.js` | Todo campo de escolha usa `ChoiceSelect`. Nenhuma tela nova pode importar `components-next/select/Select.vue` ou `<select>` nativo. |
| APIs e stores | `api/autonomia/{agents,buildThreads,sources,channels,faqSuggestions,builderImages}.js` e os módulos `store/autonomia*` | Reusar apenas os contratos reais. APIs planejadas pelo PRD (`sources/reusable|copy`, `quote_branches`, `publish` e estados de B2) são dependências explícitas do respectivo BE; não criar cliente que simule resposta. A conexão de WhatsApp continua na área central de Canais e não entra no kit de Agentes. |
| Catálogo e locale | `app/javascript/dashboard/i18n/locale/{en,pt_BR}/agents.json` já é o catálogo fork, declarado em `config/fork_i18n.json`; `agentBots.json` é o catálogo antigo de bots | As chaves do redesign entram em `AGENTS.V2.*` de `agents.json`, em en e pt_BR no mesmo PR. Datas/números passam por `toLocaleTag`, conforme `PRD.md:656-682`. |

## 3. Extração D9: quatro peças, destinos e preservação

D9 foi decidido como opção (a): extrair no F0 e deixar o #993 importar do lugar comum (PRD.md:89-94). Os destinos abaixo ainda não existem no snapshot. A extração é uma mudança de localização, não uma oportunidade para alterar o contrato.

| Peça atual | Destino comum | Consumidores reais a atualizar | Contrato que fica preservado |
|---|---|---|---|
| components-next/CampaignJourney/JourneyStepper.vue | components-next/stepper/StepsBar.vue | routes/dashboard/campaigns/journey/NewCampaignPage.vue:18,739 | A peça comum recebe uma lista ordenada de etapas com chave/rótulo, além de current, reachable, evento go, aria-current="step" e teclado Arrow/Home/End. O adaptador de Campanhas entrega exatamente 3 etapas; AgentSteps entrega exatamente 4. A spec existente (CampaignJourney/specs/JourneyStepper.spec.js:27-72) continua cobrindo o contrato de três etapas. |
| components-next/CampaignJourney/JourneySwitch.vue | components-next/switch/LabeledSwitch.vue | CampaignJourney/{AudienceChannelSwitches,AudienceCompanies}.vue e routes/dashboard/campaigns/journey/LiveChatJourneyPage.vue | checked, disabled, label, ariaLabel, evento toggle, role="switch" e alvo mínimo de 44 px, conforme JourneySwitch.vue:4-11,15-40. |
| components-next/CampaignJourney/useModalFocus.js | dashboard/composables/useModalFocus.js | SidePanel comum consome o trap; AudienceSidePanel migra sua estrutura para SidePanel e remove a chamada antiga | Baseline: useModalFocus({container, initial, onClose}) possui o ciclo inteiro. Alvo: useModalFocus({container}) devolve activate/deactivate só para Tab/Shift+Tab, mantendo focusableIn e diálogo nativo no topo; SidePanel passa a ser o único dono de foco inicial/Escape/retorno. A migração é atômica, não um simples re-export da API antiga. |
| components-next/CampaignJourney/localeTag.js | dashboard/helper/localeTag.js | Todos os imports listados abaixo, specs e CampaignOverviewPage.vue | pt_BR → pt-BR, fallback en, formatNumber para pt-BR/en e null → 0, preservando CampaignJourney/specs/localeTag.spec.js:4-24. CampaignOverviewPage migra obrigatoriamente; incompatibilidade real interrompe a extração até haver prova e spec de paridade. |

A peça comum de etapas não terá rótulos fixos de Campanhas. O adaptador de Campanhas conserva AUDIENCE/MESSAGE/REVIEW e seu i18n; o adaptador de Agentes define CHOICE/TELL/TEST/LIVE. **Pronto é tela de conclusão em ready, não uma quinta etapa.** O caminho de produto é Escolha → Conte → Teste → Ligue → Pronto, mas a barra tem quatro itens (PRD.md:47,170,920 e mockup/src/kit.js:84). AgentSteps nunca deve exibir Pronto como quinto item.

### Consumidores completos de locale

A atualização do import de localeTag precisa enumerar e conferir estes 15 consumidores produtivos:

- components-next/CampaignJourney/{AudienceChannelBadges,AudienceChannelSwitches,AudienceColumns,AudienceCompanies,AudiencePeople,AudienceSidePanel,SmsJourneyMessage,StepAudience,StepReview,TemplateVariableBindings,WhatsAppApiMessage}.vue;
- components-next/CampaignJourney/scheduleTime.js;
- routes/dashboard/campaigns/journey/{AudiencesPage,CampaignJourneyPage,NewAudiencePage}.vue;
- components-next/CampaignJourney/specs/localeTag.spec.js.

routes/dashboard/campaigns/journey/CampaignOverviewPage.vue:47-58 contém uma implementação local de localeTag; ela deve migrar obrigatoriamente para `dashboard/helper/localeTag.js` e a cópia local deve ser removida. Se houver incompatibilidade real, a extração para antes da remoção, registra a diferença e adiciona uma spec de paridade; não se aceita uma exceção aberta. O grep final deve encontrar nenhum import produtivo para o caminho antigo e nenhuma duplicata local.

### Lifecycle do foco compartilhado

SidePanel.vue:27-89 já controla `open/close`, captura o gatilho, foco inicial em `afterEnter`, scroll lock, Escape, clique fora, foco de retorno e `afterLeave`. Essa propriedade permanece única no SidePanel: ele é o dono de abrir/fechar, Escape, scroll, gatilho, restauração e fechamento final. Depois de `afterEnter`, o SidePanel escolhe o foco inicial (alvo explícito `data-autofocus`, quando houver; senão a raiz/foco padrão do painel) e ativa o trap; em `afterLeave`, restaura o gatilho salvo. No unmount, ele limpa o estado sem tentar restaurar duas vezes.

O `useModalFocus` comum muda explicitamente sua API interna: `useModalFocus({ container })` devolve `activate`/`deactivate`, além do export `focusableIn`. Não recebe `initial`/`onClose`, não captura gatilho, não possui Escape/scroll/foco inicial/restauração e não emite close. O SidePanel escolhe foco inicial após `afterEnter` e só então ativa o trap; desativa no início de close, restaura o gatilho uma vez em `afterLeave` e limpa no unmount. Diálogo nativo no topo permanece dono de suas teclas.

A migração de `AudienceSidePanel` é no mesmo bloco: remover backdrop/aside e chamada antiga a useModalFocus, montar o SidePanel comum, preservar audienceId/canManage e eventos close/use/delete do componente de Campanhas, pôr conteúdo/cabeçalho/rodapé nos slots correspondentes e abrir via ref no mounted. O botão Fechar usa close do SidePanel. O adaptador AudienceSidePanel não repassa o close inicial ao pai: só em afterLeave emite uma vez seu evento público close, depois de o SidePanel restaurar foco; assim o pai existente pode desmontar por v-if sem listeners adicionais nem restauração antecipada. O foco inicial explícito do botão Fechar fica em data-autofocus. Não manter ponte da API antiga nem listener paralelo. Preservar a largura/layout e os alvos de Campanhas por teste; a API pública de AudienceSidePanel continua igual, enquanto a API interna do composable muda deliberadamente.

A matriz de não-regressão cobre AudienceSidePanel, PerformanceConversationsPanel, ReportDrilldownDrawer, TemplatePreviewDrawer, drawers de Conversas/Captain e Agentes: abrir, foco inicial único, Tab/Shift+Tab, diálogo aninhado, Escape único, clique fora, scroll lock, retorno ao gatilho em afterLeave, reabertura e limpeza no unmount. Uma spec isolada do composable não substitui integração.

### Ordem segura da extração

1. Criar os quatro destinos com a API genérica de etapas e o lifecycle descrito. Preservar props/eventos públicos dos consumidores; a exceção interna explícita é a API de useModalFocus, migrada atomicamente com SidePanel e AudienceSidePanel, conforme acima.
2. Atualizar todos os imports acima e procurar novamente o caminho antigo no app, nos specs e no alias de componentes.
3. Manter os specs do #993; mover JourneyStepper.spec.js e localeTag.spec.js para os destinos ou ajustar apenas seus imports. Cobrir switch e foco no destino e no SidePanel, com os consumidores da matriz acima.
4. Remover a cópia antiga somente quando o grep confirmar que não há import legítimo restante. Compatibilidade temporária só pode ser um re-export do destino comum, se um consumidor real fora do grep exigir; nunca um stub ou duas implementações divergentes.
5. Antes de F1/F2, conferir teclado, foco, locale, i18n do #993 e git diff da extração. Um erro nesta etapa bloqueia o F0 e não é contornado dentro dos agentes.

### Contrato das quatro etapas de Agentes

| Etapa | Rota | Estado mínimo para entrar | reachable e retorno |
|---|---|---|---|
| Escolha | agents/new | nenhum agente/thread; seleção do tipo é local até o backend aceitar a abertura | única etapa inicial; voltar à lista não cria rascunho. |
| Conte | agents/:agentId/build/tell | tipo escolhido e thread persistida na conta; a resposta da abertura devolve o id real | entrada em E1/E2; em E3/E4, “Quero mudar algo” também permite voltar para editar. A alteração preserva a mesma thread e dados, invalida o teste atual e devolve ao ciclo de Teste; não libera Ligue até novo teste válido. Sair em qualquer desses estados preserva o rascunho. |
| Teste | agents/:agentId/build/test | instrução fechada pelo backend; quatro respostas não substituem o contrato de estado | acessível quando a API indicar que pode testar; avançar exige resposta de teste concluída e digest atual. |
| Ligue | agents/:agentId/build/live | E4/teste válido atual, mais canal/horário/permissão quando aplicável | acessível somente pelo estado tipado; volta para Teste sem perder a thread. |
| Pronto | agents/:agentId/ready | resultado de Ligue: E4 desligado por enquanto ou E5/E6 após operação | tela de conclusão fora da barra; ao abrir o painel, o estado vem da API. |

AgentSteps recebe os quatro itens, marca current/reachable a partir de E1–E6 e dos campos de continuidade do B2, e nunca lê texto da conversa. A barra antiga de Campanhas continua com três itens; BuilderStepBar.vue continua sendo o fallback legado de duas fases até a remoção prevista em F10.

O retorno “Quero mudar algo” só é uma transição de edição de E3/E4 para Conte: ele não altera E5/E6, não transforma um agente no ar ou pausado em rascunho e não reabre o Construtor sem o leitor B3/BE-05. E5/E6 continuam sendo lidos e geridos por seus cartões/painéis próprios.

## 4. Token comum D4

O tema central está em theme/colors.js:106-226: colors.n expõe os tokens Radix semânticos; tailwind.config.js:212-220 injeta ...colors no tema. n-navy deve ser criado nesse mesmo espaço comum, com o valor aprovado por D4 (#0D2344), e consumido como bg-n-navy, text-n-navy ou equivalente Tailwind. Não criar variável, <style>, classe CSS local ou novo hexadecimal em componente.

O baseline fixo usado nesta revisão tem **18 ocorrências em 12 caminhos do dashboard**, quando buscado sem diferenciar maiúsculas/minúsculas. O inventário e a decisão são parte do check do F0:

| Caminho | Ocorrências | Classificação |
|---|---:|---|
| components-next/CampaignJourney/StepReview.vue | 1 | migrar para bg-n-navy; superfície de resumo. |
| components-next/CampaignResult/ResultKpiStrip.vue | 1 | migrar para bg-n-navy; faixa de KPI. |
| routes/dashboard/automacoes/components/AutomacaoHeroi.vue | 3 | migrar para n-navy; herói, texto de ação e ícone. |
| routes/dashboard/automacoes/components/AutomacaoSugestao.vue | 2 | migrar o início do gradiente e o texto do botão; manter o segundo stop somente se tiver token próprio. |
| routes/dashboard/automacoes/pages/AutomacaoConversaPage.vue | 1 | migrar para bg-n-navy. |
| routes/dashboard/campaigns/journey/AudiencesPage.vue | 1 | migrar para bg-n-navy. |
| routes/dashboard/campaigns/journey/CampaignJourneyPage.vue | 1 | migrar para bg-n-navy. |
| routes/dashboard/campaigns/metaAds/components/MetaAdsHero.vue | 2 | migrar superfície e texto para n-navy. |
| routes/dashboard/campaigns/metaAds/components/MetaAdsPanel.vue | 2 | migrar superfície e texto para n-navy. |
| routes/dashboard/campaigns/metaAds/components/MetaAdsSummary.vue | 2 | migrar os dois usos sólidos para n-navy. |
| routes/dashboard/campaigns/metaAds/metaAdsHelpers.js | 1 | migrar o stop do gradiente para a classe semântica e conferir geração/safelist. |
| routes/dashboard/campaigns/pages/EmailCampaignsPage.vue | 1 | migrar para bg-n-navy. |

A classificação acima inclui todos os 18 usos do dashboard no SHA. A busca case-insensitive deve ser `git grep -ni '#0d2344' -- app/javascript/dashboard` e continuar retornando 18 ocorrências em 12 caminhos. Há uma exceção pública separada em `app/views/public/tracked_link_kits/show.html.erb:9`, com `#0d2344` em CSS próprio da página pública de Links/QR; ela não usa Tailwind do dashboard, permanece fora de D4/F0 e não será tocada. Documentação, HTML do PRD e mockup/src também ficam fora por serem fontes/artefatos. O PRD cita quatro arquivos no texto da decisão (PRD.md:89), mas o inventário case-insensitive do dashboard e a exceção pública nomeada são a autoridade de escopo. A prova do PR deve mostrar o grep vazio do literal no dashboard após a migração e a exposição do token em theme/colors.js/Tailwind, sem substituir gradiente ou stop de cor sem conferir sua semântica.

## 5. Flag, entradas e contrato de rotas

### Estado atual

autonomia.routes.js:58-76 tem apenas ensureAutonomiaEnabled: ENV AUTONOMIA_AGENTS_ENABLED mais account.autonomia_agents_enabled, com carregamento da conta por contaDaRota. As rotas de agentes atuais estão em :115-139: lista, agents/new e painel com test|knowledge|channels|performance|tune|publish. autonomia.routes.spec.js:25-84 prova o guard antigo, mas ainda não prova a flag nova, o fallback nem a origem segura.

### Estado alvo, derivado do B2 e do PRD

O B2 define Config.redesign_enabled? como ENV AUTONOMIA_AGENTS_REDESIGN e account.internal_attributes['autonomia_agents_redesign'], default false nos dois níveis, exposto como booleano autonomia_agents_redesign_enabled (design/B2.md:64-89). Esse gate é aditivo: nunca substitui nem altera autonomia_agents_enabled.

| Nome | Caminho | Permissão | Com redesign ligado | Com redesign desligado |
|---|---|---|---|---|
| autonomia_agents_index | accounts/:accountId/agents | ver | entrada nova | hub antigo |
| autonomia_agents_builder | accounts/:accountId/agents/new | editar | Escolha; inicia o fluxo novo após escolha | builder antigo |
| autonomia_agent_build | accounts/:accountId/agents/:agentId/build/:step(tell|test|live) | editar | Conte/Teste/Ligue | tell → tune, test → test, live → publish |
| autonomia_agent_ready | accounts/:accountId/agents/:agentId/ready | editar | Pronto | → performance |
| autonomia_agent_panel | accounts/:accountId/agents/:agentId/:tab(performance|test|knowledge|channels|tune|tools|publish)? | ver | casca nova; padrão performance; publish → build/live | casca antiga; preserva tabs existentes |
| autonomia_agent_panel_legacy | accounts/:accountId/agents/:agentId/legacy/:tab(test|tune|performance)? | ver | entrada de compatibilidade nomeada para `AgentPanelPage`/`PanelTune`, disponível durante o staging mesmo com a flag nova ligada | painel legado; preserva tabs existentes |
| *(nenhuma rota de conexão em Agentes)* | — | — | Agentes apenas leem/associam canais conectados | a conexão permanece em Canais |

Esse mapa é o contrato de PRD.md:656-674 e CA-GERAL-12 (PRD.md:866-870). A decisão de 07/10/2026 mantém a conexão de WhatsApp exclusivamente na área central de Canais: Agentes só leem canais já conectados/elegíveis e os associam ao agente. Não há rota de conexão, número, QR, token ou criação de caixa dentro de Agentes; quando não houver canal, a tela preserva o agente e oferece orientação/atalho para `settings_inbox_new` se a permissão permitir. O achado histórico F0-FINAL-01, escrito sob o contrato anterior, fica superado por essa decisão e não é um PASS retroativo.

Enquanto F2–F7 não estiverem implementadas, `autonomia_agent_panel_legacy` é a rota compatível explícita
para o painel existente. Ela usa a mesma conta/agente, uma aba nomeada (`tune` para E2m), os guards de
`autonomia_agents_enabled` e a resolução real do `AgentPanelPage`; sua disponibilidade não depende do gate
novo. O guard do redesign deve ramificar E2m antes de BE-05 e resolver esse nome, sem `href` arbitrário,
sem tela dummy, sem POST de thread e sem trocar o agente. Quando F7 entregar a tela nova de Ajustes, a rota
compatível poderá ser retirada em decisão própria; até lá, a flag nova preserva as rotas legadas para o
staging.

### Disposição do legado global de conexão

`InviteConnectionPage` e `autonomia_invite_connection` ficam formalmente fora do redesign de Agentes. São uma superfície global preexistente de convite/onboarding, com entrada pelo menu de perfil (`SidebarProfileMenu`), retorno de SSO (`Autonomia::Sso::Provisioner`) e recursos Rails de convite. Este F0 preserva esses chamadores, rota, autenticação e permissões sem refatorar SSO/auth ou remover onboarding; registra teste de não-regressão desses destinos. O bloco correspondente em `porques.md` permanece global; o Guia é regenerado das fontes, sem editar guideRouteRegistry à mão.

O kit, lista, Construtor, Ligue e painel novos de Agentes não importam essa página, não apontam para essa rota e não recebem `from`. Nenhum atalho de conexão do redesign usa menu/SSO/convite como fallback: usa exclusivamente `settings_inbox_new` na área central quando permitido. O inventário final deve provar ausência de referência a InviteConnectionPage/autonomia_invite_connection/from nas fontes próprias do redesign. Preservar a superfície global fora de Agentes evita regressão e não reintroduz conexão dentro da jornada nova.

Durante o staging, ativar só a entrada cujo componente real já está implementado e validado (primeiro a lista). As outras entradas mantêm os componentes/redirects legados funcionais da tabela, mesmo com a flag nova ligada, até suas respectivas fatias; não importar páginas futuras/dummy. Isso não é aceite visual das telas F2–F7. Retomadas guiadas passam pelo BE05; E2m usa somente o agente manual escopado. A tabela acima descreve o destino final, esta regra fixa a entrega gradual.

O guard deve:

- carregar a conta do accountId antes da decisão, aplicar o gate geral e então o gate do redesign;
- manter meta.permissions e as verificações de conta, agente e thread existentes; um agente/thread de outra conta não pode ser retomado por URL;
- preservar agentId, threadId e somente query params documentados ao desviar, sem criar thread, agente ou conexão no fallback;
- para E2m, desviar antes do leitor BE-05 para `autonomia_agent_panel_legacy`/`tune`; essa é a única exceção
  de retomada manual e não pode chamar `build_thread` nem cair na casca nova antes de F7;
- somente na retomada guiada E1–E4 por editor (nunca em E2m ou Abrir de viewer), hidratar a thread exata antes de renderizar o legado usando obrigatoriamente o leitor B3/BE-05 `GET agents/:agent_id/build_thread`, com a conta e o `agentId` da rota. O endpoint devolve a última thread `guided` do agente e o estado/id necessários ao store; exige `autonomia_manage`, responde 401 para só ver, 404 para outra conta, outro agente ou ausência e 422 `manual_mode` para agente manual. A entrada pode usar um `threadId` da projeção apenas como pista, mas na retomada guiada sempre confirma e hidrata pelo BE-05 antes de montar `PanelTune`; se a leitura não existir ou falhar, o deep link volta à lista/painel com aviso e fica bloqueado. Este caminho nunca chama `autonomiaBuildThreads.start` nem cria outra thread;
- no fallback tell → tune, test → test, live → publish e ready → performance, passar esse mesmo registro para a página antiga; F5, alternar a flag e o botão de continuar não podem abrir uma thread diferente;
- manter a associação de canais dentro de `autonomia_agent_panel`, lendo somente canais já conectados/elegíveis da mesma conta. A ausência de canal não abre uma rota de conexão em Agentes: preserva o agente e apresenta orientação/atalho para `settings_inbox_new`; a criação/configuração de WhatsApp permanece no fluxo central de Canais, com sua própria autenticação e permissões;
- escolher nova/antiga por conta sem esconder ou desligar o produto inteiro. AUTONOMIA_AGENTS_REDESIGN não substitui AUTONOMIA_AGENTS_ENABLED.

As specs de rota F0 precisam cobrir, no mínimo: ENV off; conta sem gate; conta com gate; duas contas com flags diferentes; deep link/F5 sem conta carregada; E2m ramificando antes de BE-05 para `autonomia_agent_panel_legacy`/`tune` com flag ligada e desligada; BE-05 com thread guiada do agente e ausência; recusa manual (`422 manual_mode`) testada na API, separada do caminho E2m que faz zero chamadas ao leitor; 401 de só ver, 404 de outro agente/conta; hidratação do store antes de `PanelTune`; `start` nunca chamado pela entrada nova; fallback de cada passo preservando o mesmo agente/thread; painel com canais já conectados, canal ocupado, nenhum canal elegível e atalho central condicionado à permissão; tools no painel; permissões de ver/editar. As specs existentes do legado devem permanecer sem alteração de comportamento.

## 6. F1 e F2: sequência concreta até uma tela real

F1 e F2 não podem depender de placeholders. Cada página abaixo só entra quando o endpoint e o estado que ela lê estiverem implementados e cobertos pelo B2/B3/B4.

### F1 — porta de entrada real

1. Implementar `AgentsListPage`, `AgentRow`, `AgentsSummaryChips`, `AgentsEmptyHero` e `AgentModelCard` em `agentes/pages` e `agentes/components`, reusando a lógica comprovada de `AgentsHubPage`/`AgentCard`.
2. Ligar a lista ao projection de BE-01: Clara externa, Lia de cotação, interno, rascunhos E1–E4, E5 atendendo e E6 pausado; contadores, canais, ocupação e estatísticas vêm da API, sem zeros ou estados inventados.
3. Implementar menu de item único, Guia e permissões. No perfil só ver, não mostrar criação, retomada, escrita, O que sabe, Onde atende ou Ajustes; “Abrir” leva ao leitor permitido conforme CA-LISTA-15.
4. Fechar loading, erro com tentativa, vazio com modelos, exclusão/pausa/religação e retomada no ponto salvo. A validação local deve provar o efeito na API/banco de teste isolado; não usar dados de cliente.
5. A primeira captura F1 já deve ser da tela real, sem `stateBar`, `MAP`, controles de simulação ou seletor de perfil do mockup.

Dependências: F0 completo + B2/BE-00, 01, 08, 11, 16, 27, 32. Se BE-01 ainda não devolver a projeção, F1 para; não reutiliza um card que invente a situação.

### F2 — Escolha e Conte reais

1. Criar `AgentBuildChoosePage`, `AgentModelCard` e `AgentSteps`, usando `AgentTypePicker` como fonte de tipos e `StepsBar` como peça comum. A seleção fica bloqueada até uma escolha; conta sem ajudante não mostra a opção interna; falha de `POST build_threads` não deixa rascunho órfão (`PRD.md:1399-1402`).
2. Criar `AgentBuildTellPage`, `BuildKnowsPanel` e `BuildMaterialsPanel`. Reusar `BuilderChat`, `ChatBubble`, `ChatComposer`, `MaterialDropzone` e `useFileDrop`; enviar/retentar pela API real de `build_threads`; renderizar `knows`, `suggested_links`, estados do material e respostas fora de ordem vindos do backend.
3. Implementar a retomada guiada E1–E4 pelo `agentId` usando BE-05 antes do fallback legado; hidratar o store, preservar a thread e proibir `start`. E2m ramifica antes, só lê o agente manual da conta e monta Ajustes legados sem leitor/thread/job; Abrir de viewer só lê painel. A exceção é testada separadamente. O caminho de saída vale em qualquer estado. Depois de quatro respostas, o campo continua disponível; só o contrato de estado libera Teste. Material `pending`/`failed` não é marcado pronto pelo front nem trava o que o PRD permite.
4. Usar `sources/reusable|copy` quando B4 expuser esses endpoints: um material pronto permite atalho; dois ou mais abrem escolha; outra conta retorna 404. Não chamar `inviteConnection` como substituto.
5. Fechar a rota `agents/:agentId/build/tell` com o guard e a entrada definidos no F0. A implementação passa a F3 só depois de a jornada Conte → Teste conservar thread, rascunho, nome e materiais numa releitura real.

Dependências: F0 + B3/BE-05 (leitor e retomada), B3 (criação), B4/BE-02 (material de outro agente), B2/BE-08 e BE-27. A frase “fica guardado” só pode ser apresentada quando o estado e o reaper do B1 sustentarem isso.

### Depois de F2

F3 implementa `AgentTestPhone`, `AgentBuildGoLivePage`, `ChannelRadioList`, `GoLiveSummary` e `AgentReadyPage`, incluindo `ready` e o teste assíncrono. F4 cria `AgentPanelShell` e o resumo; F5–F8 fecham leitores de materiais, canais, ajustes, ferramentas, Lia, interno e conversa, conforme a tabela do Apêndice A (`PRD.md:1403-1416`). Nenhuma dessas fatias pode ser considerada pronta por existir no bundle: precisa de captura e cenário real.

## 7. Playwright, fixtures e evidência local

F0 cria a infraestrutura, não a aprovação visual. A dependência @axe-core/playwright precisa ser declarada no pacote/lockfile do projeto Playwright antes de o helper ser considerado executável; hoje ela não está declarada. O comando que chama o helper deve falhar se o módulo ou a configuração estiverem ausentes.

### Configurações e barreiras

- tests/playwright/agents.config.ts: base URL obrigatoriamente loopback, locale pt-BR, timezone America/Sao_Paulo, browser isolado, autenticação sintética local e dados de teste locais;
- tests/playwright/agents-prod.config.ts: apenas planejado para T23, somente leitura, com host aprovado e bloqueio padrão de POST/PATCH/PUT/DELETE, seed, publish e connect. Sua implementação, autenticação, host e qualquer segredo de produção estão fora deste F0 e exigem autorização específica; não executar nem preparar credencial real;
- tests/playwright/helpers/expectNoSeriousA11y.ts (ou destino equivalente do setup existente): usa @axe-core/playwright, falha em violações serious/critical e é chamado em cada família, viewport e tema;
- bloqueio de rede: host externo falha fechado; page.route não pode fulfill payload de sucesso. Pode apenas simular uma falha explicitamente nomeada do transporte/provedor local (por exemplo, provider_error) ou aplicar um atraso controlado à resposta do backend local (transport_delay) para observar loading real. Vazio, sucesso, lista, estado, persistência e loading sem falha continuam vindo do banco/API local;
- fixtures/seed locais: IDs criados no setup e cleanup ao final; nenhuma fixture lê segredo, conta de cliente ou produção.

### Identidades e ciclo de persistência

| Fixture | Escopo e permissão | Uso |
|---|---|---|
| editor_a | conta A, autonomia_manage, sem SuperAdmin | cria, edita, testa, pausa e retoma no fluxo externo. |
| viewer_a | conta A, autonomia_view ou função personalizada equivalente, sem manage | lê, testa dentro da exceção documentada e recebe 401/ausência nos controles de escrita. |
| account_admin_a | administrador da conta A | confere canais conectados/elegíveis, agenda/ocupação e o atalho para `settings_inbox_new`. |
| super_admin | currentUser.type === SuperAdmin, conta A | confere Ferramentas; não ganha Ferramentas na Lia por isso. |
| viewer_b | conta B, sem acesso à conta A | prova que lista, agente, thread, material e canal de A retornam 404/401 conforme o contrato. |

A autenticação local usa o mecanismo real do repositório (credencial sintética, POST /auth/sign_in, cookies/sessão), sem copiar cookies pessoais. Cada mutação exige: resposta HTTP esperada; GET posterior do recurso; releitura da tela após reload; asserção do efeito e do escopo. O teardown remove apenas IDs criados pelo job. Sucesso e vazio são contas/recursos reais do banco local; o vazio é um GET de uma conta sem agentes, e loading é atraso nomeado da resposta local, não payload fabricado.

## 8. Matriz executável das 13 famílias

O arquivo-base dos cenários visuais é `tests/playwright/tests/agents/visual.spec.ts`, conforme PRD §11.6; cada `caso` abaixo é um `test.describe`/`test` identificável nesse arquivo, não uma promessa de que ele já existe. Para cada estado listado, a captura obrigatória é exatamente `<família>@<estado>.1440.claro.png`, `<família>@<estado>.1440.escuro.png`, `<família>@<estado>.400.claro.png` e `<família>@<estado>.400.escuro.png`. A imagem sozinha nunca fecha o cenário: cada caso precisa de leitor, perfil, pós-condição e registro `PASS`, `FAIL` ou `BLOCKED`.

| Família | Todos os estados normativos e nomes dos casos/capturas | Perfil, ação e leitor real | Pós-condição verificável |
|---|---|---|---|
| F01 Lista | `normal`, `carregando`, `erro`, `vazio`, `so-ver` → `F01-lista-normal`, `F01-lista-carregando`, `F01-lista-erro`, `F01-lista-vazio`, `F01-lista-so-ver` | `editor_a`, `viewer_a`, `viewer_b`; GET local de agentes, `transport_delay` para carregamento e falha nomeada para erro | GET posterior confirma escopo A/B; vazio é coleção vazia do banco local; só ver não vê criar nem escrever. |
| F02 Cartões e retomada | Clara externa (`clara`), Lia (`lia-cotacao`), interno (`interno`), E1 (`rascunho-e1`), E2 (`rascunho-e2`), E2m manual (`rascunho-e2m`), retomada (`retomada-e1`, `retomada-e2`, `retomada-e3`, `retomada-e4`), abandono em Conte/Teste/Ligue (`abandono-conte`, `abandono-teste`, `abandono-ligue`), E4 pronto (`pronto-para-ligar`), E5 atendendo (`atendendo`), E6 pausado (`pausado`), canais ocupados (`canais-ocupados`), sem canal (`sem-canal`), só ver E1–E4 (`so-ver-e1`, `so-ver-e2`, `so-ver-e3`, `so-ver-e4`) | `editor_a` e `viewer_a`; projection da lista, GET BE-05 ao continuar guiado; E2m faz zero GET BE-05 e usa painel manual escopado; rota de Abrir para só ver; nenhum texto infere estado | Continuar retoma o mesmo passo/thread para editor; Abrir só lê para viewer; sair guarda E1–E4; E5 nunca vira “Falta terminar”; interno não inventa uso; canal/ausência permanecem após reload. |
| F03 Pausar, religar e excluir | `atendendo-pausa`, `confirmar-pausa`, `pausado-equipe`, `religar`, `excluir-rascunho`, `excluir-externo`, `excluir-interno` | `editor_a`, `account_admin_a`; PATCH/DELETE locais, confirmação e GET do agente/canais | Persistência, vínculo e devolução à equipe são relidos; `viewer_a` recebe recusa e não altera nada. |
| F04 Escolha e início | Seis modelos externos (`seis-modelos`), Ajudar minha equipe (`escolha-interno`), Outro trabalho (`escolha-outro`), sem escolha (`sem-escolha-bloqueada`), escolha marcada (`escolha-selecionada`), conta sem ajudante (`sem-ajudante`), E1x sem rascunho (`e1x-sem-rascunho`) e nova tentativa (`e1x-tentar-novamente`) | `editor_a`, contas com e sem painel do ajudante; POST real de início, erro nomeado e retry previsto | Só um cartão fica marcado; Continuar bloqueia sem escolha; opção interna some quando indisponível; E1x não cria rascunho e retry não duplica. |
| F05 Conte, respostas e materiais | quatro respostas (`quatro-respostas`), chip sugerido (`resposta-sugerida`), fora de ordem (`respostas-fora-de-ordem`), nome (`nome`), link sugerido (`link-sugerido`), imagens (`imagens`), arquivos (`arquivos`), material enviando (`material-enviando`), lendo (`material-lendo`), não deu para ler (`material-falhou`), precisa de outro arquivo (`material-precisa-outro`), ainda não conferido (`material-pendente`), não é sobre o negócio (`material-fora-do-negocio`), parece não ser (`material-incerto`), pronto (`material-pronto`), campo após quatro (`campo-pos-quatro`), um material reutilizável (`reuso-um`), dois ou mais (`reuso-varios`), nenhum (`reuso-vazio`), arquivado excluído (`reuso-sem-arquivado`), outra conta 404 (`reuso-outra-conta`) | `editor_a`, thread real; `build_threads`, `builder_images`, BE-26 `knows`, BE-09 `suggested_links`, BE-27 sources e B4 reusable/copy | GET/reload conserva respostas, nome, materiais e escolha; teste só libera com quatro respostas; falha/pendência segue regra do PRD; cópia fora da conta retorna 404; lista nunca traz arquivado. |
| F06 Conte em espera, erro e limite | Pensando (`pensando`), Erro ao enviar (`erro-ao-enviar`), Não salvou 422 `error_fields` (`nao-salvou`), Demorando após janela (`demorando`), Ainda respondendo 409 (`ainda-respondendo`), Muitas mensagens 429 (`muitas-mensagens`) | `editor_a`; API local real, `transport_delay` somente para observar processing/stale, `provider_error` nomeado, 422/409/429 reais do ambiente isolado | Pensando preserva texto; erro permite reenviar o mesmo texto; Não salvou diz que nada foi gravado e marca o campo; Ainda respondendo bloqueia campo/envio e não duplica; Demorando só aparece após `STALE_PROCESSING_AFTER`; Muitas mensagens bloqueia por 60 s e preserva texto. |
| F07 Teste da instrução | normal (`teste-normal`), apresentação alterada (`apresentacao-alterada`), ainda montando (`ainda-montando`), não respondeu (`nao-respondeu`), demorando (`teste-demorando`), muitas mensagens (`teste-muitas-mensagens`), invalidado por material (`material-invalida-teste`), ferramenta que grava (`ferramenta-grava`) | `editor_a` e `viewer_a`; POST 202 + polling local, PATCH de nome/primeira mensagem, material e ferramenta conforme permissão | Só resposta concluída atual libera continuar; alteração limpa/recomeça teste; erro, demora, limite e montagem não contam; teste viewer não roda ferramenta POST; gravação local só ocorre para editor. |
| F08 Lia e ajudante | Lia normal (`lia-teste`), Lia com `skipped_tools` (`lia-aviso-cotacao`), interno conversa-exemplo (`interno-exemplo`), interno resposta válida (`interno-teste-valido`), viewer no teste (`interno-viewer`) | `editor_a`, `viewer_a`; GET tipo/quote branches/copilot e POST teste permitido; sem chamada de cotação real para Lia | Lia mostra aviso só com `skipped_tools`, zero ToolRun/job; interno não mostra passagem nem métricas falsas; uma resposta concluída conta para ligar; controle viewer respeita D17. |
| F09 Ligue e recusas | normal com canal livre (`ligue-normal`), ocupados (`canais-ocupados`), nenhum livre (`sem-canal-livre`), falha ao ligar (`falhou-ao-ligar`), canal sem horário (`canal-sem-horario`), teste ausente (`sem-teste`), instrução ausente (`sem-instrucao`), material novo (`material-novo`), editor sem administrador (`editor-sem-admin`), interno sem canal (`interno-sem-canal`) | `account_admin_a`, `editor_a`, `viewer_a`; GET channels/agenda/agent, publish local e recusas 401/422; `viewer_a` nunca escreve | Falha é atômica e mantém rascunho/desligado; sem canal preserva o agente e orienta para Canais, com atalho para `settings_inbox_new` quando permitido; material/teste/instrução levam ao passo que falta; interno liga sem escolher canal, mas exige teste. |
| F10 Pronto e desligado | sucesso externo (`pronto-externo`), sucesso interno (`pronto-interno`), deixar desligado (`pronto-desligado`) | `editor_a`; publish/leave-off local, GET agent/state e reload | Sucesso confirma E5 e cartão Atendendo; interno oferece conversa local; deixar desligado preserva E4, cartão Pronto para ligar e retomada; nenhum efeito de produção. |
| F11 Painel Clara e gestão | Como está indo dados (`painel-dados`), carregando (`painel-carregando`), erro (`painel-erro`), sem conversas (`painel-sem-conversas`); Testar normal (`painel-teste-normal`), montagem incompleta (`painel-teste-montando`), não respondeu (`painel-teste-erro`), ferramenta pulada por viewer (`painel-teste-viewer-tool`); O que sabe normal (`sabendo-normal`), enviando (`sabendo-enviando`), lendo (`sabendo-lendo`), não deu para ler (`sabendo-nao-deu`), precisa de outro arquivo (`sabendo-precisa-outro`), ainda não conferido (`sabendo-nao-conferido`), não é sobre o negócio (`sabendo-nao-negocio`), parece não ser (`sabendo-incerto`), pronto (`sabendo-pronto`), vazio (`sabendo-vazio`), limite 30 (`sabendo-limite`); Onde atende normal (`onde-normal`), sem canal (`onde-sem-canal`), falha (`onde-falhou`), editor sem admin (`onde-sem-admin`), pausado (`onde-pausado`); Ajustes normal (`ajustes-normal`), versões (`ajustes-versoes`), sem ajudante (`ajustes-sem-ajudante`), interno (`ajustes-interno`), os dois (`ajustes-os-dois`), sem versão guiada (`ajustes-sem-guiada`), rascunho testado (`ajustes-rascunho-testado`), manual (`ajustes-manual`), retorno ao guiado (`ajustes-voltar-guiado`), vários canais sem horário (`ajustes-varios-sem-horario`); Ferramentas SuperAdmin (`ferramentas-super-admin`), ausência para demais (`ferramentas-sem-super-admin`), ausência na Lia (`ferramentas-lia-oculta`) | `editor_a`, `viewer_a`, `account_admin_a`, `super_admin`; o caso `ferramentas-super-admin` usa explicitamente SuperAdmin e os casos de ausência usam editor/viewer/Lia; GET analytics/sources/channels/settings/tools, mutações com GET/reload, gaveta com escopo | Só ver vê apenas Como está indo/Testar; SuperAdmin vê Ferramentas e os demais recebem 401/ausência; Lia nunca vê Ferramentas; materiais, versões, canais e ajustes exibem o estado/API correspondente, sem controles sem leitor. |
| F12 Painel Lia e interno | Lia Como está indo (`lia-painel-resumo`), Testar (`lia-painel-teste`), O que cota (`lia-o-que-cota`), Ajustes (`lia-ajustes`), escolhas de nome/foto (`lia-nome-foto`), horário informado (`lia-horario-informado`), jeito de cotar (`lia-jeito-cotar`), alvo (`lia-alvo`), Para quem responde (`lia-publico`), Quando atende (`lia-janela`), Lia sem materiais/ferramentas (`lia-abas-ocultas`); interno cartão (`interno-cartao`), Como está indo (`interno-resumo`), sem canal/horário (`interno-sem-atendimento`) | `editor_a`, `viewer_a`, `account_admin_a`, inclusive `super_admin` para provar que Lia não recebe Ferramentas; GET quote choices/copilot, salvar e reler cada escolha | Lia mostra ramos/aviso Hub2You e controles próprios, sem O que sabe/Ferramentas; interno mostra conversa/Ver numa conversa, sem uso falso, canal, horário ou passagem genérica. |
| F13 Conversa e gavetas | ajudante (`conversa-ajudante`), vazio sem ajudante (`conversa-vazia`), nota privada (`conversa-nota`), menu (`conversa-menu`), cinco motivos (`conversa-cinco-motivos`), resposta errada (`conversa-resposta-errada`), gaveta com itens (`gaveta-itens`), gaveta vazia (`gaveta-vazia`), gaveta de respostas erradas (`gaveta-respostas-erradas`) | `editor_a`/`viewer_a`; GET conversa/drawer, POST report/note conforme permissão, isolamento entre contas, foco do SidePanel | Nota não vai ao cliente; report só conclui após motivo; drawer mostra motivo/resposta/Ensinar e respeita escopo; viewer só escreve nas exceções do PRD; foco, Escape e retorno funcionam. |

Os identificadores de estado acima são parte do contrato do F0 e foram extraídos do aceite-telas-reais.md:50-161 e PRD.md:1181-1195. Não é permitido substituir uma lista por `error`, `view`, `fail` ou outro nome genérico. Cada escrita termina com resposta HTTP, GET do recurso e reload; loading normal, vazio e sucesso nunca são payload de `page.route`. Se um caso não tiver leitor real, ele fica `BLOCKED` e a fatia para; não se cria fixture, stub ou sucesso cenográfico para preencher a tabela.

## 9. Guia e Central: mapa que precisa fechar com as rotas

F0 deve registrar, antes da primeira tela nova, a seguinte cadeia para cada entrada nova:

| Rota | Explicação fonte | Saída gerada | Central |
|---|---|---|---|
| autonomia_agents_index e autonomia_agents_builder | bloco em lib/operator_guide/porques.md para criar/retomar | guia-produto.md, guideRouteRegistry.js, destaque de “Criar agente com IA” | artigo da lista e criação, ou mapa.fora justificado |
| autonomia_agent_build e autonomia_agent_ready | blocos Escolha/Conte/Teste/Ligue/Pronto | mesmos artefatos gerados | artigos da jornada e retomada |
| autonomia_agent_panel | blocos do painel, canais já conectados e atalho para Canais | activeOn dos nomes de rota do painel | capítulo 11 e artigo de associação de canal; a conexão fica no mapa central de Canais |
| tools e conversa | bloco restrito a SuperAdmin/conversa | saída gerada com gates | artigo ou mapa.fora por não ser rota de usuário comum |

A implementação de F0 acrescenta/ajusta somente porques.md e fontes autorizadas; executa pnpm guia:build, pnpm guia:check e pnpm central:check no fechamento. lib/operator_guide/guia-produto.md e app/javascript/dashboard/helper/guideRouteRegistry.js nunca são editados à mão. O conteúdo específico das telas pode ser refinado em F1–F9, mas nenhuma rota nova entra sem explicação ou mapa.fora justificado.

## 10. Critérios de parada e estado deste desenho

- DRAFT — não aprovado permanece até a checagem independente deste bloco. Este documento não inicia implementação.
- Se B2 não entregar o booleano, a projeção ou os estados documentados, ou se B3/BE-05 não entregar `GET agents/:agent_id/build_thread` com escopo, 401/404 e hidratação do store, parar antes das páginas e registrar a lacuna; não criar resposta de conveniência nem chamar `start`.
- Se uma extração D9 quebrar um import, teclado, foco, locale, lifecycle do SidePanel ou spec do #993, parar a extração e corrigir sua causa antes de seguir; não abrir uma cópia local da peça.
- Se o grep case-insensitive do dashboard não coincidir com os 12 caminhos/18 usos acima, ou se a exceção pública `tracked_link_kits/show.html.erb:9` mudar de escopo, registrar a diferença antes de trocar classes; não esconder a divergência com CSS local nem tocar a página pública neste F0.
- Se CampaignOverviewPage não puder migrar para `dashboard/helper/localeTag.js` por incompatibilidade real, parar a extração com a prova e a spec de paridade; não deixar uma duplicata sem decisão.
- Se o SidePanel e o trap não mantiverem a ownership única de Escape, scroll, gatilho, foco inicial, restauração e Tab/Shift+Tab, ou se AudienceSidePanel instalar listener próprio, parar e corrigir o lifecycle antes das telas.
- Se @axe-core/playwright, loopback, bloqueio de métodos ou fixture de autenticação não forem executáveis no config local, o gate de telas fica bloqueado. O config de produção continua apenas planejado/read-only e sem autenticação/secrets até autorização específica.
- Se qualquer controle não tiver leitor no código/API real, removê-lo ou bloquear a fatia conforme a matriz controle → leitor (PRD.md:379-413); não entregar botão decorativo.
- O aceite só fecha com telas reais em quatro combinações de viewport/tema, perfis e 13 famílias, sem tela branca/corte, a11y sem serious/critical, jornada compreensível para pessoa leiga e aprovação explícita do Rodrigo. Merge, fila, deploy e produção continuam sob a sessão Automação e OK específico do Rodrigo.

**Conclusão do F0:** o mapa executável foi corrigido com os contratos de etapa, thread, origem, token, locale, foco, fixtures, leitores, Guia e Central. O estado continua DRAFT — não aprovado; aguardando revisão. A próxima ação autorizável é a checagem independente; só depois dela e dos contratos B2 fechados começa o código F0.
