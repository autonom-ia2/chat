# PRD — SLA Inteligente (SLA "justo" com IA, horário real e dentro do CRM)

> **Status:** proposta para aprovação (não iniciada). Documento de produto + UX + especificação técnica.
> **Fork** Chatwoot v4.14.1 EE em `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`. Produção atual: `conn16`. Conta de teste: **6** (Seguro Viagem, inbox 113, WhatsApp via WAHA). Âncora do roadmap: [[crm_roadmap_status]].
> **Pesquisa que embasa:** mapa real do SLA do Chatwoot (modelos/serviços/cron EE) + docs WAHA & Evolution API (identificação de grupo, comprovada com citações no §11).

---

## 0. Objetivo e princípios

**Objetivo.** Transformar o SLA do Chatwoot num **"SLA justo e inteligente"**, que (a) **não conta conversas de grupo**, (b) **não pune pausas naturais** de relacionamento (usando a IA que lê a conversa), (c) **respeita o horário real de atendimento** — com **vários blocos por dia** (estilo cal.com) e **horário por agente** que sobrescreve o da caixa —, (d) vive **dentro do CRM** (não escondido em Configurações) e (e) mostra o **badge de quebra no Kanban/Lista**.

**Regras SEMPRE (não negociáveis neste e em todo PR):**
- **Zero regressão.** O SLA nativo do Chatwoot (na conversa/inbox/relatórios) e tudo o mais continuam funcionando. Tudo é **aditivo**; o motor de cálculo só muda comportamento quando os novos toggles estão ligados.
- **Respeitar EE overlay.** SLA é Enterprise (`enterprise/app/...`, gate `feature_enabled?('sla')`). Mudanças no SLA vão no overlay EE; nada hardcoded de OSS. Garantir a feature `sla` habilitada na conta.
- **Reviews por fase + fix-pass** (alinhamento Chatwoot, backend, segurança/Pundit, **regressão zero**, paridade i18n, WhatsApp/IA) + **review final GO/NO-GO**.
- **Testes reais:** gate `eager_load` (EE namespaceado — risco Zeitwerk que já derrubou prod), `ruby -c`, eslint, **paridade i18n en↔pt_BR**, `vite build`, **teste visual real** (SSO + Playwright), e **smoke do cálculo** (cenários de horário/grupo/IA via runner, sem efeitos externos).
- **Backup antes do build**, **deploy só com OK explícito**, **rollback pronto** (próxima tag `connN`).
- **Identidade Chatwoot:** Vue 3 `<script setup>`, Tailwind `n-*`, components-next, i-lucide, i18n pt_BR+en com paridade 1:1.

---

## 1. Como o SLA funciona hoje (resumo) + os 3 problemas

**Hoje (nativo EE):**
- **Política de SLA** (`SlaPolicy`, `enterprise/app/models/sla_policy.rb`): 3 prazos — 1ª resposta (FRT), próxima resposta (NRT), resolução (RT) + flag `only_during_business_hours`.
- **Aplicação:** via **Automação** (ação `add_sla`, `enterprise/app/services/enterprise/action_service.rb`) → seta `conversation.sla_policy_id` → callback cria `AppliedSla` (status `active`).
- **Motor:** cron a cada **5 min** (`TriggerScheduledItemsJob` → `Sla::TriggerSlasForAccountsJob` → `ProcessAccountAppliedSlasJob` → `ProcessAppliedSlaJob` → `Sla::EvaluateAppliedSlaService`). Compara prazos com `created_at`/`waiting_since`/`first_reply_created_at`. Na violação cria `SlaEvent` (frt/nrt/rt), vira `active_with_misses`; ao resolver vira `hit` ou `missed`. Notifica (assignee + admins + participantes) e faz broadcast realtime.
- **UI:** Configurações → SLA (CRUD); badge na conversa/caixa (`components-next/Conversation/Sla/SLACardLabel.vue`, `SLAPopoverCard.vue`); relatório em Configurações → Relatórios → SLA.

**Os 3 problemas (2 levantados por nós, 1 pelo PO):**
1. **Grupos** (WhatsApp não-oficial/WAHA) entram como atendimento e **bagunçam o SLA**.
2. **Relacionamento contínuo** (consultor/vendedor/suporte): a conversa **não fecha**, pausa naturalmente → NRT/RT disparam **falsas quebras**.
3. **Bug do horário comercial:** a flag `only_during_business_hours` **existe mas NÃO é aplicada** — o cronômetro conta **24/7, relógio de parede**. E o horário nativo só aceita **1 bloco/dia**.

---

## 2. Decisões travadas (PO)
- **#1 Grupos:** toggle **"Excluir grupos"** na criação do SLA → **não criar SLA** para conversa de grupo (detecção comprovada: JID termina em `@g.us`; também ignorar `@broadcast`/`status@broadcast`/`@newsletter`).
- **#2 IA:** usar a máquina de leitura/resumo do CRM. **Só no momento da quebra**, a IA decide se há cliente realmente esperando; se não (pausa saudável/encerrou) → **não conta**. Aplica a **NRT + RT** (e FRT quando a última msg não pede resposta). Decisão cacheada (barato).
- **#3 Horário:** corrigir o bug **e** suportar **vários blocos por dia + fuso** (dinâmica cal.com). Feriados **ficam para depois**.
- **IMPORTANTE 1 — Horário por agente:** toggle **"Definir/Editar horário de atendimento"** na criação/edição do agente. Precedência no cálculo do SLA: **horário do agente atribuído > horário da caixa > 24/7**.
- **IMPORTANTE 2 — SLA no CRM + auto-aplicar:** mover a gestão de SLA de Configurações para a **aba CRM, abaixo do Dashboard**. Na criação, **toggles de auto-aplicação** (sem ir em Automações). **v1: só o gatilho "conversa criada".**
- **IMPORTANTE 3 — Badge no CRM:** reusar o **badge de quebra de SLA** nos cards do **Kanban e da Lista**.

---

## 3. Desenho por frente

### 3.1 Motor de horário "justo" (multi-bloco + por-agente) — corrige o bug
**Modelo de horário próprio do SLA** (não mexer no `WorkingHour` nativo, que é 1 bloco/dia e serve a outras coisas — evita regressão):
- Um **"Calendário de atendimento"** com **fuso horário** + **vários blocos por dia da semana** (ex.: seg 09–12 e 13–18).
- Pode ser definido **por caixa de entrada** (substitui/complementa o nativo p/ fins de SLA) e **por usuário (agente/admin)**.
- **Precedência no cálculo de um SLA:** (1) calendário do **agente atribuído** à conversa, se definido e ativo; senão (2) calendário da **caixa**; senão (3) **24/7**.

**Cálculo "tempo útil" (a correção do bug):** em vez de `prazo = início + X segundos de relógio`, o motor conta **só o tempo dentro dos blocos ativos** (no fuso do calendário). Equivalente: "quanto tempo útil já passou entre o evento e agora" → viola se `tempo_útil ≥ prazo`. Fora do expediente, **o relógio pausa**.
- O flag de política **`only_during_business_hours`** vira o **interruptor mestre**: ligado → usa o calendário (com precedência); desligado → **24/7** (comportamento atual, sem regressão para quem é 24h).
- **Bônus:** o Chatwoot **já calcula "tempo em horário comercial" nos relatórios** (`Reports::DataSource` business_hours) — reaproveitamos a lógica/idioma para o cálculo do SLA em vez de inventar do zero (validando a multi-bloco).

**Exemplo:** expediente 09–18 (1 bloco). FRT = 2h. Cliente escreve **17h** → conta 1h hoje, **pausa à noite**, retoma 9h, **viola 10h** do dia seguinte. Com almoço (09–12 e 13–18), as 12–13 também não contam.

### 3.2 Exclusão de grupos (comprovado WAHA/Evolution)
- **Detecção:** a conversa é grupo quando o identificador salvo (`contact_inbox.source_id`) **termina em `@g.us`**. Denylist de não-1:1: `@g.us`, `@broadcast`/`status@broadcast`, `@newsletter`. (Comprovado nas docs — §11. O novo `@lid` afeta só 1:1, não quebra a regra de grupo.)
- **Onde aplica:** ao **auto-aplicar** (3.4) ou via ação `add_sla`, se a conversa for de grupo e o toggle "Excluir grupos" estiver ligado → **não cria `AppliedSla`**. Salvaguarda: o avaliador também pula grupo (defensivo).
- **Toggle por política:** `exclude_groups` (default **ligado**).
- Helper novo: `conversation.whatsapp_group?` (lê o `source_id` do contact_inbox primário).

### 3.3 IA "pausa saudável" — não contar quebra ⭐ (o diferencial)
- **Serviço novo** `Sla::AiBreachGuard` (reusa `Crm::Ai::ContextBuilder` + `ResponsesClient` + `CredentialResolver`). Schema: `{ customer_waiting: boolean, reason: string, confidence: number }`.
- **Gatilho:** dentro do `EvaluateAppliedSlaService`, **no exato momento em que ia registrar uma quebra** (NRT/RT, e FRT quando aplicável), pergunta: *"há um cliente realmente esperando uma resposta NOSSA agora, ou a conversa pausou de forma saudável / a bola está com o cliente / encerrou?"*.
  - `customer_waiting=false` (confiança ≥ limiar, ex. 0,6) → **suprime a quebra** (não cria `SlaEvent`, não muda status). Marca uma "pausa" no `AppliedSla` (cache).
  - `customer_waiting=true` → conta normal.
- **Custo:** chamada **só no momento da quebra** (não a cada 5 min) + **cache** no `AppliedSla` (decisão + id da última mensagem); reavalia quando entra mensagem nova. Gate por `CRM_AI_ENABLED` + toggle de política **"IA: não contar pausas naturais"** (default ligado).
- **Resultado:** métrica de SLA **real**, não inflada por relações contínuas.

### 3.4 SLA dentro do CRM + auto-aplicar (v1)
- **Mover a tela** de Configurações → **aba CRM, abaixo do Dashboard** (nav: Kanban · Dashboard · **SLA**). Reusa os endpoints EE (`sla_policies_controller`); só relocamos o **frontend** (nova rota `crm/sla`, remove o item de Configurações). Gate `feature_enabled?('sla')` + permissão admin.
- **Auto-aplicar (sem ir em Automações):** na caixa de criação/edição do SLA, um bloco **"Aplicar automaticamente"** com:
  - **v1: gatilho "ao criar conversa"** (toggle) + seleção de **caixas E funis** (ou "todas/todos") onde vale.
  - Por baixo: um **hook próprio no evento conversation_created** aplica a política às novas conversas que caem numa **caixa OU num funil** selecionado (respeitando exclusão de grupo). Guardado em `sla_policy.metadata.auto_apply = { event:'conversation_created', inbox_ids:[...], pipeline_ids:[...] }`. (Futuro: outros gatilhos.)
- Mantém a aplicação manual/por automação existente intacta (aditivo).

### 3.5 Badge de quebra no Kanban/Lista
- **Reusar** `components-next/Conversation/Sla/SLACardLabel.vue` (já calcula contagem regressiva/atraso ao vivo a partir de `applied_sla` + prazos) nos **cards do Kanban** e nas **linhas da Lista**.
- **Payload:** expor no card a SLA da **conversa primária** — adicionar `sla` (status + prazos + created_at + paused?) ao payload do card (no `conversation_payload`/board builder), gated em `feature_enabled?('sla')`. Sem PII.
- Mostra só quando há `AppliedSla` na conversa do card.

---

## 4. Modelo de dados (tudo aditivo; migrations additivas)
- **`ServiceSchedule`** (novo; EE) — calendário de atendimento. Campos: `account_id`, **owner polimórfico** (`Inbox` ou `User`), `timezone`, `enabled`, `blocks` (jsonb: `[{ day_of_week, start_minute, end_minute }]` — **vários por dia**). *(Alternativa: tabela `service_schedule_blocks`; jsonb é mais simples e suficiente.)*
- **`SlaPolicy`** (+ colunas/metadata): `exclude_groups` (bool, default true), `ai_skip_natural_pause` (bool, default true), `auto_apply` (jsonb). `only_during_business_hours` passa a ser **respeitado**.
- **`AppliedSla`** (+ metadata): cache da decisão da IA (`ai_pause: { waiting:false, reason, decided_at, source_message_id }`) e marcação de "pausado por horário/IA/grupo" para auditoria.
- **Sem mudança** em `SlaEvent` (só deixa de ser criado quando suprimido).

## 5. Lógica de cálculo (passo a passo)
No `EvaluateAppliedSlaService`, para cada prazo configurado:
1. **Grupo?** se a conversa é grupo e a política exclui grupos → **encerra** (não avalia / não cria).
2. **Calendário aplicável** = agente atribuído (se tem schedule ativo) → senão caixa → senão 24/7.
3. **Tempo útil decorrido** entre o marco (criação / waiting_since / first_reply) e agora, **contando só dentro dos blocos** do calendário (no fuso dele). Se `only_during_business_hours` desligado → tempo de relógio (24/7).
4. **Ainda dentro do prazo?** se sim, não faz nada. *Relógio único (#283):* o prazo é `AppliedSla#calculate_due_at` → `Sla::DueAtCalculator` (calendário do fork via `BusinessTimeCalculator#deadline`; sem calendário usável → `Sla::BusinessHoursService` upstream; 24/7 → relógio de parede). O cartão, o Kanban e a quebra leem o **mesmo** valor: a quebra é registrada em `now >= due_at`, e a primeira resposta está no prazo se `first_reply_created_at <= frt_due_at`.
5. **Estourou?** antes de marcar quebra, se a política usa IA → **`AiBreachGuard`**: se "cliente não está esperando" → **suprime** (cacheia). Senão → cria `SlaEvent` + `active_with_misses` + notifica.
6. Ao **resolver**: `hit` (sem quebras) ou `missed` (com quebras).

## 6. Mapa de arquivos (reuso vs novo)
**Reuso:** `enterprise/app/services/sla/evaluate_applied_sla_service.rb` (motor — alterado), `enterprise/app/models/{sla_policy,applied_sla,sla_event}.rb`, `enterprise/app/services/enterprise/action_service.rb` (add_sla), `Crm::Ai::{ContextBuilder,ResponsesClient,CredentialResolver}`, `components-next/Conversation/Sla/SLACardLabel.vue`, `crm.routes.js`, `Reports::DataSource` (business hours), `contact_inbox.source_id`.
**Novo:** `ServiceSchedule` model + cálculo de tempo útil (`Sla::BusinessTimeCalculator`), `Sla::AiBreachGuard`, helper `conversation.whatsapp_group?`, hook de auto-aplicar no conversation_created, UI de horário (caixa + **agente**, multi-bloco), tela de SLA no CRM, badge no card, endpoints de schedule, i18n.
**EE overlay:** mudanças de SLA sob `enterprise/`; novos modelos gated por `feature_enabled?('sla')`.

## 7. Faseamento (ondas)
- **Onda 1 — Motor justo:** `ServiceSchedule` (multi-bloco + fuso, por caixa e por agente) + `BusinessTimeCalculator` + honrar `only_during_business_hours` com precedência **agente>caixa>24/7** + UI de horário (caixa estilo cal.com + **toggle no agente**). *(Maior onda; corrige o bug #3 + IMPORTANTE 1.)*
- **Onda 2 — Grupos:** detecção `@g.us`/denylist + toggle `exclude_groups` + skip na aplicação/avaliação. *(Pequena.)*
- **Onda 3 — IA pausa saudável:** `Sla::AiBreachGuard` + cache + toggle de política. *(Média; reusa IA.)*
- **Onda 4 — SLA no CRM + auto-aplicar:** mover tela p/ aba CRM + bloco de auto-aplicação (v1 conversation_created). *(Frontend + hook.)*
- **Onda 5 — Badge no Kanban/Lista:** expor `sla` no payload do card + reusar `SLACardLabel`. *(Pequena.)*

Cada onda: orquestração (impl disjunto + review paralelo + fix-pass) → gates → teste visual/smoke → **OK do PO** antes de deploy.

## 8. Regras de processo (recap)
- **Backup** (tgz das pastas app/config/db/docs) antes de codar.
- **Gates obrigatórios:** `ruby -c` (todos .rb), `eslint`, **JSON + paridade i18n en↔pt_BR**, `vite build`, **`eager_load` em serviço Swarm temporário** (EE namespaceado!), **teste visual real** (SSO+Playwright) + **smoke do cálculo** (cenários: dentro/fora do expediente, multi-bloco, fuso, grupo, IA suprime/conta).
- **Reviews:** backend, segurança/Pundit (endpoints de schedule, policies), **regressão zero** (SLA nativo + conversa/inbox + relatórios), WhatsApp/grupo, IA/custo, FE+i18n. **Review final GO/NO-GO.**
- **Deploy** `--update-order start-first` com **OK explícito** + rollback armado.
- **Lição registrada:** testar IA com **chamada real** (não só review/eager_load) — o schema strict da Responses API quebrou silenciosamente uma vez.

## 9. Decisões (FECHADAS pelo PO — prontas p/ implementar)
1. ✅ **Troca de agente no meio:** usar sempre o calendário do **agente atribuído ATUAL** no momento da avaliação.
2. ✅ **Sem agente atribuído:** cai no horário da **caixa** (e, se a caixa não tiver, 24/7).
3. ✅ **Limiar de confiança da IA:** **0,6 fixo** (interno, sem campo na tela).
4. ✅ **Auto-aplicar v1:** amarra **OS DOIS** — por **caixa(s)** E por **funil(is)/pipeline**. A config `auto_apply` guarda `inbox_ids` e `pipeline_ids`; no evento conversa-criada, aplica se a conversa cair numa caixa OU num funil selecionado (respeitando exclusão de grupo).
5. ✅ **Calendário do agente:** **um por usuário** (vale para todas as caixas dele).
6. ✅ **Tela:** **remover o item SLA de Configurações de vez**; passa a viver só na aba CRM (abaixo do Dashboard).

## 10. Riscos
- **Regressão no motor de SLA** (compartilhado com o nativo) — mitigado: comportamento novo **só quando os toggles ligam**; 24/7 continua default.
- **EE/Zeitwerk** (modelos novos namespaceados) — mitigado pelo gate `eager_load`.
- **Custo de IA** — mitigado: só no momento da quebra + cache.
- **Detecção de grupo** depende do `source_id` estar no formato JID — confirmado (WAHA). Para canais futuros, a denylist cobre broadcast/newsletter.
- **Fuso/Horário de verão** — usar fuso IANA (ex. America/Sao_Paulo) resolve DST automaticamente.

## 11. Referências
- **Código SLA (mapa):** `enterprise/app/models/{sla_policy,applied_sla,sla_event}.rb`, `enterprise/app/services/sla/evaluate_applied_sla_service.rb`, `enterprise/app/jobs/sla/*`, `config/schedule.yml` (cron 5 min), `app/models/working_hour.rb`, `components-next/Conversation/Sla/SLACardLabel.vue`, `crm.routes.js`, `app/services/crm/cards/payload_builder.rb`.
- **Grupo (comprovado):** Grupo = JID **`@g.us`** em ambos os provedores. WAHA: `payload.from` termina em `@g.us` (https://waha.devlike.pro/docs/how-to/receive-messages/ , .../groups/). Evolution: `key.remoteJid` termina em `@g.us`, individual `@s.whatsapp.net`, e `key.participant` só existe em grupo (https://doc.evolution-api.com/v2/api-reference/group-controller/find-group-by-jid). Denylist extra: `@broadcast`/`status@broadcast`, `@newsletter`. Gotcha `@lid` afeta só 1:1 (WAHA #1907) — não quebra a regra de grupo.
- **Docs relacionados:** [[crm_roadmap_status]], `docs/crm_ai_followup_prd.md` (padrão de IA reusado), progress.md.
