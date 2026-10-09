# Revisão normal F0/F1 R1 — rotas, retomada e foco

**Data:** 2026-10-07  
**Alvo:** implementação local F0/F1 na worktree `docs/agentes-ia-prd`, com o snapshot 30 congelado pelo coordenador.  
**Escopo:** rotas da área, entrada do `AgentPanelPage`, consumidor do BE-05, permissões/conta/modo manual e o ciclo compartilhado de foco (`useModalFocus`, `SidePanel`, `AudienceSidePanel`). A lista e seus specs não foram revisados como uma fatia própria; o primeiro achado abaixo é uma interação objetiva entre a entrada da lista e o consumidor da rota.  
**Método:** leitura estática de código, F0/F1/PRD e specs existentes. Não executei testes, build, lint, navegador, banco, serviço, produção ou autenticação real.

## Resultado

**PARADA — há dois resíduos concretos antes de considerar rotas e integração da primeira tela fechadas.** O ciclo de foco compartilhado, a separação de permissões e o escopo de conta passaram na leitura estática. A implementação não deve avançar para a checagem limitada enquanto os dois pontos abaixo não forem corrigidos e provados juntos.

## Achados

### F0-F1-R1-ROTAS-01 — P1 — E1/E2 fazem duas leituras do BE-05 ao continuar

**Prova:** para E1/E2, `AgentsListPage.vue:48-72` despacha `autonomiaBuildThreads/resume` e, depois que a leitura retorna, navega para `autonomia_agent_build`. A definição dessa rota em `autonomia.routes.js:129-140` sempre passa `resumeBuild: true`. Ao montar a entrada, `AgentPanelPage.vue:199-222` carrega o agente e, como `props.resumeBuild` é verdadeiro, despacha novamente `autonomiaBuildThreads/resume`.

**Causa:** a leitura foi dividida entre a ação de retomada do cartão e o consumidor da rota. O comentário da lista diz que a rota manterá a thread hidratada, mas o contrato de props manda a rota hidratá-la de novo. O teste do cartão e o teste do painel são isolados; nenhum monta a sequência real cartão → rota.

**Efeito:** a mesma retomada guiada dispara dois GETs account-scoped. A segunda ação reseta a fatia de thread e pode cancelar/recriar o polling da primeira (`autonomiaBuildThreads.js`), além de abrir uma janela de resposta fora de ordem. O contrato F1 exige ler a última thread existente antes de montar a retomada e não criar outra; manter dois donos do leitor deixa a jornada dependente de timing e custa uma consulta por continuação.

**Correção mínima:** escolher um único dono do BE-05 para E1/E2 e usar o mesmo caminho em entrada pelo cartão e deep link. Se a lista continuar lendo antes de navegar, a rota precisa receber uma marca de hidratação já documentada e não repetir a leitura; se a rota for o único dono, a falha 401/404 precisa retornar à lista com o aviso localizado de retomada. Adicionar uma prova de integração que conte as chamadas e confirme que `start` nunca é despachado.

### F0-F1-R1-ROTAS-02 — P2 — o item da Sidebar não fica ativo nas rotas novas

**Prova:** `components-next/sidebar/Sidebar.vue:804-827` limita o `activeOn` do grupo a `autonomia_agents_index`, `autonomia_agents_builder` e `autonomia_agent_panel`; o filho “Meus agentes” repete apenas `autonomia_agents_index` e `autonomia_agent_panel`. As rotas `autonomia_agent_build` e `autonomia_agent_ready` existem em `autonomia.routes.js:129-152` e já estão no registry gerado em `guideRouteRegistry.js:27-32`. O requisito normativo exige que o item cubra `autonomia_agents_index`, `autonomia_agents_builder`, `autonomia_agent_build`, `autonomia_agent_ready` e `autonomia_agent_panel` (`PRD.md:671`).

**Efeito:** ao seguir “Continuar”, “Escolher onde atende” ou “Pronto”, a pessoa permanece na área de Agentes, mas o item lateral perde o estado ativo. Isso quebra a orientação espacial da jornada e deixa a Central/Guia e a navegação visual em estados diferentes. A rota de compatibilidade `autonomia_agent_panel_legacy` também precisa de uma decisão explícita de destaque, porque é uma entrada real da mesma área (`autonomia.routes.js:155-165`).

**Correção mínima:** atualizar o `activeOn` do grupo e do filho com os nomes normativos novos e cobrir a rota legada de compatibilidade conforme a regra de navegação adotada. Provar cada nome com a mesma conta e flag; não editar o registry gerado à mão.

## Conferências sem achado adicional

- `ensureAutonomiaEnabled` continua exigindo o kill-switch global e `autonomia_agents_enabled` da conta (`autonomia.routes.js:58-75`); o redesign é escolhido dentro de `AgentsIndexPage.vue:11-15` pelo booleano da conta. A conta é carregada antes do guard (`autonomia.routes.js:42-55`), e as APIs da lista usam `accountScoped: true`, sem evidência de mistura entre contas.
- As rotas de criação/retomada usam `agentsManageMeta` (`autonomia.routes.js:122-152`), enquanto o painel compatível e o painel genérico usam `agentsMeta`. No painel, `canManage` protege a retomada do BE-05 e deixa só Testar/Como está indo para quem só vê (`AgentPanelPage.vue:61-91,199-222`).
- E2m é ramificado na lista para `autonomia_agent_panel_legacy/tune` (`AgentsListPage.vue:52-57`); no consumidor, modo manual não entra no predicado de retomada. Não encontrei chamada de BE-05 ou criação de thread no caminho manual.
- `useModalFocus.js:48-68` ficou restrito a `activate/deactivate` e Tab/Shift+Tab. `SidePanel.vue:39-112` mantém a ownership de captura do gatilho, foco inicial em `afterEnter`, Escape, scroll, restauração e `afterLeave`; `AudienceSidePanel.vue:100-139` usa apenas a ref do painel e só emite `close` depois de `afterLeave`, sem listener paralelo. As specs de `SidePanel` e `AudienceSidePanel` cobrem foco inicial, trap, Escape, retorno após `afterLeave` e fechamento público único.
- A ausência de `AgentSteps` na casca atual não foi registrada como defeito desta revisão: o mapa F0 permite manter as entradas futuras em componentes legados durante o staging, enquanto a primeira tela é ativada (`design/F0-mapeamento.md:144-158`). Isso continua uma dependência das fatias F2/F3, não uma aprovação das telas futuras.

Nenhum arquivo de produto foi alterado nesta revisão. Os achados precisam de uma correção única, seguida da checagem limitada prevista pelo coordenador; se restar erro nessa checagem, a regra do usuário exige parar e retornar o bloqueio.
