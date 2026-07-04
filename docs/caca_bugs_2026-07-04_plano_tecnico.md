# Caça a Bugs/Issues — Plano de Ataque Técnico (2026-07-04)

> Investigação **causa-raiz, read-only**, em paralelo (5 agentes por cluster de domínio) + verificação em docs
> oficiais (AWS SES, Meta Cloud API) e AWS CLI real (profile `hub2you`, conta `354307071110`).
> Nada foi alterado ainda. Este doc é para **aprovar antes de implementar**.
>
> Convenção de esforço: **P** (≤2h) · **S** (≤½ dia) · **M** (1–2 dias) · **L** (3+ dias).
> Cada track vira **branch/worktree própria**; merges agrupados para evitar cascata de deploy blue-green.

---

## Sumário de diagnóstico (9 pontos)

| # | Tema | Diagnóstico curto | Tipo | Esforço | Risco |
|---|------|-------------------|------|---------|-------|
| 1 | E-mail conta 6 não chega em Conversas | Teste valida **SMTP de envio**, não recebimento. Inbound não montado (IMAP off ou SES-receiving inexistente) | Infra/Ops | S–L | Baixo |
| 2 | Verificação de domínio SES pendente (3 e 6) | Pior que pendente: **zero identidades de domínio** no SES + conta **sandbox** + produção **DENIED** | Infra/Ops | M | Baixo–Médio |
| 3 | Botão "ativar agente" pede testar antes | **Não há trava real**; efeito de UX (botão "Testar antes" primário + toggle ativar some em `draft`) | Código FE | S | Baixo |
| 4 | Badge do funil corta a etapa com >1 funil | `max-w-[8rem] truncate` fixo no chip | Código FE | S | Baixo |
| 5 | Eventos CRM/Kanban em Automações e Macros | Eventos de card existem mas só no barramento **ActionCable**, não no dispatcher de automação. Macro não tem gatilho | Código FE+BE | M–L | Médio |
| 6 | Marcação de campanha Meta/Google no Kanban | WhatsApp/Twilio **já capturam `referral`** (enterrado). FB/IG descartado. **Google sem caminho de entrada** | Código FE+BE | S–M (WA) / L (Google, bloqueado) | Baixo–Médio |
| 7 | Atributos custom usados pelas IAs de CRM | IA recebe só o **schema** dos atributos, não os **valores** já preenchidos | Código BE | M | Médio |
| 8 | Regressão em Gestão de IA (corte LLM 29/30) | **Sem regressão.** Corte = `xhigh→high` em 4 features mini (#42). Decisão de custo | — | P (opcional) | Baixo |
| 9 | Fluxo KB-first na criação do agente | Viável, mas **1 bloqueador**: draft do agente nasce no 1º turno do chat; KB-first precisa do draft antes | Código FE+BE | M–L | Médio |

---

## Ponto 1 — E-mail conta 6 não chega em Conversas

**Causa-raiz.** No Chatwoot o "teste de e-mail" valida **conexão SMTP de envio**, não recebimento. Conversa só nasce quando uma mensagem **entra** por um de dois trilhos independentes:

- **A) IMAP pull** — Chatwoot busca ativamente na caixa do cliente. Gatilho `Channel::Email#imap_enabled = true` (`app/models/channel/email.rb:10-14`) ou provider `microsoft`/`google` com OAuth. Job: `app/jobs/inboxes/fetch_imap_emails_job.rb` → `app/mailboxes/imap/imap_mailbox.rb:8` cria contato/conversa/mensagem.
- **B) ActionMailbox push** — provedor externo entrega no Chatwoot. Ingress por ENV `RAILS_INBOUND_EMAIL_SERVICE` (`config/initializers/mailer.rb:47`, default `relay`); SES-receiving exige `ACTION_MAILBOX_SES_SNS_TOPIC` (`:51`). Roteamento `app/mailboxes/application_mailbox.rb:10-15` → `reply_mailbox.rb`.

Envio é SMTP puro (`config/initializers/mailer.rb:26-27`); **não há SDK AWS SES no envio**.

**Hipótese dominante:** inbox da conta 6 é **SMTP-only / IMAP não habilitado** → só envia, nada entra. Bate exato com o sintoma. Segunda hipótese: setup pretendia SES-receiving, que **fisicamente não existe** (ver Ponto 2: zero receipt rules/SNS).

**Ação (Ops, precisa do operador — read-only não alcançou o Postgres de prod):**
1. Console Rails prod: `Channel::Email.where(account_id: [3,6]).pluck(:id,:email,:imap_enabled,:provider,:imap_address)` + conferir `ENV['RAILS_INBOUND_EMAIL_SERVICE']` e `ENV['MAILER_INBOUND_EMAIL_DOMAIN']`.
2. Decidir o modelo de recebimento: **(a) IMAP/OAuth** (mais simples, sem DNS; recomendado se a conta 6 tem mailbox própria) · **(b) forward + ingress relay/Postmark** · **(c) SES-receiving** (mais pesado, hoje 100% ausente).
3. Enviar um e-mail **real de fora** (não o botão "testar") e olhar log de `FetchImapEmailsJob`/`ReplyMailbox`.

**Esforço:** S (habilitar IMAP) a L (montar SES-receiving). **Risco:** baixo (config de inbox, reversível). **Não vira PR de código** — é operação. Vira **Issue de Ops** com checklist.

---

## Ponto 2 — Verificação de domínio SES pendente (conta 3 e 6)

**Evidência AWS CLI real (profile `hub2you`, conta `354307071110`):**
- `sesv2 list-email-identities` us-east-1 e sa-east-1: **vazio**. us-east-2: só 3 **endereços de e-mail** de outro projeto (Viotto), nenhum domínio dos tenants.
- `get-email-identity` p/ `hub2you.ai`, `chat.hub2you.ai`, `autonomia.solutions`: **NotFoundException** em todas as regiões.
- `sesv2 get-account`: **`ProductionAccessEnabled: false` (SANDBOX)** nas 3 regiões; us-east-2 com pedido de produção **DENIED**.
- `list-receipt-rule-sets` e `sns list-topics`: **vazios** (recebimento SES inexistente).

**Causa-raiz.** Não é "verificação pendente" — **nenhuma identidade de domínio dos tenants existe no SES**. O "pendente" que aparece é estado interno do Chatwoot (`channel_email.verified_for_sending`), não reflete SES real.

**Para verificar um domínio (docs oficiais AWS):**
1. **Easy DKIM — 3 CNAMEs** (obrigatório): `sesv2 create-email-identity --email-identity <domínio>` devolve 3 tokens → publicar `<token>._domainkey.<domínio> CNAME <token>.dkim.amazonses.com`. Detecção até 72h. (docs.aws.amazon.com/ses `verify-domain-dkim`)
2. **Custom MAIL FROM** (alinhamento DMARC): `mail.<domínio> MX 10 feedback-smtp.<região>.amazonses.com` + `TXT "v=spf1 include:amazonses.com ~all"`.
3. **DMARC**: `_dmarc.<domínio> TXT "v=DMARC1; p=none; rua=mailto:dmarc@<domínio>"`.
4. **Sair do sandbox:** novo pedido de produção com use-case Hub2You (o de us-east-2 foi DENIED com texto da Viotto). Sandbox = 200 msgs/24h, só p/ destinatários verificados.

**Ligação com Ponto 1 (sem rodeio):** verificação/sandbox afetam **envio**, não **recebimento**. Verificação de domínio **não é** a causa do e-mail não chegar. O único elo: se escolher SES-receiving no Ponto 1, verificar o domínio é o degrau 1.

**Esforço:** M por domínio (criar identidade + DNS + esperar) + M pra reabrir produção. **Risco:** baixo–médio (DNS reversível; risco real é reputação/aprovação AWS). **Vira Issue de Ops** (decisão de região: padronizar **us-east-1**, que suporta receiving).

---

## Ponto 3 — Botão "ativar agente" pede testar antes

**Causa-raiz: não existe trava real.** Backend `agents_controller#update` permite `status`/`enabled` livres; o model `Autonomia::Agents::Agent` valida só `name` + `agent_type` — **nenhuma regra ligando `active` a "foi testado"**. É efeito de UX:
- `BuilderReview.vue:251-289` põe "Testar antes" (`TEST_FIRST`) como ação primária/primeira; o usuário lê como passo obrigatório.
- "Testar" **navega** pra outra aba (`AgentBuilderPage.vue:309-315`); ao voltar, o toggle de ativar no header **só aparece p/ agente não-draft** (`AgentPanelPage.vue:201`). Draft testado fica sem controle óbvio de ativar → sensação de "me obriga a testar".

**Abordagem (UI/flow, sem mudar backend):**
1. Reordenar/reestilizar `BuilderReview.vue:254-289`: ativar (`ACTIVATE_INTERNAL`/`CONNECT_ACTIVATE`) vira **primário**; "Testar antes" secundário. Interno ativa em 1 clique (sem dependência de inbox).
2. (Opcional M) Mostrar o toggle ativar no header p/ `draft` também.
3. **Preservar** a única trava real: agente externo exige inbox elegível (`canConnect` + rollback-to-draft em falha de conexão).

**Arquivos:** `BuilderReview.vue`, `AgentPanelPage.vue`, i18n `en/agents.json` (`AGENTS.REVIEW.*`). **Esforço:** S. **Risco:** baixo.

---

## Ponto 4 — Badge do funil corta a etapa com >1 funil

**Causa-raiz.** `app/javascript/dashboard/components-next/Conversation/ConversationCard/CrmConversationStageChip.vue:36` usa `max-w-[8rem] truncate` fixo. Com >1 funil o rótulo vira `funil · etapa` (`:22-24`) e estoura os 128px → corta sem indicação. Pai `CardLabels` (`ConversationCard.vue:259-263`) não previne overflow.

**Abordagem:** aumentar `max-w` (ex. `12rem` ou responsivo), manter `title` (tooltip já existe `:32`) + indicador de truncagem opcional; considerar `flex-wrap` para 2ª linha em telas largas. **Arquivos:** `CrmConversationStageChip.vue` (+ possível ajuste no container). **Esforço:** S. **Risco:** baixo (testar mobile).

---

## Ponto 5 — Eventos CRM/Kanban em Automações e Macros

**Causa-raiz (corrigida pós-Codex).** Eventos de card **já existem** (`lib/events/types.rb:66-73`: `CRM_CARD_CREATED/UPDATED/MOVED/WON/LOST/...`), emitidos em `app/services/crm/cards/mover.rb` + `broadcaster.rb`. Eles vão ao browser via ActionCable **e** já chegam ao `Rails.configuration.dispatcher` pelo caminho de **webhooks** (`Crm::Activity after_commit → Crm::Webhooks::Emitter`, `crm.card.*`). O que falta **não** é o barramento: é que **`AutomationRuleListener` não implementa handlers `crm_card_*`** e a **UI/model de automação não expõem esses eventos** (`automation_rule.rb:38-51`, listener `:1-90`: só eventos de conversa/mensagem). **Macro não tem conceito de gatilho** — sempre roda manual sobre uma conversa (`macro.rb:33-35`). Já existe motor CRM-nativo limitado: `crm/stage_automation_step.rb` (3 ações: follow-up/owner/move).

**Abordagem (2 trilhos aditivos):**
- **(A) Eventos CRM → gatilhos de Automação:** o dispatch já existe (via `Crm::Webhooks::Emitter`). Adicionar handlers no `AutomationRuleListener` (`crm_card_moved` etc.) que resolvem `card.primary_conversation` e rodam filtro/ação; **guardar card sem conversa**. Registrar `event_name` + condições CRM (`pipeline_id`, `stage_id`, `from_stage_id`). FE: `settings/automation/constants.js` + i18n. **Reusar o emit existente — NÃO adicionar um segundo `dispatch` no Broadcaster/Mover (evitar disparo duplo com o caminho de webhook).**
- **(B) Ações CRM em Automação/Macro:** adicionar `move_card_to_stage`/`create_follow_up` aos allowlists (`AutomationRule#actions_attributes`, `Macro::ACTIONS_ATTRS`), reusando `Crm::Cards::Mover`. FE + i18n.

**"Eventos CRM como gatilho de macro" é mismatch** — macro não tem trigger. Reenquadrar como (A) trigger de automação ou (B) ação CRM.

**Risco:** (1) **loop de recursão** (move → evento → automação que move) — guard `performed_by_automation?` (padrão já existe `automation_rule_listener.rb:73`); (2) **disparo duplo** — o mesmo evento já alimenta webhooks CRM; diferenciar "webhook externo" de "gatilho interno" e reusar o emit, sem duplicar. Enterprise: `AsyncDispatcher.prepend_mod_with`; gatear atrás de `Crm::Config.enabled?`. **Esforço:** (A) M–L, (B) M. **Arquivos:** `broadcaster.rb`/`mover.rb`, `automation_rule_listener.rb`, `automation_rule.rb`, `conditions_filter_service`/`action_service`, `macro.rb`, FE constants + i18n.

---

## Ponto 6 — Marcação de campanha Meta/Google no Kanban/Conversas

**Causa-raiz.** WhatsApp Cloud API e Twilio **já capturam o objeto `referral` inteiro** (todos os campos Meta), mas enterrado na 1ª mensagem, sem virar atributo/label/tag:
- WhatsApp: `app/services/whatsapp/incoming_message_base_service.rb:213-216` → `content_attributes['referral']` (helper preserva o objeto cru).
- Twilio: `app/services/twilio/referral_params_helper.rb:2-31` mapeia `source_id/source_type/source_url/headline/body/ctwa_clid`.
- **FB/IG/Messenger: referral DESCARTADO** — builders (`app/builders/messages/messenger/message_builder.rb`, `facebook/message_builder.rb`) não leem `referral`/`ad_id`/`postback.referral`.
- **Google: não existe canal de entrada** no fork (`app/services/google/*` = só Calendar). Sem webhook, sem dado. Honesto: não implementável sem criar canal.

**Campos oficiais Meta** (WhatsApp `referral`): `source_url`, `source_type` (ad/post), `source_id`, `headline`, `body`, `media_type`, `ctwa_clid`. Messenger/IG (`messaging.referral`/`postback.referral`): `ref`, `source`, `type`, `ad_id`, `referer_uri`. (developers.facebook.com — CTWA webhooks + messaging_referrals; re-verificar por versão do Graph API na hora.)

**Abordagem:**
- **Ganho barato (S–M):** promover `referral` da 1ª mensagem para `conversation.additional_attributes['campaign']` (`{source:'meta', source_id, ctwa_clid, headline, source_type}`) + aplicar label `meta-ad`/`campaign:<id>` (mecanismo de label existente) → o `Crm::Card` espelha a conversa (via `card_conversations`), então a tag flui pro Kanban. Guardar "só na criação/1ª mensagem".
- **Paridade FB/IG (M, opcional):** ler `referral`/`ad_id` nos builders Messenger/FB.
- **Google (L, bloqueado):** só via parse de UTM/`gclid` do `referral.source_url` em funil landing→WhatsApp; sem webhook Google.

**Arquivos:** `incoming_message_base_service.rb`, `incoming_message_service_helpers.rb`, `twilio/referral_params_helper.rb`, `crm/sync_conversation_card_job` (espelho), serviço aplicador de label, FE sidebar/card + i18n. **Risco:** baixo (WA, aditivo); médio (FB/IG toca OSS core).

---

## Ponto 7 — Atributos custom usados pelas IAs de CRM

**Causa-raiz.** O pipeline de IA de CRM recebe só o **schema** dos atributos (onde extrair), não os **valores já preenchidos**:
- `app/services/crm/ai/context_builder.rb:10-20,42-54` monta contexto (summary/recent_messages/current_stage/temporal) — **sem** `custom_attributes`.
- `app/services/crm/ai/stage_classifier.rb:117-136` inclui `attribute_schema` (definição), **não** os valores de contact/conversation.
- `app/services/crm/ai/classifier_prompt.rb:86-104` só instrui **extrair** novos valores; não **ler** os existentes.

Efeito: a IA decide estágio/handoff sem o contexto de negócio (Indústria, Orçamento, Prazo) que o humano vê.

**Abordagem:** `ContextBuilder` ganha `existing_attributes` (contact + conversation `custom_attributes`, filtrando vazios); `StageClassifier#user_input` passa `attributes`; `classifier_prompt` ganha seção EXISTING_ATTRS (prefixo estável p/ cache; valores vão no input dinâmico, não no prefixo). **Framing como DADO não-instrução** (anti-injeção). **Arquivos:** `context_builder.rb`, `stage_classifier.rb`, `classifier_prompt.rb`. **Esforço:** M. **Risco:** médio (bloat de token → filtrar vazios/truncar; injeção → framing). **Escopo aberto:** avaliar se o Copiloto/`autonomia/*` também deve receber (este ponto é CRM-classificação).

---

## Ponto 8 — Regressão em Gestão de IA (corte LLM 29/30)

**Não há regressão.** "Gestão de IA" = painel de uso/custo (`CrmAiUsagePage.vue`, rota `crm/ai-usage`, tabela `crm_ai_usage_events`). Config de modelo+motor em `app/services/crm/ai/config.rb`.

Duas mudanças em `main`:
- **#36 `5983d2005` (29/jun):** subiu efforts por feature (classify/auto-move `high→xhigh` etc.).
- **#42 `cb7410e42` (30/jun) — o "corte":** reverteu `xhigh→high` nas 4 features mini (classify/followup/callback/meeting-summary — tocou `config.rb` + `meeting_summary_service.rb` + comentário em `callback_runner.rb`). Só rebaixa `reasoning_effort`. **Não** é threshold, whitelist, nem gate; modelo/schema/fluxo idênticos. Thresholds de decisão intactos (`AUTO_MOVE_THRESHOLD=0.75`, `SUGGESTION_THRESHOLD=0.55`).

**Veredito honesto (pós-Codex):** **sem mudança de gate/threshold/schema** — nenhuma regra de decisão mudou. O que não dá pra *provar* é qualidade: rebaixar `xhigh→high` no auto-move pode reduzir marginalmente a precisão da classificação que move card sozinho. **Decisão de custo consciente, severidade BAIXA** — não é regressão de software.

**Fix opcional (P):** efforts são constantes hardcoded (`config.rb:24-28`) — tornar cada `*_REASONING_EFFORT` ajustável por ENV com default `high` (resolve medo de regressão + custo, sem redeploy). Ver [[pending-reasoning-effort-env]]. **Não bloqueia nada.**

---

## Ponto 9 — Fluxo KB-first na criação do agente

**Causa-raiz do incômodo.** O builder é página única com passos internos (`AgentBuilderPage.vue`). No passo "conversa" há **grid de 2 colunas** (`:562-649`): esquerda `BuilderChat` (chat), direita `BuilderKnowledgePanel` (KB) — **os dois juntos** confundem. Os sinais `actuation` (internal/external) e `withKnowledge` já são capturados (`AgentTypePicker.vue:100-105`).

**Bloqueador de arquitetura:** hoje o **draft do agente nasce no 1º turno do chat** (`AgentBuilderPage.vue:104-112`). KB-first esconde o chat → **não há draft pra anexar fontes** (`BuilderKnowledgePanel.vue:104-105` exige `agentId`). Resolver "criar draft antes do chat" é a porta para (a)/(c)/(d)/(e).

**Viabilidade por requisito:**
- **(a)** só KB primeiro (esconder chat) p/ internal/+KB: M FE + S/M BE (garantir draft-id cedo). Risco médio (a lógica de limpeza de draft vazio depende do "draft no 1º turno").
- **(b)** msg "até 5 min": **P/S** (i18n + render). Sem risco.
- **(c)** limite 30 bases: precisa **guard server-side** em `sources_controller#create` (hoje sem limite) + FE desabilitar dropzone em 30. S+S. **Confirmar definição:** conta linhas `Source kind:knowledge`?
- **(d)** auto-abrir chat ao terminar: M. Sinal "pronto" já existe (`autonomiaSources.js:80-87 getAllReviewed` + `knowledge_confidence`). Tratar falha/skip (fallback "abrir chat agora").
- **(e)** builder já conhece a base: **retrieval já satisfaz** (Playground roda pipeline contra entries aceitos). Falta só semear a **entrevista** do construtor com `knowledge_summary` (L, reordena o "IA fala primeiro").

**3 perguntas de PO (bloqueiam início):**
1. KB-first dispara quando `actuation===internal`, quando `withKnowledge===true`, ou só na interseção?
2. "Máx 30 bases distintas" = 30 linhas `Source` (kind knowledge)? Mídia fora?
3. Em (d), se fonte falha ou usuário não sobe nada, o que desbloqueia (botão manual vs timeout)?

**Arquivos-chave:** `AgentBuilderPage.vue`, `BuilderKnowledgePanel.vue`, `AgentTypePicker.vue`, `autonomiaSources.js`, `sources_controller.rb`, `playground_controller.rb`, i18n. **Esforço:** M–L. **Risco:** médio.

---

## Sequenciamento e worktrees

Cada track = **branch/worktree própria** (`git worktree`), merge agrupado por onda para 1 deploy limpo (evita cascata blue-green — ver [[deploy-stacked-prs-cascade]]).

**Onda A — Quick wins (código, baixo risco):**
- P4 badge funil (S) · P3 ativar agente (S) · P6-WhatsApp referral→label/Kanban (S–M) · P8 ENV effort opcional (P)
- 1 PR cada ou 1 PR combinado FE; Codex review; merge agrupado → 1 deploy.

**Onda B — Projetos de código (médio):**
- P7 custom attrs → IA (M) · P5 eventos CRM→automação, trilho A+B (M–L) · P9 KB-first (M–L, **após responder 3 perguntas de PO**).

**Onda C — Ops/Infra (não são PRs de código):**
- P1 e-mail conta 6 (probe prod DB + decisão trilho) · P2 SES (criar identidades + DNS + reabrir produção). Issues de Ops com checklist e 🟢 por ação (DNS/infra).

**Fora de escopo agora (honesto):** P6-Google (sem canal de entrada) · P6-FB/IG paridade (M, opcional).

**Cross-project safety (VPS multi-tenant):** mudanças em dispatcher/automação (P5) e SES/DNS (P2) tocam base compartilhada — gatear atrás de `Crm::Config.enabled?`, feature flag, e nunca omitir `env` em updates de infra. Reviewer + tester antes de merge ≥30 linhas.
