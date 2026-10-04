# #950 — fechamento do painel Super Admin (Orion, 2026-10-04)

Issue #950, branch `feat/950-instagram-admin-panel`, base `11b41b1030`. Este registro cobre somente controller, metadados/leitor de configuração, ERB/helper, traduções e specs focais. Outros agentes trabalham na mesma worktree; seus arquivos foram preservados. Commit/PR/Project/review/release pertencem ao coordenador.

## Entregue

- Save HTML inválido renderiza o painel com HTTP 422, erro localizado fixo e somente os valores submetidos válidos das cinco chaves preservados. Valores inválidos e chaves desconhecidas não voltam na mensagem nem no formulário. JSON mantém `{error: "invalid_configuration"}` / 422. Save válido usa flash EN/PT-BR.
- POST save/health/reconnect exige Super Admin e proteção CSRF explícita. Parâmetros desconhecidos são rejeitados na fronteira antes de escrita/enqueue. Falha CSRF retorna erro sanitizado próprio, sem mensagem de exceção. Ator vem exclusivamente de `current_super_admin.id`; controller chama `OperatorControl.new.enqueue(actor_id: current_super_admin.id)`.
- GET mostra/atualiza estado sem writes de configuração, sessão ou fila e sem flash de sucesso. POST health mostra aviso de leitura local; a UI não chama isso de verificação remota da Meta. Reconnect indica pedido aceito/na fila, nunca reconexão já concluída.
- Tela ERB/Tailwind com cinco campos, seis linhas de estado, heartbeat real `manager.observed_at` com idade, horário local separado `checked_at` e solicitação com `updated_at`. Mostra queued/running/operator_required/succeeded/failed sem secrets. Botão exige fonte gerenciada e sinais booleanos reais do gestor; fica desabilitado durante queued/running.
- Link dedicado na página OAuth Instagram por partial condicional; campos existentes de OAuth/secrets não foram alterados. Nenhum seletor nativo foi introduzido. Texto mínimo de 14 px e tokens do design system para contraste.
- Metadados continuam salvos transacionalmente nas cinco InstallationConfigs; valores salvos, inclusive vazios/nil, prevalecem sobre ENV. IDs permanecem strings exatas 1..40 dígitos. Nome permite limpeza explícita, até 120 caracteres e rejeita espaços nas pontas, whitespace-only, controles e formatação invisível. Toda validação ocorre antes do primeiro write.
- Um snapshot imutável de metadados por Metadata/Configuration/operação: cinco accessors compartilham uma única SELECT. Nova operação cria novo leitor; nenhuma memoização global. Revision SHA256 do JSON das cinco chaves na ordem fixa KEYS é a mesma do bootstrap privado de Lina. Contrato em `tmp/950-integration/shared-contract.md`.

## Validação efetivamente executada

- `git diff --check`: passou.
- Ruby 3.4.4 `ruby -c` nos arquivos Ruby alterados e specs focais: passou.
- Parsing seguro de YAML e comparação das chaves `super_admin.instagram_automation` EN/PT-BR: passou.
- `eval "$(rbenv init -)"` e `tmp/950-integration/run-local.sh bundle exec rubocop` nos oito arquivos Ruby do foco, com cache isolado `tmp/950-integration/rubocop-orion`: **8 files inspected, no offenses detected**.

## Specs preparados, ainda sem execução Rails por Orion

Ao fechar esta frente não existia arquivo/slot `coord-ready`/`allowed` para Orion. Não iniciei Rails/RSpec, setup, outro Postgres/Redis ou job concorrente no banco. Sintaxe/lint não são aprovação de integração. O wrapper isolado já preparado pelo coordenador deve ser usado uma vez no slot serial autorizado:

```sh
tmp/950-integration/run-local.sh bundle exec rspec \
  spec/requests/super_admin/instagram_automations_spec.rb \
  spec/requests/super_admin/instagram_automation_ui_spec.rb \
  spec/services/instagram/automation/metadata_spec.rb \
  spec/services/instagram/testers/configuration_metadata_spec.rb
```

Specs cobrem sessão de Super Admin e usuário comum, IntegrationSession com CSRF ausente/inválido/válido para os três POSTs, ator autenticado, erros HTML/JSON, input seguro/atomicidade, fontes salvas/vazias/ENV, rollback/revision/snapshot/SELECT única, estados e horários reais, EN/PT-BR, Settings/OAuth link e GET sem falsa confirmação.

O spec de serviço/controller antigo `reconnect_contract_spec.rb`, owned Lina, também precisa acompanhar a assinatura nova e o ator autenticado. Browser QA pertence à frente Vega. Guia/build e validação integrada pertencem ao coordenador. Não houve acesso à Meta, alteração de secrets, produção, commit, merge ou deploy; sem prova de renovação real de sessão ou conectividade remota.

## Slot serial Rails real — atualização 2026-10-04
Runner autorizado run-local.sh, Postgres59510/Redis59511; somente dois request specs sequenciais, timeout45s por processo. show_exceptions=:none apenas nos processos de teste.
Correções: helper singular incluído explicitamente no controller plural; nav Administrate exclui instagram_automations (link mantido em Settings); wrap_parameters false evita params JSON fabricados pelo Rails em health/reconnect vazio. Contrato enqueue(actor_id: current_super_admin.id) preservado.
Contraste: botão novo bg-n-blue-11 / dark:bg-n-blue-8, texto branco; input text-n-slate-12 / placeholder:text-n-slate-11; min-h-11 (44px). Medição browser pertence à Vega, ainda não declarada aprovada.

UI: **10 examples, 1 failure**. Log: tmp/950-integration/orion-ui-real-verified-slot.log
- PASS: `renders the dedicated page with five labeled metadata fields`
- PASS: `uses server-side actions and accessible status rows without native selects, CSS or scripts`
- PASS: `disables reconnection for an unmanaged source or an active request even when manager allows control`
- PASS: `enables reconnection only when both backend signals are true`
- PASS: `shows stored session evidence without claiming remote health and renders the check time`
- PASS: `distinguishes the real manager heartbeat time and age from the local snapshot time`
- PASS: `shows every real request state and its last update in English and Brazilian Portuguese`
- FAIL: `refreshes via GET without success flash or writes`
- PASS: `links the Instagram OAuth Settings to automation while preserving its form fields`
- PASS: `adds a separate Settings card and keeps its submenu open on the automation page`

Requests/CSRF: **18 examples, 2 failures**. Log: tmp/950-integration/orion-requests-real-verified-slot.log
- PASS: `requires Super Admin authentication on every action`
- PASS: `denies an ordinary account administrator`
- PASS: `returns only metadata and sanitized status without inserting configuration records`
- FAIL: `renders malformed HTML submissions as 422 without reflecting the submitted shape`
- PASS: `persists allowed metadata and returns sanitized JSON`
- PASS: `redirects an HTML save with a localized success flash in both supported locales`
- FAIL: `renders invalid HTML as 422 with safe fields preserved and a fixed localized message`
- PASS: `rejects unsupported fields, invalid shapes and malformed values without partial writes or echoing input`
- PASS: `recalculates health without saving metadata, invalidating sessions or making external calls`
- PASS: `redirects an HTML health check with an honest localized local-only flash`
- PASS: `keeps reconnect unavailable and never invalidates the current session`
- PASS: `rejects unknown top-level params on every POST without enqueueing or echoing input`
- PASS: `rejects configuration params on health/reconnect in HTML without a false success message`
- PASS: `enqueues using the authenticated Super Admin actor and reports accepted, not renewed`
- PASS: `redirects accepted HTML reconnection with a localized queued message`
- PASS: `rejects absent/invalid CSRF on every POST through IntegrationSession without mutations`
- PASS: `accepts a real session CSRF token for all three actions and binds the actor`
- PASS: `renders an HTML CSRF failure as a safe panel with 422`

Bloqueio: três falhas restantes de no-write mostram InstallationConfig count 0→1 ou 1→2 na renderização HTML. Layout global app/views/super_admin/application/_javascript.html.erb:43 chama ChatwootHub.installation_identifier; lib/chatwoot_hub.rb:31 cria INSTALLATION_IDENTIFIER quando ausente. Não alterei esse arquivo global nem escondi o write com fixture; as asserções permanecem. Parent precisa resolver antes de declarar GET estritamente read-only/browserready.
Resultado: UI9PASS/1FAIL; Requests16PASS/2FAIL; CSRF3PASS/0FAIL. Sem timeout/negativa sandbox/outro spec/chamada externa.

## Bloqueio GET sem escrita resolvido — opt-out local do widget (2026-10-04)
O painel operacional instagram_automation define content_for(:disable_super_admin_support_widget). O partial _javascript.html.erb envolve somente o bloco do widget externo nesse opt-out. Administrate::Engine.javascripts, yield :javascript, JS de teste, CSS e navegação permanecem. Outras páginas não definem a flag e continuam com o widget padrão, incluindo geração preexistente do identificador. ChatwootHub/geração/caches globais não foram alterados.
Exclusão deliberada somente no novo painel sensível: ele não carrega o SDK externo de suporte nem envia nome/email do operador por esse widget. GET e HTML422 são testados com InstallationConfig vazio, sem fixture INSTALLATION_IDENTIFIER. O teste da página OAuth existente usa geração original, não um stub, e confirma widget/identidade/configuração intactos.
Dois arquivos executados sequencialmente no run-local.sh/Postgres59510/Redis59511, timeout45s cada; Rails.application.env_config show_exceptions=:none somente nesses processos de teste. Nenhum browser paralelo/outro banco/setup repetido.

UI: **13 examples, 0 failures** — tmp/950-integration/orion-widget-ui-slot.log
- PASS: `renders the dedicated page with five labeled metadata fields`
- PASS: `uses server-side actions and accessible status rows without native selects, CSS or scripts`
- PASS: `disables reconnection for an unmanaged source or an active request even when manager allows control`
- PASS: `enables reconnection only when both backend signals are true`
- PASS: `shows stored session evidence without claiming remote health and renders the check time`
- PASS: `distinguishes the real manager heartbeat time and age from the local snapshot time`
- PASS: `shows every real request state and its last update in English and Brazilian Portuguese`
- PASS: `refreshes via GET without success flash or writes`
- PASS: `omits only the support widget and its operator identity while preserving application scripts and navigation`
- PASS: `keeps the support widget on existing pages without the operational opt-out`
- PASS: `omits the support widget when rendering invalid HTML without inserting any installation configuration`
- PASS: `links the Instagram OAuth Settings to automation while preserving its form fields`
- PASS: `adds a separate Settings card and keeps its submenu open on the automation page`

Requests/CSRF: **18 examples, 0 failures** — tmp/950-integration/orion-widget-requests-slot.log
- PASS: `requires Super Admin authentication on every action`
- PASS: `denies an ordinary account administrator`
- PASS: `returns only metadata and sanitized status without inserting configuration records`
- PASS: `renders malformed HTML submissions as 422 without reflecting the submitted shape`
- PASS: `persists allowed metadata and returns sanitized JSON`
- PASS: `redirects an HTML save with a localized success flash in both supported locales`
- PASS: `renders invalid HTML as 422 with safe fields preserved and a fixed localized message`
- PASS: `rejects unsupported fields, invalid shapes and malformed values without partial writes or echoing input`
- PASS: `recalculates health without saving metadata, invalidating sessions or making external calls`
- PASS: `redirects an HTML health check with an honest localized local-only flash`
- PASS: `keeps reconnect unavailable and never invalidates the current session`
- PASS: `rejects unknown top-level params on every POST without enqueueing or echoing input`
- PASS: `rejects configuration params on health/reconnect in HTML without a false success message`
- PASS: `enqueues using the authenticated Super Admin actor and reports accepted, not renewed`
- PASS: `redirects accepted HTML reconnection with a localized queued message`
- PASS: `rejects absent/invalid CSRF on every POST through IntegrationSession without mutations`
- PASS: `accepts a real session CSRF token for all three actions and binds the actor`
- PASS: `renders an HTML CSRF failure as a safe panel with 422`

Resultado final focal: **31PASS / 0FAIL / 0BLOCKED**, CSRF3PASS incluso. As três falhas anteriores de escrita em GET/HTML422 foram resolvidas sem enfraquecer asserções. Suite ampla519 e aceite browser permanecem responsabilidade do parent/Vega; não há claim de produção ou de saúde remota Meta.
