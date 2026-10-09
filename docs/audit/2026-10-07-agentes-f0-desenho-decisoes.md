# F0 — decisões e causas da correção do desenho

**Estado: DRAFT — não aprovado; aguardando revisão final única.**

Este registro consolida a revisão normal de produto/testes, a revisão normal técnica e a correção final única de F0. A checagem independente encontrou três residuais de produto e cinco técnicos no desenho de 245 linhas, SHA-256 `3dd44e652b1f14deefb8a071b1cf5db9c8cd2e7a8e3685c418c7e3be3d1978e4`; a causa raiz está em `docs/audit/2026-10-07-agentes-f0-checagem-causa-raiz.md`. A referência de código das revisões foi o baseline 6242e31695fd1c6b8b088f2fcb819c027fc5083c.

Não houve código de produto, teste, build, navegador, M2, banco, produção, autenticação real, merge, fila ou deploy. A correção foi limitada ao desenho F0 e a este audit. O desenho permanece DRAFT até a checagem independente.

## Causas consolidadas

| Grupo | Achados | Causa | Decisão de correção |
|---|---|---|---|
| Evidência real | F0-TEST-01, F0-TEST-02, F0-TEST-03, F0-SEC-07, final-produto-01 | A infraestrutura estava descrita como uma galeria visual: não separava estado vindo da API local, falha/atraso de transporte, identidade/permissão, persistência e pós-condição. | F0 exige sucesso, vazio, loading normal e persistência do banco/API local; page.route só nomeia falha/provedor local ou atraso transport_delay. Fixtures têm identidades, conta B, autenticação sintética local, cleanup e GET/reload após cada escrita. A matriz agora enumera todos os estados das 14 famílias, cada caso em `tests/playwright/tests/agents/visual.spec.ts`, perfil, leitor, pós-condição e quatro capturas. |
| Continuidade da thread | F0-ROUTE-01, F0-TEC-02, final-produto-03, final-técnico-02 | Preservar threadId na URL não basta: o painel antigo não hidrata o store e pode executar start, criando uma nova thread. A decisão anterior também transferia o leitor para B2, embora ele seja BE-05/B3. | F0 exige o leitor B3/BE-05 `GET agents/:agent_id/build_thread`, última thread guiada escopada por conta/agente, 401 sem `autonomia_manage`, 404 para outro agente/conta/ausência, 422 `manual_mode` para manual e hidratação do store antes de `PanelTune`; `start` é proibido no fallback. Os quatro desvios, F5 e F5 sem leitor entram nas specs. |
| Etapas da jornada | F0-UX-01, F0-TEC-01 | A extração técnica tinha um componente rígido de três etapas e o desenho não fechava o contrato de quatro etapas do produto. | StepsBar recebe lista/rótulos genéricos; adaptador Campanhas conserva 3; AgentSteps define 4 (Escolha, Conte, Teste, Ligue). Pronto é conclusão em ready, não quinta etapa. current/reachable/evento/ARIA/teclado permanecem cobertos nos dois contratos. |
| Origem da conexão | F0-SEC-03, final-técnico-01 | “Origem interna segura” não definia o path sem query, a origem canônica nem a prova de resolução real do router. | O path é `accounts/:accountId/agents/connect-whatsapp` e a leitura é `to.query.from`. Uma única representação de `from` é produzida por `router.resolve` a partir da rota nomeada do painel com conta, agente e `channel_ids`; o destino resolve e aplica allowlist explícita. Valor manual/externo, javascript, rota desconhecida, conta/agente/canais divergentes são recusados. |
| Token semântico | F0-D4-01, F0-TEC-04, final-técnico-03 | O PRD dizia quatro arquivos, o baseline tinha 18 ocorrências em 12 caminhos do dashboard e uma busca sensível à caixa ocultava um CSS público equivalente. | F0 mantém os 12 caminhos/18 usos do dashboard por grep case-insensitive. `tracked_link_kits/show.html.erb:9` é exceção pública nomeada, CSS próprio sem Tailwind do dashboard e fora do F0; não será tocado. Gradientes só mudam após classificação do stop e conferência de safelist. |
| Locale compartilhado | F0-TEC-05, final-técnico-04 | A lista de imports não capturava a implementação local de CampaignOverviewPage e a decisão “migrar ou exceção” deixava o contrato aberto. | F0 enumera os 15 consumidores, spec e scheduleTime e exige migrar/remover a cópia de CampaignOverviewPage para `dashboard/helper/localeTag.js`. Incompatibilidade real interrompe a extração com prova e spec de paridade; não há exceção presumida. |
| Foco e gaveta comum | F0-UX-02, F0-TEC-06, final-técnico-05 | O composable de foco podia disputar Escape, gatilho, restauração e scroll com o SidePanel; faltava definir foco inicial e limpeza. | SidePanel é dono de open/close, Escape, clique fora, scroll, captura do gatilho, foco inicial após afterEnter e restauração após afterLeave. O composable só ativa/desativa explicitamente o trap Tab/Shift+Tab, sem fechar ou restaurar; AudienceSidePanel usa o adaptador padrão sem listeners próprios. |
| Guia e Central | F0-DOC-01, F0-TEC-08 | O mapa de rotas não estava ligado aos arquivos fonte de explicação nem aos geradores/checks obrigatórios. | F0 agora exige rota → porques.md → artefatos gerados → artigo/Central, guia:build, guia:check e central:check. Arquivos gerados não são editados manualmente. |
| Axe executável | F0-TEST-04, F0-SEC-07 | O helper foi nomeado sem dependência travada, comando ou barreira de destino/método. | F0 exige @axe-core/playwright no pacote/lockfile, helper chamado por família/tema/viewport, config local loopback e config de produção somente planejado/read-only, com host aprovado e bloqueio de escritas. Nenhuma autenticação/secreto de produção é preparado nesta etapa. |

## Registro dos 17 achados

A tabela mantém todos os IDs das duas revisões; quando há a mesma causa, a decisão consolidada acima é a correção comum.

| ID | Lente | Severidade | Prova principal | Resultado na correção |
|---|---|---|---|---|
| F0-TEST-01 | produto/testes | alta | F0 anterior:126-136; aceite-telas-reais.md:13-15,65-88 | Corrigido: page.route não fabrica sucesso, vazio ou loading normal; atraso transport_delay e erro provider_error são nomeados. |
| F0-TEST-02 | produto/testes | alta | F0 anterior:130-147; helpers reais de relationships:9-62 | Corrigido: editor, viewer, administrador, SuperAdmin, conta B, auth sintética, IDs e cleanup explícitos. |
| F0-TEST-03 | produto/testes | alta | F0 anterior:128-147; aceite-telas-reais.md:46-189; PRD.md:1179-1202 | Corrigido: matriz F01–F14 com perfil, percurso, leitor, persistência e quatro nomes de captura. |
| F0-ROUTE-01 | produto/testes | alta | F0 anterior:79-96; buildThreads.js:37-39; autonomiaBuildThreads.js:165-176 | Corrigido: thread exata por entrada/projeção ou resolver real; sem start quando não há leitor escopado. |
| F0-UX-01 | produto/UX | média | F0 anterior:46-59; BuilderStepBar.vue:5-9,35-57; aceite-telas-reais.md:38-44 | Corrigido: contrato de quatro etapas. Pronto ficou explicitamente fora da barra. |
| F0-TEST-04 | produto/testes | média | F0 anterior:130-136; tests/playwright/package.json e lockfiles | Corrigido no plano: dependência e comando de axe passam a ser requisito de implementação/verificação. |
| F0-D4-01 | produto/testes | média | F0 anterior:61-67; baseline: git grep com 18 usos/12 caminhos | Corrigido: inventário completo e classificação por caminho. |
| F0-DOC-01 | produto/testes | média | F0 anterior:5-16,100-120; PRD.md:689-692 | Corrigido: cadeia Guia/Central e checks oficiais adicionados. |
| F0-UX-02 | produto/UX | média | SidePanel.vue:47-87; F0 anterior:49-50 | Corrigido: lifecycle e matriz de não-regressão do SidePanel comum. |
| F0-TEC-01 | técnica | P1 | JourneyStepper.vue:8-18; JourneyStepper.spec.js:27-72; BuilderStepBar.vue | Consolidado com UX-01: StepsBar genérico, adapter Campanhas 3, AgentSteps 4. |
| F0-TEC-02 | técnica | P1 | AgentPanelPage.vue; PanelTune.vue:209-245 | Consolidado com ROUTE-01: hidratação real e scoped fallback antes de renderizar/usar Tune. |
| F0-SEC-03 | técnica/segurança | P1 | autonomia.routes.js:115-139; contrato connect-whatsapp do PRD | Corrigido: static route + router.resolve real, from canônico nomeado e rejeições por escopo. |
| F0-TEC-04 | técnica | P2 | baseline fixo: 18 ocorrências em 12 caminhos | Consolidado com D4-01: lista explícita e sem troca cega. |
| F0-TEC-05 | técnica | P2 | imports do baseline e CampaignOverviewPage.vue:47-58 | Corrigido: todos os imports, spec e duplicata local enumerados. |
| F0-TEC-06 | técnica | P1 | useModalFocus.js:6-65; SidePanel.vue:47-87,112-113 | Consolidado com UX-02: afterEnter/afterLeave e consumidores preservados. |
| F0-SEC-07 | técnica/segurança | P1 | configs Playwright; ausência de axe nos manifests | Consolidado com TEST-02/04: loopback, bloqueio de métodos, fixtures sintéticas e produção só leitura planejada. |
| F0-TEC-08 | técnica | P2 | guideRouteRegistry.js, Sidebar activeOn, PRD.md:689-692 | Consolidado com DOC-01: fontes, geração, check e Central no fechamento. |

## Causas da checagem final e decisões

A checagem final foi autorizada para este mesmo alvo depois do diagnóstico em `docs/audit/2026-10-07-agentes-f0-checagem-causa-raiz.md`. Os oito residuais abaixo foram corrigidos em um único bloco; não são uma nova revisão normal.

| Residual | Causa raiz | Decisão final no F0 |
|---|---|---|
| Matriz sem rastreabilidade de estado | As 14 linhas resumiam famílias e não ligavam cada estado normativo a um caso executável, leitor, pós-condição e captura. | A seção 8 enumera todos os estados do aceite/PRD, identifica `tests/playwright/tests/agents/visual.spec.ts` e casos `Fxx-*`, liga cada perfil/ação/leitor/pós-condição e define quatro arquivos por estado. `Não salvou` (422 `error_fields`), `Ainda respondendo` (409), falha ao ligar, editor sem administrador e código vencido têm casos próprios. |
| Ferramentas sem ator correto | `super_admin` existia apenas no catálogo geral, enquanto F11 listava editor/viewer/admin de conta. | F11 usa `super_admin` no caso positivo, verifica ausência/401 para os demais e registra a ausência da aba para Lia mesmo quando a sessão é SuperAdmin. |
| Retorno Conte bloqueado | `reachable` foi tratado como entrada E1/E2 e não como retorno de edição de E3/E4. | Conte é alcançável por “Quero mudar algo” em E3/E4; preserva thread/dados, invalida o teste atual e exige novo teste antes de Ligue. E5/E6 não são convertidos em “Falta terminar”. |
| Rota/origem ambígua | O desenho misturava query no `path` e deixava a representação de `from` aberta. | O path não tem query; o destino lê `to.query.from`. Um helper produz uma única representação serializada do `router.resolve` da rota nomeada do painel, com conta/agente/`channel_ids`; a allowlist resolve novamente e rejeita valores manuais ou fora do escopo. |
| Leitor de thread transferido ao bloco errado | “threadId ou resolver” deixava a implementação decidir e atribuía o contrato ao B2, embora BE-05 pertença ao B3. | F0 exige B3/BE-05 `GET agents/:agent_id/build_thread`, última thread guiada, scope conta/agente, 401/404 e hidratação antes de `PanelTune`; `start` é proibido no fallback. |
| Inventário navy sensível à caixa | A busca exata do dashboard não evidenciava o literal em caixa baixa da página pública. | O check é case-insensitive e continua em 18 usos/12 caminhos do dashboard. `app/views/public/tracked_link_kits/show.html.erb:9` é exceção pública, CSS próprio e fora do Tailwind/dashboard; fica registrada e não é tocada. |
| Locale duplicado opcional | A correção deixou “migrar ou justificar” sem uma incompatibilidade demonstrada. | `CampaignOverviewPage` migra obrigatoriamente para o helper comum e a cópia é removida. Incompatibilidade real para a extração e exige prova/spec de paridade antes de qualquer exceção. |
| Foco com ownership concorrente | SidePanel e `useModalFocus` poderiam tratar Escape, gatilho, restauração e scroll simultaneamente. | SidePanel possui open/close, Escape, clique fora, scroll, gatilho, foco inicial após `afterEnter` e restauração após `afterLeave`; o composable possui apenas trap Tab/Shift+Tab por `activate/deactivate` explícitos. AudienceSidePanel usa o adaptador padrão; unmount limpa sem segunda restauração. |

## Decisões factuais adicionais

- A jornada nova tem quatro itens na barra: Escolha, Conte, Teste e Ligue. Pronto é uma tela de conclusão. A fonte factual usada na correção é PRD.md:47,170,920 e mockup/src/kit.js:84.
- O estado vazio é um GET real de conta local sem agentes; sucesso e persistência vêm da API/banco local. Loading normal pode ser observado por atraso controlado de transporte chamado transport_delay; não é payload fabricado.
- O fallback antigo deve chamar o leitor B3/BE-05 da última thread guiada do agente, hidratar o store no escopo da conta/agente antes de mostrar ou usar o ajuste e nunca chamar `start`. Ausência, 401, 404 ou 422 `manual_mode` bloqueiam o caminho com aviso; nunca se cria outra thread para “parecer” retomada.
- A resolução da rota estática de conexão será provada pelo Vue Router real com path sem query; `from` é lido de `to.query.from`, produzido uma única vez por `router.resolve` da rota nomeada do painel e validado pela allowlist de conta, agente e `channel_ids`. O desenho não afirma prioridade artificial de ordem do array.
- O config de produção é apenas plano de leitura, com autorização pendente. Nenhum login, segredo, seed, write ou leitura de produção foi preparado ou executado.
- O token n-navy é comum em theme/colors.js/Tailwind. O grep case-insensitive do dashboard tem 12 caminhos/18 usos classificados. O CSS de `tracked_link_kits/show.html.erb` é uma exceção pública fora do dashboard/Tailwind e não entra neste F0.
- CampaignOverviewPage deve usar o helper comum de locale; incompatibilidade real interrompe a extração e exige paridade demonstrada.
- SidePanel é o único dono de abertura, fechamento, Escape, clique fora, scroll, gatilho, foco inicial e restauração; `useModalFocus` apenas prende Tab/Shift+Tab por ativação explícita.
- Guia e Central permanecem gerados pelos comandos oficiais. O desenho não autoriza edição manual dos artefatos gerados.

## Fechamento

A correção final atacou as causas, não apenas as linhas apontadas: matriz rastreável de estados, identidade/persistência, máquina de etapas, leitor B3/BE-05, origem de conexão, inventário visual case-insensitive, locale único, lifecycle com ownership, infraestrutura de axe e documentação gerada.

O desenho segue **DRAFT — não aprovado** até a revisão final única. Se ela encontrar qualquer erro, o processo para e retorna ao Rodrigo sem nova correção ou implementação F0; não há autorização para iniciar código, merge, fila, deploy ou produção.
