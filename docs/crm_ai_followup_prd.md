# PRD — Follow-up Automático com IA "de onde parou" (por funil)

> **Status:** proposta para análise (não iniciada). Documento de produto + UX + arquitetura técnica.
> **Fork** Chatwoot v4.14.1 EE em `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`. Produção atual: `conn12`. Conta de teste: **6** (Seguro Viagem, pipeline 9). Âncora do roadmap: [[crm_roadmap_status]].
> **Pesquisa que embasa este PRD:** melhores práticas de cadência de follow-up + composição por IA + **regras do WhatsApp Business Platform 2024–2026** (janela 24h, templates de Marketing, pricing por-mensagem, throttle por-usuário, opt-in), cruzadas com o mapeamento real do código existente.

---

## 0. Objetivo e princípios

**Objetivo.** Quando uma conversa **estaciona** (o cliente perguntou algo e ninguém respondeu, OU nós perguntamos/pedimos uma info e o cliente sumiu), uma **IA lê onde a conversa parou** e **monta um follow-up natural** que retoma exatamente daquele ponto. O usuário **liga/desliga isso por funil** e define **quantos follow-ups** e **em que espaçamento**. O envio respeita o **WhatsApp oficial**: dentro de 24h → mensagem livre; fora de 24h → **template** (motor já existe); canal não-oficial → mensagem livre, sem restrição.

**Princípios (não negociáveis):**
1. **Reuso máximo.** O caminho de envio (sessão vs template por janela de 24h), o modo `auto_send_message`, o `DueProcessor` (cron de 1 min), o `ContextBuilder` (transcrição), o motor de IA (`ResponsesClient`/`CredentialResolver`) e a config por-funil (`SettingsUpdater`/`CrmAiSettingsPanel`) **já existem** — esta PR os conecta, não os reinventa.
2. **Natural acima de tudo.** A IA referencia **um** ponto em aberto real (citado da conversa), tom de pessoa ajudando (não marca vendendo), curto (chat), 1 CTA suave. Nunca inventa contexto (anti-alucinação: citar-ou-cair-em-template).
3. **Conformidade WhatsApp é lei** (não opcional): fora da janela de 24h só template de **Marketing pré-aprovado**, exige **opt-in próprio** (a mensagem do cliente NÃO é consentimento para proativos), respeita cap por-usuário (~1 template marketing/24h por contato; erro 131049), horário comercial e STOP/opt-out.
4. **Auto-stop sagrado:** qualquer resposta do cliente, opt-out, ou negócio ganho/perdido **encerra a cadência na hora**.
5. **Identidade Chatwoot:** Vue 3 `<script setup>`, Tailwind `n-*`, components-next, i18n pt_BR+en paridade. Gates de sempre (eager_load, teste visual, deploy com OK).
6. **Zero regressão.** Tudo additivo; o follow-up manual e as automações de etapa existentes seguem intactos.

---

## 1. O que já existe (a fundação — verificado no código)

| Peça | Onde | O que já faz |
|---|---|---|
| **Modo auto-envio** | `Crm::FollowUp` `automation_mode: auto_send_message` + `metadata.message_body` | Follow-up que, ao vencer, envia uma mensagem. |
| **Cron processador** | `Crm::FollowUpDueJob` (`*/1 * * * *`) → `Crm::FollowUps::DueProcessor` | A cada minuto pega `FollowUp.due`, ramifica `process_auto_send`. |
| **Envio WhatsApp-aware** ⭐ | `Crm::FollowUps::MessageSender#deliver_message!` + `Crm::FollowUps::MessagingWindow` | **JÁ decide sozinho:** `can_send_session_message?` (último inbound + janela 24h) → **mensagem de sessão livre**; senão → **template** (nativo `template_params` OU `WhatsappApiMessageTemplate` renderizado). Detecta capacidade WhatsApp por canal (Channel::Whatsapp / TwilioSms whatsapp / Channel::Api campanha). |
| **Transcrição p/ IA** | `Crm::Ai::ContextBuilder#recent_messages` | Lê últimas 12 msgs (`.reorder(id: :desc)`, sem privadas/activity), papel customer/agent, inclui áudio transcrito + caption de imagem. |
| **Motor LLM** | `Crm::Ai::ResponsesClient` (OpenAI Responses API, JSON-schema strict, timeout 120s) + `CredentialResolver` (hook crm_kanban_ai → fallback CAPTAIN) + `Config` (modelos gpt-5.4/mini) | Padrão pronto: `StageClassifier`/`ConversationSummarizer` chamam assim. |
| **Config por funil/etapa** | `Crm::Ai::SettingsUpdater`/`SettingsPresenter` + `AiSettingsController` (GET/PATCH `/crm/pipelines/:id/ai_settings`) + `CrmAiSettingsPanel.vue` (no drawer, master-save) | `pipeline.metadata.ai` (enabled/auto_move/stale_hours) + `stage.metadata.ai_criteria/ai_handoff`. **É aqui que entra a config do follow-up automático.** |
| **Detecção de "parado"** | `Crm::Ai::StaleCardsJob` + `pipeline.metadata.ai.stale_hours` | Acha cards com `last_activity_at < agora - stale_hours` por funil. Reaproveitável como gatilho. |
| **Template engine** | `WhatsappApiMessageTemplate` + `WhatsappApiCampaigns::TemplateRenderer` (vars `contact.name`/`first_name`) + `native_template_params` | O "motor pronto" para fora da janela. Lacuna conhecida: variáveis de corpo (`processed_params`) não são coletadas automaticamente. |
| **Sequência/offsets** | `Crm::StageAutomationStep.delay_seconds` + `StepExecutor` | Padrão de agendar follow-up com offset (`due_at = now + delay_seconds`). Modelo de referência p/ cadência. |
| **Auditoria** | `Crm::Activity` + `Crm::Cards::Broadcaster` | Eventos no timeline + realtime. |

**Conclusão:** o **envio** está ~80% pronto. Falta o **cérebro** (IA que lê onde parou e compõe), o **maestro** (cadência de N toques com auto-stop), a **config/UX por funil**, e a **camada de conformidade** do WhatsApp marketing.

---

## 2. Conceito do produto (o que o usuário vê e decide)

Na tela **Editar funil → painel de IA** (onde já ficam auto-move e handoff), uma **nova seção "Follow-up automático"**:

- **Ativar follow-up automático** (on/off, por funil — decisão global como pedido).
- **Quando disparar:** conversa parada há **N horas** sem resposta (reusa o conceito `stale_hours`, mas próprio do follow-up). Cobre os dois casos: (a) última mensagem é **do cliente** (ele perguntou e ninguém respondeu) e (b) última é **nossa** (pedimos algo e ele sumiu) — a IA entende qual é e adapta o texto.
- **Quantos follow-ups (toques):** ex. 3 (padrão recomendado pela pesquisa: curto e front-loaded).
- **Espaçamento:** offsets por toque (ex. **1d / 3d / 7d** — "intervalo crescente"), editável. Default sugerido baseado em evidência (≈93% das respostas chegam até o dia 10).
- **Liga/desliga (off por padrão):** o usuário precisa **ligar** o follow-up no funil; ligado → **auto-envio** (sem rascunho no MVP).
- **Horário comercial / quiet hours** (não enviar de madrugada) + fuso do contato.
- **Template de reengajamento** (para fora da janela 24h no WhatsApp oficial): selecionar um `WhatsappApiMessageTemplate` **Marketing pré-aprovado** do inbox. *(Obrigatório se o funil usa WhatsApp oficial — ver §3.)*
- **Tom / instruções de marca** (texto livre que entra no prompt da IA — ex. "informal, trate por você, mencione condições do seguro").

No **card**, uma aba/seção mostra: status da cadência ("Follow-up 2/3, próximo em 3 dias"), o texto que será/foi enviado, e botões **pausar / pular / editar / cancelar**.

---

## 3. A grande restrição: WhatsApp oficial (modela todo o design)

A pesquisa confirma as regras (cruzadas em múltiplas fontes BSP; reconferir números exatos nos docs da Meta na implementação):

| Situação | O que pode enviar | Custo |
|---|---|---|
| **Dentro de 24h** do último inbound do cliente | **Mensagem livre** (a IA compõe o texto natural "de onde parou") | **Grátis** |
| **Fora de 24h** (oficial) | **Só template pré-aprovado**; um follow-up de vendas é **categoria MARKETING** | **Sempre cobrado** (pricing por-mensagem desde 01/07/2025) |
| **Canal não-oficial** (ex. Channel::Api campanha, ou outros) | Mensagem livre, "tranquilo" | conforme provedor |

**Consequências que o PRD assume:**
1. **A mensagem natural da IA só vale 100% dentro da janela.** Fora dela, o conteúdo precisa ser um **template aprovado** — a IA **não pode** inventar texto livre. → Solução: a IA **preenche as variáveis** de um template de reengajamento escolhido (ex. `Oi {{1}}, vi que paramos de falar sobre {{2}}...`), com o "de onde parou" entrando como variável. *(Aprovação Meta de templates com variáveis dinâmicas tem limites — ver decisões abertas.)*
2. **Agendar o 1º toque para cair DENTRO da janela quando possível** (ex. algumas horas após parar, ainda <24h) → maximiza a mensagem natural e grátis. Toques seguintes (3d/7d) quase sempre caem fora → template marketing pago.
3. **Opt-in ASSUMIDO** (decisão #2): não exigimos registro de consentimento; quem já conversou é tratado como opt-in. *(A Meta tecnicamente exige opt-in próprio p/ proativo fora da janela — risco de política aceito pelo PO; ver §10.)*
4. **Cap por-usuário:** nunca 2 templates marketing ao mesmo contato em 24h sem resposta (erro 131049, derruba quality rating). A cadência crescente (1d/3d/7d) já evita isso naturalmente; ainda assim, **trava de no máx. 1 template marketing/24h/contato**.
5. **STOP/opt-out** em todo template marketing (rodapé "Responda SAIR") + honrar opt-out → cancela cadência.
6. **Quality rating / messaging limits:** monitorar; recuar se cair. (Full; no MVP, ao menos parar em erro de limite.)

---

## 4. Arquitetura proposta

### 4.1 Config por funil (additivo em `pipeline.metadata.ai.auto_followup`)
```jsonc
pipeline.metadata.ai.auto_followup = {
  "enabled": false,                  // OFF por padrão — o usuário LIGA por funil (decisão #3)
  "max_touches": 3,                  // quantos follow-ups (decisão #5)
  "intervals_hours": [20, 72, 168],  // offset de CADA toque a partir do último inbound: ~20h (dentro da janela), 3d, 7d (decisões #4 e #5; editável)
  "quiet_hours": { "start": 8, "end": 20, "tz": "contact" }, // janela permitida de envio
  "reengagement_template_id": 123,   // WhatsappApiMessageTemplate (Marketing pré-aprovado) p/ fora da janela 24h (decisão #1)
  "tone_instructions": "informal, trate por você…"
}
```
Persistido via `SettingsUpdater` (estendido) → `AiSettingsController` (params novos) → `SettingsPresenter` (devolve p/ o painel). Validação `jsonb_attributes_length`.
**Sempre AUTO-ENVIO quando ligado** (sem modo rascunho no MVP — decisão #3). **Opt-in assumido** (sem gate de consentimento — decisão #2). **Canal: WhatsApp oficial + não-oficial apenas** (decisão #7).

### 4.2 Detecção de "parou" + "onde parou"
- **Parou (stall):** um job varre por funil (reusa o padrão `StaleCardsJob`) cards com conversa cujo **último inbound** foi há ≥ `intervals_hours[0]` E que não estão ganhos/perdidos/arquivados E sem cadência ativa. Identifica também o **tipo de parada** (última msg é do cliente vs nossa) via `message_type`.
- **Onde parou (open loop):** a IA, com a transcrição (`ContextBuilder`), detecta o **ponto em aberto**: pergunta não respondida, info prometida, decisão pendente. Se **não houver** ponto claro → cai em template/mensagem genérica aprovada (não inventa).

### 4.3 Compositor de IA — **`Crm::Ai::FollowUpComposer`** (NOVO)
Reusa `ResponsesClient` + `ContextBuilder` + `CredentialResolver`. Schema JSON strict:
```jsonc
{
  "can_follow_up": true,            // false se conversa encerrada/sem gancho → não envia
  "open_loop": "cliente pediu o valor do seguro p/ Europa e não respondemos",
  "open_loop_source": "citação literal da msg que embasa (anti-alucinação)",
  "message_body": "Oi João! Sobre o seguro pra Europa que você perguntou — consegui o valor...",
  "tone": "friendly",
  "confidence": 0.0_a_1.0,
  "template_variables": { "1": "João", "2": "seguro Europa" } // p/ preencher template fora da janela
}
```
**Guardrails no prompt (system):** 1 ponto em aberto só; tom pessoa-ajudando; ≤ ~2-3 linhas (chat); 1 CTA suave; **não** se desculpar em excesso; **não** ser pushy/urgência falsa; personalização só com fatos da transcrição; PT-BR; respeitar `tone_instructions` do funil. Se `confidence < limiar` ou `can_follow_up=false` → não envia (ou vira rascunho).

### 4.4 Cadência (maestro) — just-in-time, com auto-stop
Padrão **um toque por vez** (não pré-compõe tudo):
1. **Stall detectado** e funil elegível → cria **1 `Crm::FollowUp`** (`automation_mode: auto_send_message`, `metadata.source='ai_followup'`, `metadata.touch=1`, `due_at = parou + intervals_hours[0]`, respeitando quiet_hours).
2. **No vencimento** (`DueProcessor` → ramo novo p/ `source=ai_followup`):
   a. **Re-checa stall:** se o cliente respondeu desde o agendamento → **cancela** a cadência (auto-stop). Se ganho/perdido/opt-out → cancela.
   b. **Compõe** via `FollowUpComposer` (estado atual da conversa).
   c. **Decide canal/janela** (reusa `MessagingWindow`): dentro de 24h ou não-oficial → usa `message_body` natural; fora de 24h oficial → usa `reengagement_template_id` preenchido com `template_variables` (+ checa opt-in + cap 1/24h).
   d. **Envia** via `MessageSender` (já pronto). Audita em `Crm::Activity` (`ai_followup_sent`).
   e. **Agenda o próximo** toque (`touch+1`) em `due_at = enviado + intervals_hours[touch]`, até `max_touches`. Depois disso, encerra.
3. **Modo rascunho:** em vez de enviar, cria a mensagem como **rascunho/sugestão** no card p/ o humano aprovar (reusa padrão `SuggestionRecorder`-like ou `metadata.ai.pending_followup`).

**Onde guardar o estado da cadência:** `card.metadata.ai.auto_followup_state = { active, touch, next_due_at, last_sent_at, stopped_reason }` + cada toque é um `Crm::FollowUp` (auditável, cancelável). *(Alternativa: tabela `crm_ai_followup_plans` — ver §5.)*

### 4.5 Entrega WhatsApp-aware (REUSO — já existe)
`MessageSender#deliver_message!` já faz o branch sessão↔template. Ajustes:
- Passar `message_body` (composto) para o ramo de sessão.
- Para o ramo template: usar `reengagement_template_id` + preencher `processed_params`/render com `template_variables` (fecha a lacuna conhecida de variáveis não coletadas).
- Não-oficial: ramo de sessão livre (já cai nele se não for whatsapp_capable estritamente; validar).

### 4.6 Auto-stop, compliance, frequency cap
- **Auto-stop (hard gates):** resposta inbound (hook no evento de mensagem / `CardSyncer`), opt-out/STOP, negócio won/lost, `max_touches` atingido → cancela follow-ups pendentes da cadência.
- **Opt-in: ASSUMIDO** (decisão #2) — sem gate de consentimento; quem já conversou é tratado como opt-in. *(Risco de política da Meta registrado em §10; decisão do produto.)*
- **Frequency cap:** máx. 1 template marketing/24h/contato; nunca 2 sem resposta (evita erro 131049). Mantido como proteção técnica/qualidade.
- **Quiet hours / fuso:** desloca `due_at` para a próxima janela permitida.
- **STOP footer** no template marketing (proteção de quality rating + opt-out honrado).

### 4.7 Modo de envio (FECHADO)
**Off por padrão; o usuário LIGA por funil** (decisão #3). Quando ligado → **sempre auto-envio** (sem modo rascunho no MVP). A "decisão de qualidade" fica no ato consciente de ligar + nos guardrails do compositor. *(Modo rascunho/aprovação fica como possível enhancement Full, se pedido depois.)*

---

## 5. Modelo de dados
- **Recomendado (MVP):** **sem tabela nova** — reusa `Crm::FollowUp` (cada toque) + `card.metadata.ai.auto_followup_state` + `pipeline.metadata.ai.auto_followup` (config). Aproveita 100% do `DueProcessor`/`MessageSender`/auditoria.
- **Alternativa (full):** tabela `crm_ai_followup_plans` (card_id, pipeline_id, status, touch, next_due_at, stopped_reason, metadata) para histórico/relatório first-class de cadências e métricas (taxa de resposta por toque). Migration additiva, fase 2.

---

## 6. Fluxo ponta a ponta (exemplo real)
> Cliente perguntou "qual o valor do seguro pra Europa 15 dias?" às 14h. Ninguém respondeu.

1. **+`intervals_hours[0]`:** job detecta stall no funil Seguro Viagem (auto_followup on). Cria toque #1 com `due_at` = agora+4h (intervalo[0]), dentro do horário comercial.
2. **Toque #1 vence (ainda <24h da última msg do cliente?**: não — já passou 28h). Janela fechada → **template**. Re-checa: cliente não respondeu, negócio aberto, opt-in ok. IA compõe `open_loop="valor seguro Europa 15d"`, preenche template marketing `reengajamento_v1` → envia. Audita. Agenda toque #2 em +3d.
3. **Cliente responde** "ah sim, quanto fica?" → evento inbound → **auto-stop**: cancela toque #2, marca `stopped_reason=replied`, devolve a conversa ao fluxo normal (e a janela de 24h reabre — IA poderia até responder, mas isso é o fluxo de atendimento, fora desta PR).
4. *(Se não respondesse: toque #2 em +3d, toque #3 em +7d, depois encerra.)*

---

## 7. UX (mock textual)

**Painel de IA do funil — nova seção:**
```
🤖 Follow-up automático
[✓] Ativar follow-up automático neste funil
    Disparar quando a conversa ficar parada por [ 24 ] horas sem resposta
    Número de follow-ups: [ 3 ]
    Espaçamento:  1º após [4h]   2º após [3 dias]   3º após [7 dias]
    Modo:  (•) Enviar automaticamente   ( ) Criar rascunho p/ eu revisar
    Horário de envio: [08:00] às [20:00]  (fuso do contato)
    Template p/ fora da janela 24h (WhatsApp oficial): [ Reengajamento v1 ▾ ]
    Tom / instruções: [ informal, trate por você, foque em seguro viagem… ]
```
**No card (aba Follow-ups):**
```
⏳ Follow-up automático — 2 de 3 · próximo em 3 dias (13/jun 10:00)
   Última mensagem (enviada 10/jun): "Oi João! Sobre o seguro pra Europa…"
   [Pausar]  [Pular próximo]  [Editar texto]  [Cancelar cadência]
```

---

## 8. Escopo MVP vs Full + faseamento

**MVP (uma PR):**
- Config por funil (`auto_followup`) + seção no `CrmAiSettingsPanel` + persistência.
- `FollowUpComposer` (IA lê onde parou + compõe, com guardrails + anti-alucinação).
- Maestro de cadência just-in-time (N toques, intervalos, quiet hours) reusando `Crm::FollowUp` + `DueProcessor`.
- Entrega WhatsApp-aware reusando `MessageSender` (sessão dentro de 24h / template fora) + preenchimento de variáveis do template.
- Auto-stop (resposta/won/lost/opt-out/max), cap 1 marketing/24h, STOP footer. **Opt-in assumido** (sem gate). **Off por padrão + auto-envio quando ligado.**
- Escopo de canal: **só WhatsApp** (oficial + Api campanha). Status no card. Auditoria.
- i18n pt_BR+en, gates, teste visual.

**Full (fases seguintes):**
- Tabela `crm_ai_followup_plans` + relatório (taxa de resposta por toque, opt-out rate, custo de templates).
- Roteamento por risco (auto p/ baixo valor, rascunho p/ alto), few-shot de marca a partir de negócios ganhos, A/B de aberturas/CTA.
- Monitor de quality rating + messaging limits + backoff automático; **MM Lite API** para entrega de marketing.
- Templates dinâmicos / seleção automática de template; intervalo crescente inteligente; send-time jitter.

---

## 9. Decisões (FECHADAS pelo PO — 2026-06-10)
1. **Mensagem fora da janela:** ✅ **SIM** — usar **template de reengajamento pré-aprovado, preenchido pela IA** (a IA não escreve livre fora de 24h). Os templates são cadastrados/aprovados na Meta pelo admin da conta (gestão de templates do inbox WhatsApp); o funil seleciona qual usar.
2. **Opt-in:** ✅ **ASSUMIDO** — sem registro/gate de opt-in; quem já conversou é tratado como consentido. *(Decisão de produto; risco de política em §10.)*
3. **Modo:** ✅ **O usuário precisa LIGAR o follow-up** (off por padrão, por funil). Quando ligado → **auto-envio** (sem rascunho no MVP).
4. **Janela do 1º toque:** ✅ **SIM** — agendar o 1º toque para cair **dentro das 24h** (mensagem natural e grátis) sempre que viável.
5. **Toques/intervalos default:** ✅ **SIM** — 3 toques, front-loaded (1º dentro da janela ~20h, depois 3d, 7d), **editável**.
6. **Multi-conversa:** ✅ **SIM** — follow-up só na conversa **primária** do card.
7. **Canal:** ✅ **Apenas WhatsApp** — oficial (`Channel::Whatsapp`) **e** não-oficial (`Channel::Api` campanha). Sem e-mail/SMS.

## 10. Riscos
- **Conformidade WhatsApp** — template fora da janela (decisão #1) e cap/STOP mitigam a maior parte. **Opt-in assumido (decisão #2) é um risco de política ACEITO pelo PO:** a Meta exige opt-in próprio p/ proativo fora da janela; tratar "já conversou = opt-in" pode gerar reclamações/queda de quality rating. Mitigação parcial: cap 1 marketing/24h, STOP footer, auto-stop, cadência curta. Reavaliar se quality rating cair.
- **Alucinação de contexto** — mitigado por citar-ou-cair-em-template + confidence gate.
- **Spam/fadiga/quality drop** — mitigado por cadência curta, cap por-usuário, quiet hours, STOP, auto-stop.
- **Custo de templates marketing** (cobrado por mensagem) — visível no relatório (full); cadência curta limita.
- **Regressão** — additivo; novo ramo `source=ai_followup` no `DueProcessor` isolado do auto-send manual.

## 11. Referências
- Código (mapa de reuso): `Crm::FollowUps::{DueProcessor,MessageSender,MessagingWindow,MetadataSanitizer}`, `Crm::Ai::{ResponsesClient,ContextBuilder,CredentialResolver,Config,SettingsUpdater,SettingsPresenter,StaleCardsJob}`, `AiSettingsController`, `CrmAiSettingsPanel.vue`, `WhatsappApiMessageTemplate`/`TemplateRenderer`, `Crm::StageAutomationStep`.
- Pesquisa: cadência front-loaded 3–4 toques / intervalo crescente / ~93% respostas até dia 10 (Yesware, Mixmax); auto-stop on reply (HubSpot/Salesloft/Apollo); WhatsApp 24h window + template Marketing sempre cobrado + pricing por-mensagem desde 01/07/2025 + erro 131049 / cap ~2/dia por-usuário + opt-in ≠ inbound (respond.io, ycloud, 360dialog, Infobip, Meta policy); MM Lite (Infobip/Wati).
- Docs relacionados: [[crm_roadmap_status]], `docs/crm_kanban_pr14_plan.md` (handoff/IA), `docs/crm_list_calendar_v2_prd.md` (padrão deste PRD).
