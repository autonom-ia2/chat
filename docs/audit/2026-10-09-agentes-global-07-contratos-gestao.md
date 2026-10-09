# Auditoria 07 — contratos de gestão (FRONT/BACK)

- **Data:** 2026-10-09
- **Lane:** Agentes IA redesign F5–F7; gestão e integração entre abas
- **Checkout auditado:** docs/agentes-ia-prd, branch docs/agentes-ia-prd, HEAD 532a5b7b
- **Baseline de referência:** 28e1e0ac8b3835577f7469368f03a86d1a8dab0d
- **Status:** **PARECER PARCIAL RETIFICADO**. Após adjudicação coordenada, não há achado confirmado nesta lane; permanece um candidato estático explícito.
- **Regra de severidade:** P0 = crítico; P1 = alto; P2 = médio; P3 = baixo.

## Escopo e método

Cruzei as telas e chamadas da gestão com rotas, APIs, store, controllers, strong params, serializers/Jbuilder, models, policies e jobs/polling quando a cadeia estava disponível. O exame cobriu Knowledge (PanelKnows, FaqReviewList, AddMaterialDialog), atendimento (implementado como PanelWhereServes), Test (PanelAgentTest), Settings (Identity, Instructions, Actuation, Speech, Handoff, Audience, Schedule, Versions, Lifecycle e Quote), Tools (PanelToolsV2/ToolDialog) e performance HowItsGoing/drawer.

Também li o HANDOFF-CODEX, o bloco F5–F7, PRD §6.3/§6.6/§6.7/§7 e o parecer C1–C15. Não executei testes pesados, serviços, runtime ou produção. O working tree foi preservado; não houve correção, commit, merge, push ou cleanup.

Os nomes pedidos PanelChannels, SettingsChannels e SettingsDanger não existem no caminho atual; as responsabilidades equivalentes são PanelWhereServes, SettingsSchedule e SettingsLifecycle. Isso foi tratado como diferença de nomenclatura, não como remoção presumida.

## Resultado após adjudicação

| Item | Veredito | Confiança |
|---|---|---|
| AG-07-01 — wrapper do toggle de status | **Retirado** | Alta, por evidência Rails compartilhada |
| AG-07-02 — teto de fontes sob seleção múltipla | **Candidato estático P2; não confirmado** | Média |
| AG-07-03 — 422 sem code em Sources | **Observação preexistente; não achado acionável** | Alta |
| AG-07-04 — validação de upload sem JSON | **Retirado** | Alta, por handler comum verificado |
| P0/P1/P2/P3 confirmados | **Nenhum** | —
## Retificações

### AG-07-01 — retirado: wrapper do toggle de status

A hipótese anterior dizia que AgentPanelPage enviava status/enabled sem o envelope agent e que params.require(:agent) bloquearia a operação. A adjudicação do root e os probes de parâmetros Rails em .codex/preview/global-audit-20261009/rails-params-wrapper-probe-ascii.json e rails-params-wrapper-scope.json refutam essa conclusão para o checkout auditado: o formato do initializer e o fallback do controller permitem o payload cru, sem override global no model Agent.

Portanto, não há P1 confirmado neste ponto. A referência anterior ao storeFactoryHelper.js:166-170 foi removida; ela estava incorreta para o fluxo/linha considerado. O trecho correto do helper de update fica na faixa 53-65, mas não sustenta defeito após o probe. Não propor correção nem teste deste item.

### AG-07-04 — retirado: ausência de handler JSON para RecordInvalid

A formulação anterior também estava errada. app/controllers/application_controller.rb inclui RequestExceptionHandler; app/controllers/concerns/request_exception_handler.rb:11 resgata ActiveRecord::RecordInvalid e render_record_invalid retorna 422 JSON com message e attributes.

Pode existir uma discussão separada sobre DTO/códigos específicos de Sources, mas não há ausência do handler nem base para afirmar 500/sem JSON. O item foi retirado do quadro de achados.

### AG-07-03 — observação, sem finding novo

Foi observado que alguns caminhos de Sources chamam render_unprocessable sem code (sources_controller.rb:10-18,78-85; base_controller.rb:88-92). A ausência é real no payload observado, mas é preexistente no baseline e o contrato BE10 é específico; não há fundamento nesta lane para inventar códigos obrigatórios ou transformar isso em P2.

O ponto fica registrado apenas como observação de compatibilidade para uma revisão contratual própria. Não bloqueia esta auditoria e não gera proposta de alteração.

### AG-07-02 — candidato estático P2: contagem e criação sem lock

- **Causa:** o reconverse de Instructions dispara um create por arquivo em Promise.all; cada request conta as fontes e salva separadamente. O limite está no controller, sem lock demonstrado unindo contagem e criação.
- **Gatilho:** selecionar vários arquivos quando o agente está próximo de 30 fontes knowledge, ou repetir a ação em abas/requests concorrentes.
- **Efeito possível:** duas requests podem observar a mesma contagem e salvar além de MAX_KNOWLEDGE_SOURCES = 30. É risco de invariável de capacidade, não defeito reproduzido.
- **Evidência estática:** app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/panel/SettingsInstructions.vue:223-234; app/controllers/api/v1/accounts/autonomia/agents/sources_controller.rb:14-24,127-133; app/models/autonomia/agents/source.rb:91-112.
- **Cobertura/veredito:** cadeia seleção múltipla → API/store → contagem/modelo/persistência examinada; nenhuma corrida foi executada. **Confiança: média; candidato estático, não achado confirmado.**
- **Proposta para avaliação futura:** tornar atômica contagem + criação na fronteira do agente, com lock/constraint/transação e recusa estável. Serializar no frontend pode melhorar UX, mas não substitui defesa no servidor.

## Mapa de contratos verificados

- **Knowledge:** PanelKnows carrega Sources e filtra kind=knowledge; AddMaterialDialog cria link/arquivo; FaqReviewList lista/aprova/ignora FAQ paginada. Controllers escopam o agente pela conta atual; Jbuilder expõe payload e metadados.
- **Atendimento:** PanelWhereServes usa index/create/destroy de Channels, com elegibilidade, ocupação e schedules; rota é ocultada para interno/viewer.
- **Settings:** as seções enviam envelopes agent ou endpoints específicos; Versions separa origem manual/guiada; Lifecycle envia o envelope correto. Quote usa endpoint próprio e o serializer de detalhe.
- **Test:** PanelAgentTest usa playground assíncrono/polling e consome reply, confiança, handoff, conhecimento, tools ignoradas e writes_external; não encontrei divergência de shape nesta leitura.
- **Tools:** PanelToolsV2 limita acesso a SuperAdmin/gestão, usa response.data.payload e coincide com o controller; quote não expõe Tools.
- **HowItsGoing/drawer:** analytics e drilldown usam payload/meta, limite e filtros por permissão; não encontrei divergência de shape nesta leitura.

## Cobertura, limites e autoria

- **Lido:** HANDOFF-CODEX, bloco de design F5–F7, PRD §6.3/§6.6/§6.7/§7, C1–C15; APIs, store, rotas e componentes da lane; controllers Sources/FAQ/Channels/Agents/Playground/Handoff/Analytics/Tools; params, policies, Jbuilder/DTOs e model Source.
- **Integração:** foram cruzados autorização por conta/módulo, isolamento de agente, respostas, persistência, eventos/jobs de ingestão e polling; nenhuma afirmação de cobertura total foi feita.
- **Não executado:** testes globais, serviços, browser/runtime, produção e comparação adicional ampla com o drift/base. Não há evidência de comportamento real além das leituras, dos artefatos já registrados no HANDOFF e dos probes de adjudicação citados acima.
- **Enterprise/legado:** a leitura delimitada não encontrou um espelho Enterprise que alterasse o candidato restante. Isso é lacuna de cobertura, não atestado de equivalência; revisar overlays quando uma correção for preparada.
- **P0/P1/P2/P3:** nenhum achado confirmado. O AG-07-02 permanece somente como candidato estático para decisão posterior.
- **Autoria:** o parecer e o candidato AG-07-02 permanecem de responsabilidade da auditoria 07; as retiradas e o ajuste de confiança incorporam a evidência de adjudicação do root.

**Registro de coordenação:** recuperação local concluída em modo read-only; relatório retificado sem nova auditoria ampla e sem alteração de produto.
