# Agendamento: "Parar avisos" como botão, em mensagem separada, no WhatsApp oficial (#1562)

Refs #1562 · continuação do #1517/#1530 (botão "Ver meu horário"), #1473 (envios ricos).

## Decisão (Rodrigo, 14/10/2026, via Auditoria BM)

"Faz split da mensagem": o "Parar avisos" vira botão numa segunda mensagem. Modelo com dois botões numa mensagem só
foi recusado.

## Quando vale

Só quando `Notices::Text#button?` é verdadeiro: `Notices::Button.allowed?` (sessão, WhatsApp oficial `whatsapp_cloud`
com a janela aberta na conversa, fora do Híbrido), texto sem o link próprio e o corpo cabendo no limite do botão.

1. **Mensagem 1** (`Text#to_s` + `Text#rich_message`): o aviso SEM a linha de parar, com o botão "Ver meu horário"
   para o link de gestão.
2. **Mensagem 2** (`Text#stop_message`), criada logo depois pelo `Notices::Sender`, com o mesmo `Delivery` e o mesmo
   remetente, na conversa da mensagem 1: `crm.booking_v2.notices.stop_prompt` + botão
   `crm.booking_v2.notices.stop_button_label` para `Text.stop_url(invite)` (`/b/<código>?stop_notices=1`). Marcas em
   `content_attributes`: `crm_booking_notice: true`, `crm_booking_notice_part: 'stop'`, `crm_booking_notice_id: <aviso>`.

Exemplo (conta pt_BR, aviso "ao marcar"):

- 1: `content` = `Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.`;
  `rich_message` = `{ "type": "link_button", "label": "Ver meu horário", "url": "https://…/b/<código>" }`.
- 2: `content` = `Não quer mais receber estes avisos?`;
  `rich_message` = `{ "type": "link_button", "label": "Parar avisos", "url": "https://…/b/<código>?stop_notices=1" }`.

Em inglês: "Don't want these reminders anymore?" / "Stop reminders" (14 caracteres; o limite do rótulo é 20).

## O aviso continua um só

`Crm::MeetingNotice` não muda: `message_id` = a mensagem 1. Os tetos (4 por número e 300 por conta em 24 h) contam
avisos, não mensagens; as duas contam como 1.

`Notices::Button.fits?` agora mede só o corpo da mensagem 1 (a linha de parar foi para a 2). A 2 é curta.

## Falhas

- **Erro ao criar a 2** (`Sender#deliver_stop!`): a 1 já foi criada e vai sair; nada é refeito. O aviso fica `sent`,
  com `error_code: stop_part_failed`, o erro vai ao log e ao tracker, e o responsável é avisado pelo
  `Notices::AgentAlert`, evento novo `notice_stop_failed`: a mesma atividade do aviso que não saiu
  (`booking_notice_failed`, motivo `stop_part_failed`), título próprio ("O aviso … saiu, mas a mensagem com o botão
  'Parar avisos' não …") e UMA vez por reunião. A 2 fica fora do `rescue` da 1: um erro até no registro da falha chega
  ao `NoticeDispatchJob`, que não mexe em aviso `sent`.
- **A 2 marcada `failed` depois** (provedor ou `SendGuard`): `NoticeDispatchJob#fail_undelivered!` passou a chamar
  `flag_undelivered_stop!`. Mesma janela do `delivery_failed` (2 h). O SQL acha as mensagens `failed` da conversa da 1,
  criadas depois dela (índice de `conversation_id`), e a marca é conferida em Ruby: `messages.content_attributes` é
  json gravado como texto (`store … coder: JSON`), então `->>` devolve sempre NULL (o spec pegou isso). O aviso fica
  `sent` com `error_code: stop_part_failed` e o responsável é avisado uma vez; nada é reenviado. Aviso já marcado não
  é revisto.
- **A 1 falhou**: `delivery_failed` de sempre (o aviso vira `failed`), com ou sem a 2.

`error_code` num aviso `sent` só aparece aqui; o `Scheduler::RESET` o limpa ao reprogramar, e nenhuma tela o lê.

## O que não muda

- Caminho de texto (WAHA, Híbrido, canal API, 360dialog, modelo da Meta, corpo acima do limite, texto próprio com o
  link): uma mensagem só, com a linha de parar, igual a antes.
- RA-18: a saída de parar existe sempre, em botão (mensagem 2) ou em texto. Se a 2 não sair, o link de gestão do botão
  da 1 abre a página, que também oferece parar os avisos.
- `TestInvite` ("Testar no meu WhatsApp"): o convite não tem linha de parar (`InviteText` + prefixo do teste, sem
  `stop_line`), então não ganha a mensagem 2. Conferido no spec de request (`conversation.messages.outgoing.sole`).

## Validação local

Specs (um arquivo por vez, banco isolado): `spec/services/crm/booking_v2/notices/*` (agent_alert, custom_text,
scheduler, sender_button, sender_hybrid, sender, text), `spec/jobs/crm/booking_v2/notice_dispatch_job_spec.rb` e
`notice_dispatch_job_concurrency_spec.rb`, `booking_pages_notices_spec`, `booking_routes_permissions_spec`; rubocop nos
arquivos tocados. `pnpm i18n:fork:check` não se aplica: `booking_v2.*.yml` não está em `config/fork_i18n.json`.

## Fora deste passo

Teste real no número do Rodrigo (caixa 43 da conta 16), push, PR e deploy. O cartão do painel (`bookingAlert.js`)
não conhece o evento `notice_stop_failed`: mostra o título do backend com o cabeçalho genérico do alerta, sem
mudança no front.
