# Contrato F2-A (#1192) — avisos, confirmação, remarcar e cancelar

Fonte das regras: `PLANO-TECNICO.md` §2.5, §8, §10 (TODO d) e termos J5-A1..A8, J2-A6, J2-A9, J3-A11, RA-18.
Backend é dono do contrato; se precisar mudar algo, mude **aqui** e avise no relatório.

## Página de gestão: o mesmo `/b/:code` do convite

`GET /public/api/v2/invites/:code` (já existe) ganha, **só quando `state == 'scheduled'`**:

```json
{
  "code": "AB3K9QXZ", "page_slug": "...", "state": "scheduled",
  "contact_first_name": "Ana", "phone_masked": "(11) •••••-5678",
  "starts_at": "2026-10-20T10:00:00-03:00", "timezone": "America/Sao_Paulo",   // F1-B: "Você já agendou" (fuso da página, IANA)
  "meeting": {
    "starts_at": "2026-10-20T10:00:00-03:00", "ends_at": "2026-10-20T10:30:00-03:00",
    "timezone": "America/Sao_Paulo", "title": "Conversa de 30 min", "agent_name": "Camila",
    "location": { "type": "whatsapp_video", "label": "Vídeo no WhatsApp", "join_url": null, "address": null },
    "status": "scheduled",                    // scheduled | canceled
    "confirmation_status": "pending",         // pending | confirmed | change_requested
    "can_change": true,                       // false quando faltam menos de cancel_until_minutes (120) ou já passou
    "change_deadline": "2026-10-20T08:00:00-03:00",
    "notices_stopped": false,
    "ics_url": "<FRONTEND_URL>/public/api/v2/ics/<token>"
  },
  "can_rebook": false,                         // true só com a reunião cancelada e a página (e o link individual) atendendo
  "contact_whatsapp_url": "https://wa.me/55..."   // ou null
}
```

Reunião cancelada: o link de gestão continua abrindo até 1 dia depois do fim previsto, com `meeting.status = "canceled"` e `can_change = false` (resolve o TODO d do plano: não morre no cancelamento, mostra "Cancelada" e oferece marcar de novo).

**Marcar de novo pelo mesmo convite.** Com `can_rebook: true` (reunião cancelada — pelo cliente, pelo agente ou por outro motivo —, convite ainda válido para gestão e página atendendo), "Marcar outro horário" segue o fluxo do convite na própria `/b/:code`: escolhe dia e hora da página e confirma **sem pedir nome nem WhatsApp**, com o `POST /public/api/v2/booking/:page_slug` de sempre (`invite_code` + `request_id`). O servidor cria uma reunião nova para o mesmo contato, o convite passa a apontar para ela (`meeting`, `scheduled_at`) e o card registra `booking_client_rebooked` (payload `meeting_id`, `starts_at`, `by: "client"`, `canceled_meeting_id`) com aviso ao responsável. Mesmas regras de segurança da reserva por convite: só o contato do convite, conferência travada do convite dentro da transação do `Booker` (dois pedidos ao mesmo tempo: o segundo é `booking_failed` e desfaz a reunião dele), reenvio só com a mesma `request_id`. Convite com reunião marcada (não cancelada) continua recusando reserva nova (`booking_failed`). Convite agendado abre **mesmo com a página pausada** (o cliente ainda precisa poder cancelar); remarcar usa os horários da página. Fora disso: 404 uniforme como hoje.

`?stop_notices=1` no link de gestão (`/b/<code>?stop_notices=1`) é o link de "parar avisos" que vai em toda mensagem automática: a tela abre já oferecendo "Parar avisos" (chama `stop_notices`).

Ações (todas `POST`, sem corpo salvo indicado, respondem **200 com o mesmo JSON do GET**; 404 uniforme; 422 `{ "error": <código> }`):

| Rota | Corpo | Efeito | Erros 422 |
|---|---|---|---|
| `/public/api/v2/invites/:code/confirm` | — | `confirmation_status = confirmed`, `confirmed_at`; avisa o agente **uma vez** (idempotente) | `not_changeable` (cancelada, já começou ou convite sem reunião) |
| `/public/api/v2/invites/:code/cancel` | — | cancela a reunião (libera o horário), cancela avisos pendentes, avisa o agente | `too_late`, `not_changeable` |
| `/public/api/v2/invites/:code/reschedule` | `{ "starts_at": "...", "duration": 30? }` | mesma reunião, novo horário (mesmas regras do `Slots`, sob as mesmas travas do `Booker`); `confirmation_status` volta a `pending`; reprograma avisos (aviso `rescheduled` na hora); avisa o agente | `too_late`, `not_changeable`, `slot_unavailable` (também para data inválida e duração que a página não oferece), `booking_failed` (também quando o serviço de remarcar recusa) |
| `/public/api/v2/invites/:code/stop_notices` | — | grava `crm_booking_notice_stops` do contato + `reminders_stopped_at`; avisos pendentes viram `skipped: 'stopped'` | — |

Horários para remarcar: a tela usa as rotas públicas que já existem (`GET /public/api/v2/booking/:page_slug/slots` e `next_slot`).

## Página pública (`GET /public/api/v2/booking/:slug`)

`notices_enabled` passa a ser verdadeiro quando o perfil tem `notice_inbox_id` utilizável. Com ele verdadeiro, a tela mostra o aviso de consentimento antes de Confirmar (já implementado na F1-B).

Resposta do `POST` de reserva ganha `notice_will_send: true|false` — verdadeiro só quando o aviso "ao marcar" vai de fato sair (caixa de avisos + regra de janela/modelo do `Notices::Sender` permite). A tela de sucesso só fala em "você vai receber uma mensagem" quando verdadeiro (J2-A6).

## Configurações (painel, `booking_pages`)

`GET/PATCH /api/v1/accounts/:id/crm/booking_pages/:id` aceitam e devolvem:

```json
{
  "notice_inbox_id": 12,                       // null = sem avisos
  "notice_preset": "standard",                 // standard (ao marcar, 1 dia antes, 1 h antes) | light (ao marcar, 1 h antes) | minimal (só ao marcar)
  "notice_templates": { "booked": { "name": "...", "language": "pt_BR" }, "day_before": {...}, "hour_before": {...}, "rescheduled": {...} },
  "cancel_until_minutes": 120                  // 0..10080
}
```

`notice_templates`: WhatsApp oficial usa `{ "name", "language" }` (modelo **aprovado** na Meta, conferido na lista sincronizada da caixa); canal API de campanhas usa `{ "id": <WhatsappApiMessageTemplate> }`. Chaves aceitas: `booked`, `rescheduled`, `day_before`, `hour_before`. Variáveis do modelo da Meta (corpo, posicionais): `{{1}}` primeiro nome, `{{2}}` dia e hora, `{{3}}` link de gestão — só as que o corpo usa vão para a Meta. **O texto do modelo tem de levar o `{{3}}`** (a página tem "Parar avisos"): ao salvar, modelo da Meta que já está na lista sincronizada da caixa e não tem `{{3}}` no corpo → 422 com `errors.notice_templates` ("must include {{3}} (manage link): <avisos>"); no envio, modelo aprovado sem `{{3}}` → aviso pulado com `template_without_link`. O modelo também só pode pedir o que o aviso preenche (corpo só com `{{1}}`..`{{3}}`, topo sem variável nem mídia, botão sem link variável): ao salvar, 422 com `errors.notice_templates` ("must only use {{1}}, {{2}} and {{3}}: <avisos>"); no envio, `template_unsupported`. O painel lista os modelos pelo texto (com exemplos no lugar das variáveis), nunca pelo nome técnico, e no canal API de campanhas lê os modelos do canal (`GET /inboxes/:id/whatsapp_api_message_templates`, exige `campaign_view`; sem acesso, a tela diz que não deu para ver) e grava `{ "id" }`. O modelo do canal API recebe depois do corpo o dia, o link e a linha de parar. Caixa inválida → 422 `crm.booking_v2.notice_inbox_invalid`. `notice_inbox_id` e `calendar_inbox_id` só são conferidos contra as caixas que a pessoa enxerga quando o valor **muda**: reenviar a caixa que já está gravada passa (a tela manda os dois em todo PATCH).

`GET :id` também devolve `notice_inbox_options: [{ id, name, channel_type, provider, needs_templates }]` vindo de `policy_scope(::Inbox)` (só WhatsApp Cloud/360dialog, WAHA e API). `needs_templates` = Cloud/360dialog.

`POST /api/v1/accounts/:id/crm/booking_pages/:id/test_invite` `{ "phone": "+55..." }` → 200 `{ "sent": true }` ou 422 `{ "error": "notice_inbox_missing" | "notice_inbox_forbidden" | "page_not_published" | "invalid_phone" | "cannot_send", "reason": "template_required" | "waha_outside_window" | "number_cap" | "stopped" | "conversation_forbidden" | ... }`. Precisa de `agendamento_manage` **e** enxergar a caixa de avisos (`policy_scope(::Inbox)`, o mesmo escopo de `notice_inbox_options`): senão `notice_inbox_forbidden`. Se a mensagem iria para uma conversa que já existe e a pessoa não pode responder nela (`ConversationPolicy#show?`, o critério do envio de mensagem do painel): `notice_inbox_forbidden` com `reason: "conversation_forbidden"`. Número que recusou mensagens ativas ou parou os avisos: `cannot_send` com `reason: "stopped"`. Recusa não cria contato nem convite (o contato novo só é criado quando a mensagem vai sair). Envia ao número informado, pela caixa de avisos, um link igual ao do cliente (J3-A11): um convite real com `metadata.test = true`, fora das listas e dos números (`Crm::BookingInvite.real`); a reunião marcada por esse convite leva `metadata.test = true` e fica fora dos números (`Crm::Meeting.real` — F2-C parte desse escopo). Só texto: no WhatsApp oficial fora da janela, o admin precisa mandar antes uma mensagem ao número da empresa.

## Card e calendário (painel)

`MeetingsController`/serializer da reunião ganham `booking` (verdadeiro quando a reunião veio de uma página de agendamento, `metadata.booking_profile_id`; é o que liga o selo de resposta do cliente no painel — reunião comum não ganha selo, mesmo com o contato tendo parado os avisos), `confirmation_status`, `notices_stopped`, e `notices: [{ kind, due_at, status, skip_reason }]`. Os eventos de reunião do calendário do CRM (`GET .../crm/calendar/events`, `event_type: "meeting"`) ganham `booking`, `confirmation_status` e `notices_stopped` (selo do popover).

Remarcar pelo painel (`PATCH .../crm/meetings/:id`) ou pela agenda do provedor (sincronização) uma reunião de página nova faz o mesmo que o remarcar do cliente: `confirmation_status` volta a `pending` (o cliente confirmou outro horário; o aviso `rescheduled` leva o link para confirmar de novo) e os avisos são reprogramados (aviso `rescheduled` na hora). Está no `Crm::Meetings::RescheduleService`, na mesma transação da mudança.

`notices[].kind`: `booked`, `rescheduled`, `day_before`, `hour_before`. `status`: `pending`, `sending`, `sent`, `skipped`, `failed`. `skip_reason`: `disabled` (flag da conta), `canceled`, `past_due` (qualquer aviso, também "marcado"/"remarcado" atrasado, de reunião que já começou; ou lembrete cujo horário já tinha passado ao reprogramar), `stale` (lembrete cujo vencimento não bate mais com o início da reunião), `too_close` (lembrete que cairia a menos de 30 min de outro aviso da mesma reunião; ao marcar ele nem é criado), `replaced` (o "marcado" que não saiu foi substituído pelo "remarcado"), `opted_out`, `stopped`, `no_inbox`, `no_invite`, `no_contact`, `no_phone`, `unsupported_inbox`, `template_required`, `template_without_link` (modelo aprovado sem `{{3}}`), `template_unsupported` (modelo aprovado que pede variável além de `{{1}}`..`{{3}}`, topo com variável ou mídia, ou botão com link variável), `waha_outside_window`, `number_cap` (4 por número em 24 h — por contato, já que o telefone é único por conta —, somando avisos enviados, avisos saindo agora e testes), `account_cap` (`CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT`, padrão 300 em 24 h, mesma soma). `failed` grava em `error_code` a classe do erro, `interrupted` (o envio morreu no meio: não reenvia) ou `delivery_failed` (a mensagem foi criada, mas o provedor marcou falha de entrega nas 2 h seguintes). Toda falha avisa o responsável (uma vez por reunião).

Avisos ao agente (falha ou pulo que pede ação, confirmou, cancelou, remarcou): pelo caminho de notificação que o CRM já usa — uma tarefa (`Crm::FollowUp` `task`, lembrete, vencendo agora) para o responsável, que o cron de tarefas transforma em push/e-mail conforme as preferências dele — e atividade no card (`booking_client_confirmed`, `booking_client_canceled`, `booking_client_rescheduled`, `booking_client_rebooked`, `booking_notice_failed`, `booking_notices_stopped`; payload com `meeting_id`, `starts_at`, `by` — `"client"` no que o cliente fez, `"system"` em `booking_notice_failed` —, e `from` no remarcar). Falha de aviso avisa **uma vez por reunião**. Parar avisos só registra. Nunca alteram a reunião (J5-A4). O sino (`Notification`) não foi usado: tipo novo exigiria mexer no modelo e nas preferências de notificação do upstream.
