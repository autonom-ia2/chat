# F0 — revisão normal técnica e de segurança

**Estado:** revisão normal concluída; há achados concretos para correção. O desenho continua `DRAFT — não aprovado`.

**Alvo revisado:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`, SHA-256 `3ec82b9314644342f59f59e90e4ef6524521b778b47cd4b83489b2387668725c` (158 linhas).

**Referência do código:** baseline fixo `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. Essa referência não é uma afirmação sobre o `origin/main` atual.

**Método e limite:** leitura estática do F0, PRD D4/D9/§8/§10, código de rotas e componentes, configurações Playwright, catálogos e artefatos gerados. Não houve alteração de produto, build, RSpec, M2, banco, navegador ou produção. Esta revisão não aprova o protótipo nem autoriza implementação, merge, fila, deploy ou produção.

## Achados para correção

### F0-TEC-01 — P1 — o contrato de etapas não fecha três etapas de Campanhas e quatro de Agentes

**Evidência:** F0 §3, na linha 48, descreve `StepsBar` e diz que `AgentSteps` será um adaptador fino. O `components-next/CampaignJourney/JourneyStepper.vue:8-18` atual é rígido em `['AUDIENCE', 'MESSAGE', 'REVIEW']`; sua spec cobre somente três etapas (`CampaignJourney/specs/JourneyStepper.spec.js:27-72`). O legado `routes/dashboard/autonomia/components/builder/BuilderStepBar.vue` é rígido em duas etapas (`conversa`, `revisao`). O PRD §6.2 e o mockup exigem quatro etapas para a jornada nova: `Escolha`, `Conte`, `Teste`, `Ligue`.

**Causa:** o mapa nomeia a extração, mas não define a API que recebe a quantidade, os rótulos e o mapeamento de índice. Copiar o componente atual manteria três etapas; alterar o componente sem adapter poderia quebrar Campanhas.

**Correção exigida:** fechar `StepsBar` com contrato genérico de lista/rótulos, preservando o adapter de Campanhas com três etapas e criando `AgentSteps` com quatro etapas e suas chaves de i18n. Adicionar cobertura para os dois contratos, incluindo `current`, `reachable`, `aria-current`, teclado e evento `go`. Não mudar a jornada de Campanhas para quatro etapas.

### F0-TEC-02 — P1 — o fallback não prova a retomada da thread salva

**Evidência:** F0 §5, linhas 90-93, manda preservar `agentId` e `threadId` no desvio para o painel antigo. O `AgentPanelPage.vue` recebe apenas `agentId` e `tab`, carrega o agente e não hidrata `threadId` da query. Em `components/panel/PanelTune.vue:209-245`, `openReconverse` reseta o estado de threads e `onReconverseSend` usa `autonomiaBuildThreads/getThread`; sem thread carregada, despacha `autonomiaBuildThreads/start`, criando uma nova thread.

**Causa:** preservar o identificador na URL não preserva a conversa se o painel legado não o resolve para o store antes da ação de retomada. Um deep link com a flag nova desligada pode abrir o painel antigo e iniciar uma conversa diferente.

**Correção exigida:** definir a hidratação/resolução da thread exata antes de renderizar o `tune`, validando conta, agente e thread, e garantir que a ação use esse registro. Cobrir `tell → tune`, `test → test`, `live → publish` e `ready → performance`, com F5 e isolamento entre contas. O fallback não pode criar agente, thread ou conexão.

### F0-SEC-03 — P1 — `connect-whatsapp` precisa de rota sem colisão e origem canônica

**Evidência:** a tabela de F0 (§5, linhas 83-86) lista o painel dinâmico antes da rota `accounts/:accountId/agents/connect-whatsapp?from=`. A rota atual em `autonomia.routes.js:115-139` usa `accounts/:accountId/agents/:agentId/:tab(...)`, portanto `connect-whatsapp` pode ser interpretado como `agentId` se a resolução/ordem do router for alterada ou se a rota estática não for registrada com prioridade. O F0 também não define os valores canônicos de `from` nem como o destino identifica o agente/canais para validar “mesma conta e canais do agente”.

**Causa:** “origem interna segura” descreve a intenção, mas não fecha o conjunto de origens aceitas nem a prova negativa da colisão entre rota estática e parâmetro dinâmico.

**Correção exigida:** registrar a rota estática com prioridade explícita e uma spec que prove que ela nunca cai no painel como `agentId`. Aceitar apenas tokens/rotas internas nomeadas que resolvam conta, agente e conjunto de canais; permitir a lista quando documentado; rejeitar URL externa, `javascript:`, conta/agente/canal incompatível e origem desconhecida, com retorno e aviso localizado. Manter permissões e a proibição de `InviteConnectionPage` ou conexão fictícia.

### F0-TEC-04 — P2 — o escopo efetivo do token D4 ainda não é revisável

**Evidência:** F0 §4, linhas 61-67, registra os quatro arquivos citados pelo PRD e manda inventariar ocorrências adicionais antes da troca. No baseline fixo, `git grep '#0D2344' -- app enterprise` encontra 18 ocorrências em 12 caminhos de produto, incluindo `CampaignJourney`, `CampaignResult`, Automação, Campanhas Meta Ads e Email Campaigns. O documento não lista esses caminhos nem decide quais usos pertencem à semântica D4.

**Causa:** a implementação ainda teria de decidir durante a edição se cada ocorrência migra ou fica fora. Isso deixa a mudança de tema aberta a substituição cega ou a escopos inconsistentes.

**Correção exigida:** registrar no desenho o inventário por arquivo e uso, a inclusão/exclusão de cada ocorrência e a prova esperada. Criar `n-navy` no `theme/colors.js` comum e conferir sua exposição no `tailwind.config.js`; não trocar hex de mockup, documentação ou gradiente sem a classificação semântica correspondente.

### F0-TEC-05 — P2 — o inventário de `localeTag` está incompleto e há implementação local paralela

**Evidência:** a tabela D9 do F0 (§3, linha 51) cita nomes genéricos e não fornece a lista verificável. Os imports produtivos encontrados no baseline são: `components-next/CampaignJourney/AudienceChannelBadges.vue`, `AudienceChannelSwitches.vue`, `AudienceColumns.vue`, `AudienceCompanies.vue`, `AudiencePeople.vue`, `AudienceSidePanel.vue`, `SmsJourneyMessage.vue`, `StepAudience.vue`, `StepReview.vue`, `TemplateVariableBindings.vue`, `WhatsAppApiMessage.vue`, `scheduleTime.js`, `routes/dashboard/campaigns/journey/AudiencesPage.vue`, `CampaignJourneyPage.vue` e `NewAudiencePage.vue`. Há ainda `components-next/CampaignJourney/specs/localeTag.spec.js`. `routes/dashboard/campaigns/journey/CampaignOverviewPage.vue:47-58` mantém uma implementação local de `localeTag` usando `replace('_', '-')` e `Intl`.

**Causa:** um grep apenas dos imports não detecta a implementação local, e a lista genérica não permite provar que todos os consumidores e specs foram migrados.

**Correção exigida:** enumerar todos os imports, specs e duplicatas locais; decidir explicitamente a migração de `CampaignOverviewPage`; exigir grep final sem implementação antiga e preservar os contratos de `pt_BR → pt-BR`, fallback `en`, `formatNumber` e `null → 0`.

### F0-TEC-06 — P1 — a integração de foco do `SidePanel` comum não está especificada

**Evidência:** F0 §3, linha 50, diz que o `SidePanel` comum deve usar `useModalFocus`. O composable atual (`useModalFocus.js:6-65`) instala o trap no `onMounted`, trabalha com o container naquele momento, registra Escape e devolve foco no unmount. O `components-next/side-panel/SidePanel.vue` começa com `isOpen = false`, monta o conteúdo com `v-if` dentro da transição, expõe `open/close`, faz foco e scroll lock em `onAfterEnter`, restaura foco em `close` e emite `afterLeave`. O consumidor atual `AudienceSidePanel.vue` tem outro ciclo de montagem e chama o composable no próprio painel.

**Causa:** aplicar o composable diretamente no `SidePanel` pode inicializar antes de existir o container, não prender Tab quando a gaveta abre, ou duplicar listeners, restauração de foco e scroll lock. O mapa não define a integração com `open`, `onAfterEnter`, `close` e `afterLeave` nem a compatibilidade da API pública.

**Correção exigida:** especificar o contrato de lifecycle ou um adapter do composable que inicie no `afterEnter` e finalize no `afterLeave`, preservando `open/close`, Escape, Tab/Shift+Tab, scroll lock e foco do gatilho. Criar spec do destino e da integração; não criar uma segunda implementação de gaveta.

### F0-SEC-07 — P1 — a infraestrutura Playwright não garante isolamento nem a11y executável

**Evidência:** F0 §7, linhas 126-136, nomeia `agents.config.ts`, `agents-prod.config.ts` e `expectNoSeriousA11y`, mas não define allowlist de host, bloqueio de métodos de escrita, fixture/auth sintética ou gate explícito para o config de leitura. Não há `@axe-core/playwright` nos manifests ou lockfiles atuais. O config geral `tests/playwright/playwright.config.ts` aceita `BASE_URL` arbitrário; `relationships.config.ts` é a referência que exige loopback, pt-BR e timezone, mas isso não se aplica automaticamente ao novo config.

**Causa:** “somente leitura” no nome do arquivo não é uma barreira técnica. Sem dependência travada, helper executável e restrição de destino/método, o gate pode não detectar violações ou pode apontar para um ambiente mutável.

**Correção exigida:** fixar `@axe-core/playwright` e o helper no setup aprovado; fazer o config local exigir loopback; fazer o config T23 aceitar somente host aprovado e bloquear por padrão `POST`, `PATCH`, `PUT`, `DELETE`, seed, publish e connect, sem segredos ou contas de cliente. Manter o fluxo local com fixture de autenticação e dados sintéticos separado de qualquer leitura de produção.

### F0-TEC-08 — P2 — as rotas novas não fecham o contrato dos artefatos gerados do Guia/Central

**Evidência:** o registry gerado atual (`app/javascript/dashboard/helper/guideRouteRegistry.js`) e os `activeOn` do `Sidebar.vue` conhecem somente `autonomia_agent_panel`, `autonomia_agents_builder` e `autonomia_agents_index`. F0 define novos nomes de rota e pede specs, mas não inclui no escopo/gate a atualização gerada, os blocos em `lib/operator_guide/porques.md` ou a execução de `pnpm guia:build`/`pnpm guia:check`.

**Causa:** as rotas poderiam funcionar sem aparecer no Guia/Central, contrariando PRD §8 e as regras de geração do repositório. Editar apenas o registry gerado também seria descartado na próxima geração.

**Correção exigida:** incluir na sequência do F0 a explicação/cobertura de cada rota em `porques.md`, a geração do registry/guia e `guia:check`, além da prova de `activeOn` para todas as novas entradas. Os arquivos gerados devem ser atualizados pela ferramenta, nunca manualmente.

## Pontos que passaram no cross-check

- O F0 proíbe explicitamente stub, mock, placeholder e fachada e exige API/estado real para F1/F2.
- O mapa mantém a distinção entre flag antiga e nova, preserva a intenção de conta/permissão e rejeita `InviteConnectionPage`/conexão falsa.
- O gate visual exige aplicação construída, quatro combinações de viewport/tema, perfis e 14 famílias; isso ainda não foi executado nesta revisão.

## Conclusão

Os achados acima precisam ser corrigidos no desenho e checados em uma rodada limitada antes de iniciar a implementação do F0. O F0 permanece `DRAFT — não aprovado`; não há aprovação visual, de merge, fila, deploy ou produção.
