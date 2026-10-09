# Auditoria 09 — segurança, permissões, flags, legado, Enterprise, Guia e integração

**Data:** 2026-10-09  
**Escopo:** leitura estática do worktree `agentes-ia-prd`, sem alterar produto, spec, snapshot ou Git.  
**Candidato:** `docs/agentes-ia-prd@532a5b7beb56902d2a0168013a3e8b657ba31488`.  
**Main de referência fornecida:** `28e1e0ac8b3835577f7469368f03a86d1a8dab0d`.

## Parecer delimitado

Após confrontar o contrato do PRD e as rotas reais, não mantenho P1 ou P2 confirmado nesta adjudicação. O primeiro apontamento era uma leitura incorreta do contrato de analytics; o segundo não é alcançado pelo fluxo normal da flag ON. Registro abaixo o risco de deep link legado como candidato, junto das lacunas de integração e validação.

## Adjudicação do apontamento de analytics

O resumo agregado por agente e conta é comportamento aprovado pelo contrato:

- O PRD BE-25, linha 538, limita `PermissionFilterService` a `analytics/conversations`; registra expressamente que a extensão Enterprise entra por `prepend_mod_with` e que o número agregado do resultado não muda.
- D12 trata `analytics/conversations` e `faq_suggestions`, não o resumo.
- CA-RES02 define dados agregados; CA-RES04 define a lista filtrada.

O código observado é compatível com essa separação: `app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb:7-8` chama o resumo sem filtro de conversa, enquanto `analytics_controller.rb:32-37` aplica `Conversations::PermissionFilterService` no drilldown. `app/services/autonomia/agents/analytics.rb:35-57` e `:78-82` calculam os números por agente+conta e janela. Portanto, retiro o P1-09.1 e não recomendo alterar autorização ou privacidade do resumo.

## Adjudicação da flag e do painel legado

O fluxo normal com flag de redesign ligada não monta o consumidor antigo:

- `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js:168-175` aponta `autonomia_agent_panel` para `AgentPanelEntry`.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentPanelEntry.vue:20-25` escolhe `RedesignAgentPanelPage` quando `autonomia_agents_redesign_enabled === true`.
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentPanelPage.vue:22,96` usa `PanelSettings`, não `PanelTune`.

Assim, retiro o gatilho anterior de “conta ON abre o PanelTune antigo” e não mantenho P2-09.2 como defeito confirmado.

### Candidato de compatibilidade legado

Existe, porém, uma superfície separada que não depende da flag: `autonomia_agent_panel_legacy` é uma rota explícita em `autonomia.routes.js:155-166` e monta diretamente `LegacyAgentPanelPage`. A lista redesign também direciona o estado `E2m` para essa rota em `AgentsListPage.vue:50-54`; esse estado é manual e não exibe a reconversa guiada.

Se alguém abrir diretamente `/agents/:agentId/legacy/tune` para um agente guiado com a flag ON, o legado alcança `PanelTune.vue:47-48`, que lê `autonomia_agents_redesign`, enquanto `_account.json.jbuilder:38` fornece apenas `autonomia_agents_redesign_enabled`. Nesse deep link, `PanelTune.vue:228-239` pode escolher o reset/fluxo legado em vez de retomar a thread. Isso fica como **candidato de compatibilidade de URL antiga**, sem evidência de que seja um fluxo suportado ou alcançado pela navegação normal. A decisão pendente é manter a rota legada utilizável com flag ON ou bloqueá-la/redirecioná-la.

## Controles e invariantes verificados

- O gate central em `app/controllers/api/v1/accounts/autonomia/base_controller.rb` aplica feature flag da conta e permissão de módulo. Nos jobs/listeners revisados, os caminhos de operação também consultam `Autonomia::Agents::Config.enabled?`; não encontrei bypass de flag-off nesses caminhos.
- Os controllers revisados resolvem agente, fonte, canal e thread dentro da conta corrente. Strong params e `ConfigContract` aparecem nas entradas de agentes; não foi confirmado IDOR ou bypass de parâmetros nesta leitura.
- O probe standalone de Rails 7.1.5.2 retornou 200 com envelope `agent`; o apontamento 06-P1 de falha HTTP do wrapper foi descartado.
- A evidência sobre `ApplicationController`/`RequestExceptionHandler` e `RecordInvalid` impede manter o apontamento 07-04 como retorno 500.
- Não foi encontrada extensão Enterprise específica para estes controllers. Isso não é defeito por si só: o caminho comum usa a política compartilhada e há cobertura Enterprise para o drilldown. Compatibilidade Enterprise em runtime não foi executada.

## Integração com main e alegações anteriores

- O candidato está 136 commits atrás do main de referência e há 16 caminhos sobrepostos. A comparação da fonte congelada registrou 367 arquivos examinados e nenhuma diferença entre working tree e fonte 80.
- A alegação 05 de remoção de Connect e operações Meta Ads descreve o candidato isolado, mas o merge somente leitura em scratch terminou com código 0 e preservou Connect e Meta Ads. Portanto, não é defeito confirmado do patch integrado; é risco de drift que exige revisar os 16 overlaps ao montar o PR.
- A baseline 03 parou por EMFILE antes de completar suas verificações; não constitui aprovação. O resultado de GitHub também não prova SHA implantado em produção.

## Candidatos e lacunas

1. O deep link `autonomia_agent_panel_legacy` com flag ON pode carregar uma tela antiga e expor a divergência de chave descrita acima. Falta decisão de contrato sobre a permanência dessa URL; não foi classificado como regressão do fluxo principal.
2. O drilldown informa `has_hidden`, `hidden_count` e totais de registros inacessíveis. As specs Enterprise parecem tratar isso como contrato intencional; é uma decisão de privacidade a revisar, não defeito confirmado.
3. `guideRouteRegistry.js`, `guia-produto.md` e formatos do Guia são gerados. Não houve execução de `pnpm guia:check` nem de `autonomia:guia:formatos:check`; não há aprovação de sincronização do Guia ou de cobertura de strong params.
4. O merge-readonly resolveu apenas a preservação de Connect e Meta Ads. A integração final continua pendente até o patch ser aplicado ao main atual e os 16 caminhos sobrepostos serem reavaliados.
5. Nenhum teste, CI, boot completo, banco, HTTP de aplicação ou verificação de produção foi executado nesta lane.

## Conclusão

O parecer 09 fica **sem defeito P1/P2 confirmado após a adjudicação**. Permanecem um candidato de compatibilidade para deep link legado, lacunas de checks gerados e a necessidade de revisar os overlaps com o main. Isso não sustenta declaração de zero regressão, integração completa ou qualquer afirmação sobre produção.