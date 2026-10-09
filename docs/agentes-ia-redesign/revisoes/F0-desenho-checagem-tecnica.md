# F0 — checagem técnica e de segurança do desenho

**Estado:** checagem independente concluída com achados residuais; o desenho continua `DRAFT — não aprovado` e a implementação do F0 fica parada.

**Alvo revisado:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`, 245 linhas, SHA-256 `3dd44e652b1f14deefb8a071b1cf5db9c8cd2e7a8e3685c418c7e3be3d1978e4`.

**Referência do código:** baseline fixo `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. Esse SHA é a base factual desta checagem e não é uma afirmação sobre o `origin/main` atual.

**Método e limite:** leitura estática do desenho corrigido, das decisões em `docs/audit/2026-10-07-agentes-f0-desenho-decisoes.md`, do PRD/B2 e das fontes de rotas, API, store, painel, foco, locale, tema, Playwright e Guia. Não houve código de produto, teste, build, navegador, M2, banco, produção, autenticação real, merge, fila ou deploy. A revisão visual do protótipo e o aceite das telas reais continuam fora deste relatório.

## Resultado dos oito achados da revisão normal

| Achado | Resultado da checagem | Evidência no desenho corrigido |
|---|---|---|
| F0-TEC-01 — etapas | **Corrigido no desenho.** O `StepsBar` recebe contrato genérico; Campanhas conserva 3 itens e `AgentSteps` recebe 4. `Pronto` ficou fora da barra. | `F0-mapeamento.md:48,53,80-90` |
| F0-TEC-02 — fallback da thread | **Não fechado.** O desenho exige a thread exata, mas não fixa o leitor BE-05 nem a hidratação do store legado; ver F0-CHECK-02. | `F0-mapeamento.md:138-145` |
| F0-SEC-03 — rota/origem WhatsApp | **Não fechado.** A rota ainda mistura `path` e query e o formato canônico de `from` não foi definido; ver F0-CHECK-01. | `F0-mapeamento.md:132,141-145` |
| F0-TEC-04 — token D4 | **Parcial.** Os 18 usos em 12 caminhos do dashboard foram listados, mas o inventário dito completo não cobre a ocorrência de produto em ERB com caixa diferente; ver F0-CHECK-03. | `F0-mapeamento.md:96-113` |
| F0-TEC-05 — locale | **Parcial.** Os consumidores foram enumerados, mas a remoção da implementação local de `CampaignOverviewPage` ficou opcional; ver F0-CHECK-04. | `F0-mapeamento.md:57-64` |
| F0-TEC-06 — foco | **Parcial.** O momento `afterEnter`/`afterLeave` foi definido, mas ainda não há dono único para Escape, captura/restauração e scroll lock; ver F0-CHECK-05. | `F0-mapeamento.md:66-78` |
| F0-SEC-07 — Playwright/a11y | **Corrigido como gate de implementação.** O desenho exige loopback, fixture local, bloqueio de rede/escritas, dependência travada do axe e falha fechada quando a infraestrutura faltar. | `F0-mapeamento.md:175-197,241` |
| F0-TEC-08 — Guia/Central | **Corrigido como sequência de fechamento.** O desenho liga fontes humanas, geração e checks oficiais e proíbe editar os gerados à mão. | `F0-mapeamento.md:222-233` |

## Achados residuais para parar e corrigir

### F0-CHECK-01 — P1 — `connect-whatsapp?from=` não é um `path` válido para declarar a query

**Prova:** o mapa e o PRD ainda registram a rota como `accounts/:accountId/agents/connect-whatsapp?from=` (`F0-mapeamento.md:132`, `PRD.md:665`). No repositório, `frontendURL` separa o caminho dos parâmetros e só acrescenta a query quando recebe o segundo argumento (`app/javascript/dashboard/helper/URLHelper.js:1-4`). O Vue Router interpreta o `path` antes da query; a forma com `?from=` no registro vira texto do caminho, enquanto a URL real chega com `to.path` sem query e `to.query.from` separado. Portanto, copiar literalmente o contrato pode fazer a rota estática não resolver. Além disso, “origem canônica” não define se `from` é nome de rota, saída de `router.resolve`, token opaco ou outro formato.

**Consequência:** a rota pode não ser alcançada ou pode cair no caminho dinâmico; uma validação baseada em string fica sem allowlist de origem e sem prova de que conta, agente e conjunto de canais correspondem.

**Correção mínima:** fixar no desenho o `path` sem query (`accounts/:accountId/agents/connect-whatsapp`) e a leitura de `to.query.from`. Definir um único formato canônico produzido por `router.resolve`/nome de rota interno, com allowlist explícita das rotas de origem e parâmetros `accountId`, `agentId` e canais. A spec deve resolver a rota estática com e sem query e rejeitar valor externo, `javascript:`, desconhecido, de outra conta/agente ou com canais divergentes. Não usar prioridade artificial de ordem do array.

### F0-CHECK-02 — P1 — a retomada ainda não fixa o leitor escopado da thread

**Prova:** o desenho aceita “um `threadId` fornecido pelo backend/lista ou um resolver backend já existente” (`F0-mapeamento.md:138-140`), mas não nomeia o endpoint nem o contrato de hidratação. O BE-05 já define o leitor necessário como `GET agents/:id/build_thread`, com permissão `autonomia_manage` e escopo do agente (`PRD.md:518`). O endpoint atual de `build_threads` resolve apenas pelo id dentro da conta (`app/controllers/api/v1/accounts/autonomia/base_controller.rb:60-63`; `app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb:115-118`). O store também expõe apenas `show(threadId)` (`app/javascript/dashboard/api/autonomia/buildThreads.js:37-39`). No painel antigo, `PanelTune` limpa o store e, sem thread, chama `start` para criar outra (`app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue:209-245`).

**Consequência:** um deep link pode não retomar nada e criar uma conversa nova. Se um id for aceito diretamente, uma pessoa com acesso à mesma conta pode carregar uma thread de outro agente, pois o leitor atual não exige o par agente/thread. Isso viola a continuidade e o isolamento exigidos pelo fallback.

**Correção mínima:** exigir no F0 o endpoint BE-05 (`GET .../agents/:agent_id/build_thread`) ou um resolver com o mesmo contrato: `agents_scope` + agente da rota + última thread guided, 404 para outro agente/conta, 401 sem `autonomia_manage`, e retorno do id/estado necessários para o store. A entrada deve hidratar esse registro antes de montar `PanelTune`; `start` fica proibido nesse caminho. Cobrir thread do agente, thread de outro agente na mesma conta, outra conta, ausência e F5 nos quatro desvios.

### F0-CHECK-03 — P2 — o inventário D4 não é completo em modo case-insensitive

**Prova:** o desenho declara que os 18 usos em 12 caminhos são todos os usos de produto e manda provar grep vazio (`F0-mapeamento.md:96-113`). No baseline fixo há mais uma ocorrência de produto em `app/views/public/tracked_link_kits/show.html.erb:9`: `--navy: #0d2344`. Ela não aparece na busca exata por `#0D2344` usada para fechar os 18 e não é documentação, HTML do PRD ou mockup.

**Consequência:** a prova descrita pode passar deixando um literal equivalente no produto, ou a implementação pode alterar superfícies diferentes sem uma decisão explícita de escopo.

**Correção mínima:** decidir no desenho se a página pública fica fora de D4 e registrar a razão, ou incluí-la na classificação. A validação deve buscar o literal sem diferenciar maiúsculas/minúsculas, com exclusões nomeadas e justificadas; não deixar a prova dependente da capitalização.

### F0-CHECK-04 — P2 — a duplicata de locale continua permitida sem decisão fechada

**Prova:** o desenho exige a migração de `CampaignOverviewPage.vue` **ou** uma exceção documentada (`F0-mapeamento.md:64`). No baseline, a página mantém sua própria implementação em `CampaignOverviewPage.vue:47-58`, enquanto o helper compartilhado está em `components-next/CampaignJourney/localeTag.js:4-12`. A exceção não tem motivo de compatibilidade nem teste de paridade definido no desenho.

**Consequência:** a extração pode terminar com dois contratos de locale e a tela continuar divergindo no fallback, nos formatos ou no tratamento de locale composto, contrariando o motivo de D9.

**Correção mínima:** determinar a migração para `dashboard/helper/localeTag.js` e remover a cópia local como regra. Se surgir incompatibilidade real, registrar o motivo, a diferença de contrato e uma spec de paridade antes de aceitar a exceção; não deixar a escolha para a implementação.

### F0-CHECK-05 — P1 — o ciclo de foco ainda tem dois donos potenciais

**Prova:** o desenho exige não duplicar listeners/restauração (`F0-mapeamento.md:68-70`), mas não define qual código deixa de executar cada responsabilidade. O `SidePanel` atual já captura o gatilho no `open`, restaura no `close`, controla scroll lock e registra Escape (`app/javascript/dashboard/components-next/side-panel/SidePanel.vue:39-89`). O composable atual também registra um listener de teclado com Escape e restaura o gatilho no unmount (`app/javascript/dashboard/components-next/CampaignJourney/useModalFocus.js:39-64`).

**Consequência:** integrar o composable sem uma regra de ownership pode fechar duas vezes, emitir `close` duplicado, restaurar foco em elemento diferente ou manter dois tratamentos de Escape; isso é especialmente provável nos drawers já montados com `v-if` e nos diálogos aninhados.

**Correção mínima:** declarar no desenho um único dono por responsabilidade. Recomendo manter `SidePanel` como dono de `open`, `close`, Escape, scroll lock, captura do gatilho e restauração; o composable compartilhado deve apenas ativar/desativar o trap de Tab depois de `afterEnter` e antes de `afterLeave`, usando o gatilho capturado pelo painel. A integração deve contar listeners e eventos `close` em cada consumidor da matriz, além de testar diálogo nativo, clique fora e reabertura.

## Conclusão e bloqueio

Os contratos de etapas, Playwright/a11y e Guia/Central ficaram suficientemente explícitos para implementação futura. Os cinco achados acima ainda deixam risco concreto de rota inacessível, retomada de conversa errada, escopo visual incompleto, locale duplicado e foco com listeners concorrentes. Portanto, esta checagem **não passa**; o F0 deve parar, registrar as causas, corrigir somente o desenho e passar por uma única revisão final antes de qualquer código de produto.

Nenhum achado deste relatório aprova o protótipo, as telas reais, merge, fila, deploy ou produção. A checagem visual e os cenários locais exigidos pelo aceite continuam pendentes.
