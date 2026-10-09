# Confirmação limitada F0/F1 — ROTAS-01 e ROTAS-02

**Data:** 2026-10-07  
**Alvo:** snapshot31 `d974cedd1b5a1df30148ac5712f7ce1ff8d376b366fa23966f27b72a53577e5c`.  
**Escopo:** somente os achados `F0-F1-R1-ROTAS-01` e `F0-F1-R1-ROTAS-02` do parecer normal [`F0-F1-R1-rotas-foco.md`](F0-F1-R1-rotas-foco.md).  
**Método:** leitura estática do consumidor do BE-05, das rotas, do Sidebar e dos specs de integração. O coordenador informou seis cenários de integração passando no job31. Não executei testes, build, banco, serviço, autenticação ou navegador nesta sessão.

## Resultado

**PASS nesta confirmação limitada para o código e a integração; navegador real pendente.** Não encontrei residual concreto nos dois IDs. Isso não é aprovação visual, de release ou de produção: o percurso precisa ainda ser conferido no navegador real pelo coordenador, incluindo o estado ativo da Sidebar.

## ROTAS-01 — um único dono da retomada BE-05

O cartão não lê nem inicia a conversa. Para E1/E2, `AgentsListPage.vue:46-63` apenas encaminha para `autonomia_agent_build` com `step: 'tell'`; não há dispatch de `resume` ou `start` nessa entrada. A rota de produção (`autonomia.routes.js:129-140`) entrega `resumeBuild: true` ao `AgentPanelPage`.

O painel é o único dono da entrada: `AgentPanelPage.vue:201-221` primeiro carrega o agente e, somente para quem pode editar e para agente guiado, faz uma única chamada `autonomiaBuildThreads/resume`. O painel só fica pronto depois dessa chamada. Falhas entram no `catch` (`:222-231`), exibem o aviso localizado e voltam para `autonomia_agents_index`, sem criar uma thread.

O spec de integração monta a lista e o painel reais com um roteador em memória (`AgentsContinue.integration.spec.js:1-8,77-162`). Os seis cenários informados como passando no job31 cobrem:

- E1 e E2: destino `autonomia_agent_build`, uma retomada e nenhuma ação `start` (`:215-244`);
- falha 401 e 404: retorno à lista, aviso localizado, uma tentativa de retomada e nenhuma ação `start` (`:246-273`);
- E2m manual: rota legada sem `resume` nem `start` (`:275-293`);
- pessoa somente leitora: abre o painel de leitura sem `resume` nem `start` (`:295-314`).

O `f0-routes-compat.spec.js` também conserva o gate global e o gate por conta, a rota legada e a separação entre `autonomia_view` e `autonomia_manage` (`:20-25,50-90,92-131`). A prova estática e a integração não mostram o problema de dois donos que originou o ROTAS-01.

## ROTAS-02 — Sidebar A permanece ativa

Quando `autonomia_agents_redesign_enabled` está ligado, a Sidebar monta um único item `Agents` (`components-next/sidebar/Sidebar.vue:810-826`). Seu `activeOn` contém `autonomia_agents_index`, `autonomia_agents_builder`, `autonomia_agent_build`, `autonomia_agent_ready` e `autonomia_agent_panel`, além de `autonomia_agent_panel_legacy`, que é a entrada de compatibilidade documentada para o staging. A conta desligada continua no ramo legado separado (`:827-859`).

As rotas correspondentes continuam account-scoped e com permissões coerentes: index/painel usam `agentsMeta`; criação, build e ready usam `agentsManageMeta` (`autonomia.routes.js:33-40,115-183`). O registro gerado não foi editado manualmente. Não encontrei nome de rota novo fora da lista aprovada nem segundo item na Sidebar A.

## Limite restante

Os seis cenários de integração passaram conforme o recibo do coordenador. A verificação visual no navegador ainda deve confirmar a sequência lista → rota → painel, 401/404, manual, viewer e o item ativo nas cinco rotas normativas. Até essa captura, a confirmação permanece limitada e não autoriza merge, fila, deploy, produção ou aprovação visual.
