# Auditoria: quem entrega a conversa, e o que acontece com o rodízio nativo desligado (#1454)

- Data: 13/10/2026
- Base: `origin/main` @ `9810815396` (depois de `git fetch origin`). Branch local `feat/1447-agente-responsavel` @ `10c8080361` lida à parte.
- Escopo: só leitura. Nenhum código alterado, nenhum commit, **produção não consultada** (ver §6, consultas para o Rodrigo rodar).
- "Nativo" = rodízio da caixa: V1 (`AutoAssignment::AgentAssignmentService`) ou V2 (`AutoAssignment::AssignmentJob`/`AssignmentService`, flag de conta `assignment_v2`). Os dois dependem de `inbox.enable_auto_assignment`.

---

## 0. Resumo em 10 linhas

1. **Com o nativo desligado, só um caminho entrega conversa a uma pessoa sozinho: a passagem do CRM (`Crm::Ai::HandoffExecutor`)**, e só quando a IA do CRM avalia a mensagem e decide "transferir". O resto ou depende do nativo, ou só avisa, ou só filtra.
2. **Robô do Agentes IA passando a conversa** (`Responder#handoff_if_signaled`, `skip_for_humans`, `AvisoAoAtendente#escalar`): chama `bot_handoff!`. O `bot_handoff!` só escolhe pessoa pelo nativo. Desligado, a conversa fica com o robô, marcada "à espera de pessoa" **para sempre**. Ninguém a pega sozinho. A caixa inteira é notificada.
3. **n8n via `toggle_status`**: só vira `bot_handoff!` se a conversa estiver `pending`. Nas caixas com robô webhook (n8n e espelho Autonomia) a conversa nasce `open` (`Conversation#set_active_bot_conversation`). Então `toggle_status(open)` vindo do n8n **não faz nada**. Precisa ser confirmado em produção (§6).
4. **"Quem cuida do quê?"** (`Crm::InboxAgentAccess`) é **filtro de visão, não distribuidor**. A frase "recebe as conversas novas dele, um de cada vez" só se cumpre pelo nativo, que usa esse filtro (`Crm::Access::Recipients`). Com o nativo desligado, **nada entrega conversa nova**: a tela promete o que não acontece.
5. **Saída da triagem** (`TriageExit` + `VisibilitySync#reassign`): tira o atendente de triagem e devolve a conversa ao rodízio. Mas `reassign` sai cedo se `enable_auto_assignment` for falso (`visibility_sync.rb:41`). O próprio comentário admite: "Sem rodízio na caixa, a conversa fica Não atribuída" (`triage_exit.rb:5`).
6. **A passagem do CRM depende de 7 condições**: env `CRM_AI_ENABLED`, credencial de IA, IA do funil não desligada, passagem ligada na etapa/funil, card aberto, card ser o assunto atual e a classificação dizer `transferir`. Quando a avaliação vem de mensagem, ainda precisa que a caixa tenha `auto_create_card` (`card_syncer.rb:18-19,61-62`).
7. **O executor do CRM não usa "Quem cuida do quê" como pool.** Usa todos os membros da caixa menos quem o funil esconde (`Recipients.filter`). Quando ninguém da caixa tem acesso restrito, o pool é a caixa inteira.
8. **Não existe "passar para agente de IA" na Atribuição.** O #1447 (branch local) troca o robô por funil (`ResponsibleAgentSync`), mas por fora da Atribuição, e só enquanto um robô atende.
9. **`OpenCardRouter` não existe** no main nem em nenhum ref local (`git log --all -S`).
10. **Corrida real hoje**: o `HandoffExecutor` confere `assignee_id` fora da trava (`handoff_executor.rb:58`), e o `Conversations::AssignmentService` não reconfere. Com o nativo V2 ligado, os dois podem atribuir a mesma conversa e o último a gravar vence.

---

## 1. Base: o que o nativo faz e quando roda

| Fato | Evidência |
|---|---|
| `enable_auto_assignment` nasce **true** no banco. "A maioria das contas desligada" é decisão de quem configura, não o padrão. | `db/schema.rb:3315` |
| V1 roda **só** na troca de status para `open` (antes de salvar) ou na criação. Desatribuir ou trocar de robô não dispara. | `auto_assignment_handler.rb:15-21, 23-39` |
| V1 só escolhe **quem está online**. Se ninguém está, não atribui e **não tenta de novo** (V1 não tem job periódico). | `agent_assignment_service.rb:61-75` |
| V1/V2 não rodam com robô no nome (`assignee_agent_bot_id`). | `auto_assignment_handler.rb:61` |
| V2 exige a flag de conta `assignment_v2` **e** `enable_auto_assignment`. Cron a cada 30 min só em caixa com `assignment_policy`. | `inbox.rb:217-219`, `assignment_service.rb:4-6`, `periodic_assignment_job.rb:7-11`, `config/schedule.yml:64-68` |
| V2 enxerga `awaiting_person` (inclui conversa com robô marcada "à espera de pessoa", #1377). | `assignment_service.rb:35-37`, EE `enterprise/.../assignment_service.rb:59-61` |
| V1 e V2 filtram por funil (`Crm::Access::Recipients`). É aqui que "Quem cuida do quê" entra no rodízio. | `agent_assignment_service.rb:77-80`, `assignment_service.rb:79-89` |
| Time com `allow_auto_assign` escolhe pessoa online do time **sem olhar `enable_auto_assignment`**, mas pula se há robô (`ai_assignee_type`). | `assignment_handler.rb:12-29` |

---

## 2. Caminhos, um por um

Legenda da coluna "Nativo?": **sim** = sem o nativo ninguém é escolhido; **não** = escolhe sozinho; **parcial** = parte depende.

### 2.1 Agente Autonomia sinaliza passagem (Agentes IA)

Cadeia: `Responder#handoff_if_signaled` (`responder.rb:138-155`), `Responder#skip_for_humans` (porta fechada: fora do público ou do horário, `responder.rb:60, 161-174`) e `AvisoAoAtendente#escalar` (IA falhou 2x, `aviso_ao_atendente.rb:45-61`). Os três chamam `bot_handoff!` (`conversation_bot_handoff.rb:32-49`), que faz:
- `assign_person_on_handoff` (V1, `:92-97`): só com `enable_auto_assignment` e sem V2, e só pessoa online;
- sem pessoa e com robô: `wait_for_person_with(robo)` (`:99-102`), o robô segue no nome e a conversa fica marcada `bot_handoff_waiting_since`;
- `enqueue_auto_assignment_after_handoff` (V2, `:105-110`): só com V2 **e** `enable_auto_assignment`;
- `CONVERSATION_BOT_HANDOFF` → `NotificationListener#conversation_bot_handoff` (`notification_listener.rb:2-15`) avisa **todos** os membros da caixa que o funil deixa ver.

| Gatilho | Quem decide a pessoa | Nativo? | Com o nativo desligado | O que a tela promete | Gap |
|---|---|---|---|---|---|
| Instrução do agente devolve `handoff.should`; porta fechada; IA falhou 2x | Só o nativo (V1 online / V2 job) | **sim** | Robô continua no nome e respondendo. Conversa vai para "Não atribuídas" (`awaiting_person`) e **ninguém é atribuído, nunca**. `espelho_no_comando?` passa a dar falso (`operate.rb:58-61`), então o robô não passa de novo. A caixa inteira recebe notificação de "conversa nova". | Agentes: "Já chamei a equipe" (fala do robô). Atribuição: "Nenhum cliente fica sem resposta" (`PASSAGEM.HEROI.HOME_TEXTO`). A Atribuição só vale para a passagem do CRM, mas a tela não diz isso. | **G1.** A passagem do robô **não usa a regra da Atribuição do funil**. Coincidência possível: a fala do robô é mensagem → `CardSyncer` → `Evaluator`, e se a IA do CRM classificar `transferir`, o `HandoffExecutor` atribui. Isso é efeito colateral, não desenho: depende do texto, de 15 s de debounce e das 7 condições do §2.3. |
| `AgentInbox#release_bot_conversations!` (pausar, excluir, tirar canal) | Só o nativo | **sim** | `bot_handoff!(keep_bot: false)` (`agent_inbox.rb:71-78`). Conversa aberta, sem robô e sem pessoa. Fica parada em "Não atribuídas". | — | Aceitável: não é passagem decidida pela IA. Mas ninguém é avisado além da notificação geral. |
| Config `handoff_strategy`/`handoff_target_id` no agente | Ninguém | — | Campo gravado e exibido (`agent.rb:144-148`, `_agent.json.jbuilder:26`), **sem leitor no código**. `HandoffRouter` (BE-06 do PRD do Agentes) não existe no main. | Memória: "quem recebe = Atribuição do CRM, de propósito". | **G2.** Configuração fantasma. Decidir: apagar, ou ler pelo motor único. |

### 2.2 n8n / AgentBot pela API

| Gatilho | Quem decide | Nativo? | Com o nativo desligado | Tela | Gap |
|---|---|---|---|---|---|
| `POST toggle_status` com `status=open`, token de AgentBot, conversa **pending** (`conversations_controller.rb:82-99`) | `bot_handoff!` | **sim** | Igual ao 2.1: robô fica e espera para sempre. | — | **G1** de novo. |
| Mesmo POST, conversa **open** (caixa com robô webhook: nasce open, `conversation.rb:345-356`, `webhook_bot_inbox?` `:198-200`) | Ninguém | — | `bot_handoff?` é falso (exige `pending`, `:95-99`). `set_conversation_status` grava open→open, **nada muda**, robô continua. | — | **G3.** Na caixa n8n/webhook, o "handoff por toggle_status" é **no-op**. Precisa confirmar em produção qual chamada os fluxos n8n usam (§6). |
| `POST assignments` com `assignee_id` humano (liberado para bot, `access_token_auth_helper.rb:2-7`) | Quem o n8n escolher | não | Atribui direto (`Conversations::AssignmentService#assign_agent`, `assignment_service.rb:16-28`). | — | Não passa pelo filtro de funil (`Recipients`) nem pela Atribuição. |
| `POST assignments` com `team_id` | Time (`allow_auto_assign`) | parcial | Com robô no nome, `ensure_assignee_is_from_team` pula (`assignment_handler.rb:14`). Fica com time e sem pessoa. | — | Igual ao G1. |
| `toggle_status` com **token de integração** (`Crm::IntegrationToken`, usuário oculto `role: agent`) | — | — | Hipótese **a verificar**: `Current.user` é `User` (`access_token_auth_helper.rb:63`), então `handle_human_open` (`conversations_controller.rb:180-186`) poria o usuário de integração como atendente, já que `agent?` é verdadeiro. Só vale se o escopo do token permitir `toggle_status`. | — | **G4** (baixa confiança, confirmar com spec). |
| `lib/integrations/bot_processor_service.rb:55-58` (Dialogflow/CSML, ação `handoff`) | `bot_handoff!` | **sim** | Igual ao 2.1. | — | Robôs não usados hoje (memória: só AgentBot n8n e Autonomia). Baixa prioridade. |
| Captain (`enterprise/lib/captain/tools/handoff_tool.rb:58,86`, `response_builder_job.rb:147`, `hook_execution_service.rb:59`) | `bot_handoff!` | **sim** | Igual ao 2.1. | — | Captain não é usado (memória). Só registro. |

### 2.3 Passagem do CRM (Multifunnel)

**Quando dispara.** Só quando a IA do CRM avalia o card e a classificação pede `transferir` (`handoff_executor.rb:76-82`). Cadeia:
- mensagem não privada → `Crm::ConversationObserverListener#message_created` (`conversation_observer_listener.rb:2-10`) → `SyncConversationCardJob` → `CardSyncer#perform`;
- `CardSyncer` só agenda avaliação no ramo `sync_card` (`card_syncer.rb:49, 91-94`), que exige caixa com `auto_create_card` (`:96-112`). Sem isso, cai em `refresh_existing_card`, que **sai na hora quando há mensagem** (`:61-62`). Nesse caso a mensagem nunca agenda avaliação;
- outras origens da avaliação: troca de foco (`focus.rb:25`), assunto novo (`subjects/identifier.rb:93`, `suggestion_responder.rb:64`), card parado (`stale_cards_job.rb`, padrão 6 h) e "Avaliar agora" (`interactive_operation.rb:37`);
- `Evaluator#perform` (`evaluator.rb:12-25`) para cedo se faltar `Config.enabled?` (env `CRM_AI_ENABLED` + CRM ligado, `config.rb:135-137`), credencial, IA do funil (`metadata.ai.enabled != false`), debounce, card aberto ou assunto atual. Depois, `run_handoff` só roda se `handoff_settings[:enabled]` (`:108-111`).

**Resposta direta: sim, só dispara quando a IA do CRM avalia a mensagem, e depende da IA do funil ligada.**

**Quem decide.** `HandoffMemberSelector` (`handoff_member_selector.rb`):
- pool = membros da caixa **da conversa viva** menos quem o funil esconde (`:64-67`), ou uma pessoa fixa (`pool_type: user`, que cai para a caixa inteira se ela não for membro, `:52-60`);
- prefere online (`prefer_online` padrão true, `config.rb:201`); `round_robin` = menos conversas abertas **na caixa** (`:98-102`); `direct` casa o nome sugerido pela IA (`:83-92`).

| Peça | Gatilho | Nativo? | Com o nativo desligado | Tela (i18n `CRM_KANBAN.PASSAGEM`) | Gap |
|---|---|---|---|---|---|
| `HandoffExecutor` r2_direct (`handoff_executor.rb:36-47, 195-221`) | Avaliação → `transferir` | **não** | Atribui por `::Conversations::AssignmentService` e depois `bot_handoff!` (com pessoa já no nome, o nativo nem é tentado). **Funciona sozinho.** | `COMO.NA_HORA_DESC` "Vai direto para quem está online…" — verdadeiro | Guardas fora da trava (`:54-65`): corrida com nativo V2, outra avaliação ou self-assign (**R1**). |
| `hold_online` + `HandoffDrainJob` (a cada 2 min, `handoff_drain_job.rb`, `schedule.yml:116-120`) | Ninguém online | **não** | Segura com o robô e entrega quando alguém fica online. Trava a conversa (`:44-52`). | `RESUMO.COMO_NA_HORA_FORA` "…entrega para quem entrar primeiro, em até 2 minutos" — verdadeiro | Só r2_direct (`:25-28`). Exige `Config.enabled?`. |
| `HandoffExecutor` r3_invite → `HandoffInviter` | Avaliação → `transferir` | **não** | Convida (participante + notificação), não atribui, robô segue (`:170-189`). | `COMO.CONVITE_DESC` — verdadeiro | Convite **sem exigir online** (`select_agent(require_online: false)`, `:30`). |
| `HandoffEscalationJob` (5 min) | Convite vencido | **não** | `renotify` ou `escalate` → atribui o supervisor **só online** se `prefer_online` (`:184-189`), e chama `bot_handoff!`. | `COMO.ESPERA_PASSA` — verdadeiro | Supervisor tem que ser membro da caixa (`:177-179`). |
| `HandoffExpiryJob` (15 min) | TTL 24 h | não | Fecha o ciclo e ninguém mais é avisado. | `COMO.VALE_24H` — verdadeiro | Depois de 24 h a conversa fica com o robô e sem pessoa. Silencioso. |

### 2.4 "Quem cuida do quê?" (Caixas no CRM)

- Dado: `Crm::InboxAgentAccess` (pessoa × caixa: `all_pipelines`, `triage`, `only_own`) + `Crm::InboxAgentPipeline` (funis liberados). `restricts?` (`inbox_agent_access.rb:20-22`).
- Uso: `Crm::Access::Recipients` (`recipients.rb`) **remove** quem não pode ver. Ele é chamado por: nativo V1/V2, `HandoffMemberSelector`, `NotificationListener`, `Evaluator#eligible_agent_names` (`evaluator.rb:94-104`).
- Nada no código lê esse dado para **escolher e atribuir** uma pessoa. As telas só gravam acesso (`crm/caixas/gravador.rb`); nenhuma linha toca `enable_auto_assignment`.

| Gatilho | Quem decide | Nativo? | Com o nativo desligado | Tela | Gap |
|---|---|---|---|---|---|
| Conversa nova chega na caixa | Nativo V1 (online, na criação) / V2 (job) | **sim** | **Ninguém recebe.** Fica em "Não atribuídas". A notificação `conversation_creation` vai a todos que podem ver (`notification_listener.rb:17-30`). | `CRM_CAIXAS.PESSOAS.RODIZIO` "Quem cuida de um assunto recebe as conversas novas dele, um de cada vez." · `CONFIRA.RODIZIO` "Quem recebe as conversas novas, um de cada vez" · `SOZINHO.AUTO_EXEMPLO` "…cria o card e entrega para {pessoa}, a próxima da vez." · `SOZINHO.CHEGOU_EXEMPLO` "…e vai para {pessoa}." (`crm.json:3969, 3978, 3996, 4033`). A "próxima" vem de `quemCuida(form, funil)[0]` (`CaixaPage.vue:112-116`). | **G5.** Promessa sem motor. Mesmo com o nativo ligado: V1 só pega quem está online na hora, sem retry, e com robô na caixa não roda. O "um de cada vez" é o round-robin da **caixa**, não por assunto. |
| Conta sem nenhuma linha restritiva | — | — | `Recipients` não filtra nada (`:76-81`): "quem cuida" = a caixa toda. | idem | O pool por assunto só existe em conta com restrição. |

### 2.5 Saída da triagem

`Crm::Access::VisibilitySync.perform` (`visibility_sync.rb:11-28`), disparado por mudança de card ou vínculo via `CountInvalidation.card_changed!` (`card.rb:181`, `card_conversation.rb:44`, `conversation_linker.rb:64`) → `VisibilitySyncJob`. **Só em conta com linha de acesso** (`AccountFlag.any?`).

| Passo | Nativo? | Com o nativo desligado | Tela | Gap |
|---|---|---|---|---|
| `TriageExit#release_triage_assignee` (`triage_exit.rb:39-50`): tira o atendente de triagem sem o funil, zera o dono do card, devolve ao robô e faz `bot_handoff!(dispatch_event: false)` | **sim** (para entregar) | Atendente sai. Com robô: o robô fica marcado "à espera" **para sempre** (o `bot_handoff!` tenta o nativo e falha). Sem robô: "Não atribuída". Sem evento de handoff, então **sem notificação**. | Comentário do próprio arquivo, `:4-5`: "Sem rodízio na caixa, a conversa fica Não atribuída". | **G6.** A tela de Caixas não avisa isso. |
| `VisibilitySync#reassign` (`:40-49`) | **sim** | `return unless … enable_auto_assignment?` (`:41`) → nada. | — | idem G6. |
| `add_owners_as_participants` (`:57-76`) | não | Dono do card entra como participante e passa a ver. | — | Vê, mas não é atribuído. |

### 2.6 `OpenCardRouter` e `CardSyncer`

- `OpenCardRouter`: **não existe** (`git grep` no main e `git log --all -S OpenCardRouter` vazios; `feat/1150-outro-canal` sem commits além do main). Ignorado.
- `CardSyncer` **não entrega conversa**. Ele espelha `assignee_id` → `card.owner_id` (`card_syncer.rb:168, 199-203`) e agenda a avaliação da IA (que pode virar passagem, §2.3). O sentido é sempre conversa → card, nunca card → conversa. Card criado com dono (`Crm::Cards::Creator#default_owner`, `creator.rb:77-81`) **não atribui a conversa** ao dono. O TriageExit só faz do dono participante.

### 2.7 Desatribuir, devolver para a IA, resolver, reabrir

| Ação | Código | Nativo? | Com o nativo desligado | Gap |
|---|---|---|---|---|
| Desatribuir pela UI ou API | `AssignmentService#assign_agent` com nil → `hand_back_to_inbox_bot` (`assignment_service.rb:16-35`) | — | Com robô na caixa, volta ao robô. Sem robô, "Não atribuída". **O nativo não roda nem ligado** (não há troca de status). | Não existe botão "Devolver para IA": é desatribuir ou atribuir o AgentBot. O CRM carimba a devolução (`DevolucaoAIa.registrar!`, listener `:31-33`) para a IA do CRM não repassar a fala antiga (`handoff_executor.rb:61`). |
| Atribuir robô | `assign_ai_assignee` (`:45-60`) | — | Reabre, tira a pessoa e encerra a espera. | ok |
| Automação/macro "atribuir agente" | `ActionService#assign_agent` (`action_service.rb:43-55`) | não | Atribui direto. | **G7.** Não passa por `Recipients` (pode entregar a quem o funil esconde). Desatribuir por automação (`:44, 76-78`) **não devolve ao robô**, ao contrário do `AssignmentService`. Dois comportamentos para a mesma ação. |
| Automação "atribuir time" | `ActionService#assign_team` → `AssignmentHandler` | parcial | Escolhe online do time se `allow_auto_assign` e sem robô. | idem G1 com robô. |
| Resolver | — | V2 só rebalanceia | Pessoa continua no nome (resolver não desatribui). | ok |
| Reabrir por mensagem do cliente | `Message#reopen_resolved_conversation` (`message.rb:469-481`) | **sim** (se sem dono) | Volta `open` com o mesmo atendente. Sem atendente e sem robô: V1 tentaria só com o nativo ligado. | Conversa reaberta sem dono fica parada. |

### 2.8 Outros caminhos encontrados

| Caminho | Entrega conversa? | Observação |
|---|---|---|
| `ConversationBuilder` (API `assignee_id`, `conversation_builder.rb:36`) | sim, direto | Quem chama decide. Sem funil. |
| Follow-ups do CRM (`crm/follow_ups/*`) | não | `assignee_id` é o dono da tarefa, não da conversa. |
| Campanhas (`campaign_conversation_builder.rb`) | não | A conversa nasce pelo `set_active_bot_conversation`. Sem pessoa. |
| Agenda / booking (`crm/booking_v2/*`, `default_assignee`) | não | Anfitrião da reunião, não atendente. |
| `#1447` `Crm::Ai::ResponsibleAgentSync` (branch local) | troca **robô** | `ResponsibleAgentSync` atribui o espelho do agente responsável pelo funil via `AssignmentService(assignee_type: 'AgentBot')` (`responsible_agent_sync.rb:128-139`). Só quando já há robô atendendo e ninguém esperando pessoa (`:87-90`). Não é passagem de pessoa → robô. |

---

## 3. Mapa de dono

| Peça | Dono |
|---|---|
| `Autonomia::Agents::Operate::Responder` (`handoff_if_signaled`, `skip_for_humans`), `AvisoAoAtendente`, `AgentInbox#release_bot_conversations!`, `Agent#handoff_strategy`, `Operate.espelho_no_comando?`, `NotaDoEncaminhamento`, `EventLogger` | **Agentes IA** |
| `Crm::Ai::Evaluator`, `HandoffExecutor`, `HandoffMemberSelector`, `HandoffInviter`, jobs Drain/Escalation/Expiry, `DevolucaoAIa`, `Crm::Ai::Config` (handoff), tela Atribuição (`settings/assignmentPolicy/pages/passagem/*`), `Crm::Access::*` (Recipients, TriageExit, VisibilitySync), `Crm::InboxAgentAccess`, Caixas no CRM, `CardSyncer`, `#1447` `InboxAiAgent`/`ResponsibleAgentSync` | **Multifunnel (CRM)** |
| `ConversationBotHandoff` (#1377), `Conversations::AssignmentService`, `AutoAssignment::*`, `conversations_controller#toggle_status`, `ActionService`, `NotificationListener` | **Núcleo compartilhado** (fork do Chatwoot). Mexer aqui afeta os dois lados: avisar as duas sessões. |

---

## 4. Proposta: "Atribuição como motor único"

### 4.1 Princípio

Toda decisão de "quem atende agora" passa por **um serviço**, `Crm::Entrega`. Ele generaliza o `HandoffExecutor` sem a parte da IA (classificar fica no `Evaluator`). Os caminhos dizem **que** a conversa precisa de alguém. O motor decide **quem** e **como**, pela regra da Atribuição do funil do card em atendimento.

```
Crm::Entrega.new(conversation:, motivo:, origem:, sugestao: nil).perform
  motivo ∈ robo_pediu | porta_fechada | ia_falhou | n8n | triagem | conversa_nova | reaberta | devolvida_sem_dono
  origem = quem chamou (log e métrica). sugestao = nome sugerido pela IA (só modo direct)
  → Result(:entregue_pessoa | :entregue_robo | :convidado | :segurando_online | :sem_regra | :ignorado, motivo)
```

Dentro dele:
1. **Trava e relê** a conversa (`conversation.with_lock`, na ordem conversa → card, a mesma do Drain e do CardSyncer). Sai se já tem pessoa ou se está resolvida/adiada (salvo `reaberta`).
2. **Acha o card em atendimento** (`ConversationCardFinder` / `conversa_em_atendimento`). Sem card ou sem CRM na caixa → **fallback** (§4.4).
3. **Lê a regra** (`Config.handoff_settings(stage, pipeline)`). Regra desligada → `:sem_regra` → fallback, nunca silêncio.
4. **Monta o pool** (§4.2) e escolhe com o `HandoffMemberSelector`, que é reaproveitado.
5. **Executa o modo**: na hora (`AssignmentService` + fim do robô, sob a trava), segurar online (marca para o Drain, que passa a chamar `Crm::Entrega`), convite (`HandoffInviter`) ou robô (§4.3).
6. **Uma linha de log** por saída (o `registrar` atual) e uma atividade no card.

O `HandoffExecutor` vira um adaptador: confere `requested?`, cooldown e devolução, e chama `Crm::Entrega(motivo: 'ia_crm')`.

### 4.2 "Quem cuida do quê" como pool

Pool de uma conversa na caixa C, para o funil F do card em atendimento:
1. membros de C (`inbox.members`);
2. ∩ quem pode ver por funil (`Recipients.filter`, o de hoje);
3. ∩ **quem cuida de F em C** = pessoa com `InboxAgentAccess` em C com `all_pipelines` ou `InboxAgentPipeline(F)`. Sem nenhuma linha na caixa, vale todo mundo (como hoje). Conversa **sem card** (triagem) → quem tem `triage`;
4. `pool_type: user` da Atribuição restringe a uma pessoa dentro desse pool (com o fallback atual para o pool inteiro);
5. menos administrador **só se** a Atribuição não o marcou (decisão de produto: hoje admin "vê tudo" mas não deveria entrar no rodízio por padrão. **Perguntar ao Rodrigo**).

Assim "Quem cuida de um assunto recebe as conversas novas dele, um de cada vez" passa a ser verdade pelo `Crm::Entrega(motivo: 'conversa_nova')`. Ele é chamado quando o card nasce (`Creator`/`CardSyncer`/`Subjects::Applier`) ou quando a conversa entra sem robô. O round-robin passa a contar conversas abertas **do funil na caixa**, não da caixa toda.

### 4.3 "Passar para agente de IA" em Quem recebe

- A Atribuição ganha `destino: 'pessoa' | 'agente_ia'` (no mesmo jsonb `metadata.ai.handoff` do funil e da etapa, sem migração). Com `agente_ia`, guarda `autonomia_agent_id`.
- A lista de agentes na tela sai de `Crm::Ai::Config.destinos_para` / `responsible_agent` (#1447): só agente não apagado **com vínculo (`AgentInbox`) na caixa da conversa**. Sem vínculo, a opção aparece desabilitada com o motivo ("{nome} não atende nesta caixa").
- A execução reaproveita `ResponsibleAgentSync#trocar`: `AssignmentService(assignee_type: 'AgentBot')` com o espelho, atividade `ai_agent_changed` e `EVENTO_TROCA` para o Agentes IA responder. Isso exige que `trocar` vire método público (ou que se extraia um `Crm::Ai::EntregarAoAgente`).
- O nome mostrado vem de `agent.name` (já em `destinos_para`: `agente_nome`).
- Laço: robô A passa → Atribuição manda ao robô B → B passa → … Guarda: o motor não entrega a um robô que já passou esta conversa no mesmo episódio. Depois disso, cai para pessoa.

### 4.4 Fallback sem CRM (ou sem regra)

Nesta ordem:
1. nativo **ligado** → deixa o nativo agir, sem chamar outro motor;
2. nativo desligado → **o comportamento de hoje, mas honesto**: robô segue com a marca "à espera", notificação a quem vê, e a tela de Atribuição/Caixas diz "Nesta caixa ninguém é escolhido automaticamente". Opcional (decisão do Rodrigo): um "rodízio mínimo" do próprio motor (pool = caixa ∩ Recipients, online, menos conversas), ligado por caixa.

### 4.5 Convivência com o nativo ligado

- **Um dono por caixa.** O motor responde "o CRM cuida desta conversa?": caixa com CRM + card aberto + regra ligada. Se sim, o nativo **pula** a conversa. Ponto de corte único:
  - `AutoAssignment::AssignmentService#unassigned_conversations` e o EE: excluir conversas com marca `crm_delivery_pending` (ou com card aberto cuja regra está ligada; preferir marca barata em `additional_attributes`, gravada pelo motor sob a trava);
  - `AgentAssignmentService#reassignment_still_needed?`: mesma marca;
  - `ConversationBotHandoff#assign_person_on_handoff`/`enqueue_auto_assignment_after_handoff`: chamar `Crm::Entrega` **antes**. Se ele entregou ou segurou, não chama o nativo.
- Se o CRM não cuida, o nativo faz o que faz hoje.
- Para não atribuir duas vezes: toda gravação de pessoa (motor e nativo V2 com `FOR UPDATE SKIP LOCKED` + `awaiting_person`) reconfere `assignee_id IS NULL` **dentro** da trava. Isso fecha a corrida R1 de hoje.

### 4.6 Quem chama o motor (todos os caminhos)

| Caminho | Hoje | Depois |
|---|---|---|
| `Responder#handoff_if_signaled` / `skip_for_humans`, `AvisoAoAtendente#escalar` (Agentes IA) | `bot_handoff!` | `bot_handoff!` → `Crm::Entrega(motivo: robo_pediu/porta_fechada/ia_falhou)` dentro do concern. **Agentes IA não muda nada no código deles**: o ponto de entrada fica em `ConversationBotHandoff`. |
| `toggle_status` do n8n | `bot_handoff!` só se pending | aceitar também `open` com `ai_assignee` = robô da caixa (`bot_handoff?` olha `ai_assignee`, não `pending`) → mesmo concern. **Núcleo.** |
| `HandoffExecutor`/`Drain`/`Escalation` | atribuem sozinhos | chamam `Crm::Entrega` |
| `TriageExit` | `bot_handoff!(dispatch_event: false)` + `VisibilitySync#reassign` (só nativo) | `Crm::Entrega(motivo: triagem)`; `reassign` só cai no nativo quando o CRM não cuida |
| Conversa nova / card novo (Caixas) | nativo | `Crm::Entrega(motivo: conversa_nova)` no `after_commit` do card ou do vínculo (fora da transação do card) |
| Automação/macro "atribuir agente" | direto | mantém (escolha explícita de pessoa), mas passa por `Recipients` (G7) |
| Desatribuir | volta ao robô | mantém. Opcional: sem robô na caixa, `Crm::Entrega(motivo: devolvida_sem_dono)` |

### 4.7 Riscos

| # | Risco | Mitigação |
|---|---|---|
| R1 | Corrida executor × nativo V2 × self-assign × outra avaliação (guardas fora da trava hoje) | Trava conversa → card. Reconferir `assignee_id` sob a trava. V2 já usa `SKIP LOCKED`. Spec de concorrência com dois threads. |
| R2 | Deadlock ABBA (card → conversa em algum caminho novo) | Regra única: sempre conversa antes de card (como Drain/Escalation/CardSyncer `SyncLock`). |
| R3 | Cross-account | Pool só de `conversation.inbox.members`. `AssignmentService` busca em `conversation.account.users`. Agente IA só via `AgentInbox.kept.find_by(account_id: inbox.account_id, …)`. `pool_id`/`escalation_user_id` relidos na conta. Spec: id de usuário/agente de outra conta salvo no jsonb → ignorado. |
| R4 | Loop de avaliação (atribuir → `assignee_changed` → avaliação → atribuir) | Guardas atuais (`already_assigned`, cooldown, `DevolucaoAIa`) continuam no adaptador do Evaluator. O motor é idempotente. |
| R5 | Loop robô ↔ robô (§4.3) | Proibido entregar a um robô que já passou esta conversa no episódio. |
| R6 | Silêncio (regra desligada, sem pool, ninguém online sem retry) | Todo `Result` ≠ entregue deixa log + atividade. Segurar online sempre tem o Drain. "Sem regra" cai no fallback, nunca em nada. |
| R7 | Núcleo compartilhado (`ConversationBotHandoff`, `toggle_status`, `AssignmentService`) | PR do núcleo separado, com aviso às sessões Agentes IA e Orquestração. Spec de não-regressão do #1377. |
| R8 | Performance: o motor roda em todo `bot_handoff!` | Sai cedo sem CRM na caixa (uma consulta). `AccountFlag` para acesso. Job assíncrono quando não precisa ser na mesma gravação. |

### 4.8 Testes de cenário (specs que reproduzem a conta real)

Todos com `inbox.enable_auto_assignment = false`, salvo onde indicado:
1. Robô Autonomia sinaliza → card com regra "na hora" → pessoa online do funil recebe; robô cala.
2. Igual, **ninguém online** → robô segue, marca de espera; o Drain entrega quando alguém fica online (`travel`).
3. **Sábado** (porta fechada `skip_for_humans`) → passa pela regra; ninguém online → segura até segunda.
4. n8n `toggle_status(open)` em conversa **open** de caixa webhook → entrega pela regra (hoje: no-op).
5. n8n `toggle_status(open)` em conversa pending → idem.
6. Triagem: atendente sem o funil sai → quem cuida do funil recebe; sem ninguém → a tela/log diz por quê.
7. Conversa nova sem robô em caixa com "Quem cuida do quê" → a primeira pessoa do funil, depois a segunda (um de cada vez, por funil).
8. Conversa em **outra caixa** do mesmo card → pool da caixa da conversa viva.
9. Destino **agente de IA** → espelho do agente vinculado vira `ai_assignee`; sem vínculo → cai para pessoa e loga.
10. Nativo **ligado** + regra do CRM ligada → só um atribui (contar `ASSIGNEE_CHANGED` = 1).
11. Nativo ligado + caixa sem CRM → nativo como hoje (não-regressão).
12. Concorrência: avaliação e job V2 ao mesmo tempo → uma atribuição só.
13. Cross-account: `pool_id`/agente de outra conta no jsonb → ignorado.
14. Devolver à IA (desatribuir) sem pedido novo → não reentrega (`DevolucaoAIa`).
15. IA do CRM desligada no funil → robô passa → fallback honesto (sem atribuir, com log `sem_regra`).

---

## 5. Lista de gaps (para virar Issues)

| # | Gap | Dono | Prioridade |
|---|---|---|---|
| G1 | Robô (Autonomia/n8n/bot) passa e, com o nativo desligado, ninguém é escolhido. Fica "à espera" para sempre. Não usa a regra da Atribuição. | Núcleo + CRM (motor). Agentes IA só é avisado. | Alta |
| G3 | `toggle_status(open)` do n8n é no-op em caixa webhook (conversa já open) | Núcleo | Alta (confirmar em prod) |
| G5 | Caixas promete "recebe as conversas novas, um de cada vez" / "entrega para {pessoa}" sem motor quando o nativo está desligado | CRM | Alta (texto agora, motor depois) |
| G6 | Saída da triagem só reatribui pelo nativo | CRM | Alta |
| — | Passagem do CRM depende de `auto_create_card` para ser avaliada por mensagem | CRM | Média |
| G2 | `handoff_strategy`/`handoff_target_id` do agente sem leitor | Agentes IA | Baixa (decidir) |
| G7 | Automação atribui sem filtro de funil; desatribuir por automação não devolve ao robô | Núcleo | Média |
| G4 | Token de integração em `toggle_status` pode virar atendente (hipótese) | Núcleo | Média (verificar com spec) |
| R1 | Corrida executor × nativo | CRM | Média |
| — | Passagem "na hora" não respeita "Quem cuida do quê" como pool (só como filtro de visão) | CRM | Alta (é o pedido) |

**Textos honestos, já, sem motor novo:** Caixas (`PESSOAS.RODIZIO`, `CONFIRA.RODIZIO`, `SOZINHO.AUTO_EXEMPLO`, `CHEGOU_EXEMPLO`) condicionados a `inbox.enable_auto_assignment`. Atribuição (`HEROI.HOME_TEXTO` "Nenhum cliente fica sem resposta") dizendo que vale quando a IA do CRM chama a equipe, não quando o robô do Agentes IA passa.

---

## 6. Produção: não consultada (o que confirmar)

A Issue pede código **e** produção. Esta auditoria não acessou produção. Consultas só de leitura para o Rodrigo rodar (`psql` via SSM, conforme o runbook):

```sql
-- 1. Quantas caixas com rodízio nativo desligado, por conta
SELECT account_id, count(*) FILTER (WHERE NOT enable_auto_assignment) AS desligadas, count(*) AS total
FROM inboxes GROUP BY account_id ORDER BY desligadas DESC;

-- 2. Contas com assignment_v2 (feature_flags é bitmask; conferir no console de flags) — ou listar policies
SELECT i.account_id, count(*) FROM inbox_assignment_policies p JOIN inboxes i ON i.id = p.inbox_id GROUP BY 1;

-- 3. Conversas presas "à espera de pessoa" (G1) e há quanto tempo
SELECT account_id, inbox_id, count(*), min((additional_attributes->>'bot_handoff_waiting_since')::timestamptz)
FROM conversations
WHERE status = 0 AND assignee_id IS NULL AND additional_attributes ? 'bot_handoff_waiting_since'
GROUP BY 1,2 ORDER BY 3 DESC;

-- 4. Funis com passagem ligada (na etapa ou no funil)
SELECT p.account_id, p.id, p.name, p.metadata->'ai'->'handoff'->>'enabled' AS funil,
       count(s.id) FILTER (WHERE s.metadata->'ai_handoff'->>'enabled' = 'true') AS etapas_ligadas
FROM crm_pipelines p LEFT JOIN crm_stages s ON s.pipeline_id = p.id GROUP BY 1,2,3,4;

-- 5. Como o n8n passa (G3): status das conversas de caixas webhook quando o robô saiu
--    (precisa cruzar com o log de requests de toggle_status/assignments do token do bot)
```

Também confirmar a env `CRM_AI_ENABLED` no serviço de produção (só o nome, sem expor valor).

---

## 7. Arquivos citados (origin/main)

`app/models/concerns/conversation_bot_handoff.rb`, `app/models/concerns/auto_assignment_handler.rb`, `app/models/concerns/assignment_handler.rb`, `app/models/conversation.rb`, `app/models/message.rb`, `app/models/inbox.rb`, `app/services/auto_assignment/{agent_assignment_service,assignment_service}.rb`, `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`, `app/jobs/auto_assignment/{assignment_job,periodic_assignment_job}.rb`, `app/services/autonomia/agents/operate.rb`, `app/services/autonomia/agents/operate/{responder,aviso_ao_atendente}.rb`, `app/models/autonomia/agents/{agent,agent_inbox}.rb`, `app/controllers/api/v1/accounts/conversations_controller.rb`, `app/controllers/api/v1/accounts/conversations/assignments_controller.rb`, `app/controllers/concerns/access_token_auth_helper.rb`, `lib/integrations/bot_processor_service.rb`, `app/services/conversations/assignment_service.rb`, `app/services/action_service.rb`, `app/listeners/{notification_listener,crm/conversation_observer_listener}.rb`, `app/services/crm/ai/{evaluator,handoff_executor,handoff_member_selector,config,observer,devolucao_a_ia}.rb`, `app/jobs/crm/ai/{evaluate_card_job,handoff_drain_job,handoff_escalation_job,handoff_expiry_job,stale_cards_job}.rb`, `app/services/crm/conversations/card_syncer.rb`, `app/services/crm/access/{recipients,triage_exit,visibility_sync,count_invalidation,account_flag}.rb`, `app/models/crm/{inbox_agent_access,inbox_agent_pipeline}.rb`, `app/services/crm/cards/{creator,focus}.rb`, `app/javascript/dashboard/i18n/locale/pt_BR/crm.json` (2909-3040, 3950-4046), `app/javascript/dashboard/routes/dashboard/crm/caixas/{pages/CaixaPage.vue,components/EtapaConfira.vue,components/EtapaPessoas.vue}`, `app/javascript/dashboard/routes/dashboard/settings/assignmentPolicy/pages/passagem/passagem.js`, `config/schedule.yml`, `db/schema.rb`.
Branch `feat/1447-agente-responsavel`: `app/models/crm/inbox_ai_agent.rb`, `app/services/crm/ai/responsible_agent_sync.rb`, `app/services/crm/ai/config.rb` (diff).

---

## 8. Notas da implementação (PR do #1454)

- **Fila de quem espera** (`Crm::Ai::HandoffDrainJob`, a cada 2 min): até 500 conversas por rodada, as menos tentadas primeiro (`tentado_em` na marca `crm_entrega`), pelo índice parcial `idx_conversations_crm_entrega_fila`. Sem estado fora do banco. Uma rodada por vez (`pg_try_advisory_lock`), 45 s para cada passo (conversas e cards antigos), com a ordem alternada a cada rodada, e `lock_timeout` de 5 s por linha (ocupada, a conversa é pulada e volta na rodada seguinte).
- **Presença congelada na rodada (aceito):** a presença de cada conta é lida uma vez por rodada. Quem entra online no meio de uma rodada só recebe na seguinte, até 2 minutos depois (no pior caso, cerca de 110 s de rodada, já que o teto é checado entre itens, mais o intervalo do cron).
- **Pendências registradas (revisão final):** (a) conversa cuja linha fica travada por outra sessão volta no topo da fila (`tentado_em` não grava) e custa até ~10 s por rodada até a outra transação terminar; causa raiz seria transação longa alheia, a observar em produção pelo log `[crm][entrega] fila ... trava ocupada`; (b) o `lock_timeout` de 5 s vale só para a fila (drain); `Crm::Entrega` chamado pelo `bot_handoff!`, triagem e IA do CRM usa o timeout padrão do banco, como antes; (c) o log de duração é uma linha por conversa (até 500 a cada 2 min).
- **Medida no banco de teste (M4):** 500 conversas na fila; ninguém online, cerca de 3 s por rodada; todos online (500 atribuições), cerca de 12 s.
- **Convite que nunca sai:** passado o prazo do convite contado da marca, a conversa continua segura com o robô, a marca diz `nao_conseguimos_chamar` e sai um aviso só (atividade no card e notificação aos administradores da caixa). Não volta ao rodízio nativo.
