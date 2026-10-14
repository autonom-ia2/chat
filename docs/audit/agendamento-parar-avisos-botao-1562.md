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
2. **Mensagem 2** (`Text.stop_message`), criada pelo `Crm::BookingV2::NoticeStopPartJob` DEPOIS que a 1 saiu, com o
   mesmo `Delivery` e o mesmo remetente, na conversa da mensagem 1: `crm.booking_v2.notices.stop_prompt` + botão
   `crm.booking_v2.notices.stop_button_label` para o link do botão da 1 com `?stop_notices=1`. Marcas em
   `content_attributes`: `crm_booking_notice: true`, `crm_booking_notice_part: 'stop'`, `crm_booking_notice_id: <aviso>`.

## Ordem: por que a 2 sai por um job (ajuste da revisão)

Cada mensagem enfileira o próprio `SendReplyJob` na criação (`Message#send_reply`, `after_create_commit`, fila
`high`). Criadas em sequência, com o Sidekiq em paralelo, a 2 podia chegar ao cliente antes do aviso. Agora o
`Notices::Sender` cria só a 1 e enfileira o `NoticeStopPartJob` com `WAIT = 10 s`. O job:

- relê o aviso; só segue se ele está `sent` e sem `error_code`;
- mensagem 1 `failed` (ou apagada): a 2 não sai; o `NoticeDispatchJob` marca `delivery_failed` e avisa o responsável;
- mensagem 1 sem `source_id` (wamid): ainda não saiu. O `Message` não tem estado "enviando" (`sent` é o padrão na
  criação; os estados são sent/delivered/read/failed), então o sinal de "saiu" é o wamid. Reagenda (`attempt + 1`);
  na tentativa `MAX_ATTEMPTS = 6` (~1 min) desiste com `stop_part_failed` e alerta;
- com o wamid: com o aviso travado (`with_lock`), cria a 2 se ainda não houver, na conversa e depois da 1, mensagem
  com a marca deste aviso (idempotente contra retry e job duplicado).

Alternativa avaliada: disparar a 2 do `SendReplyJob` da 1. É mais direta, mas exige prepend no envio comum do
WhatsApp (o caminho de todas as mensagens do painel). O job fica nos arquivos do agendamento. A Meta não garante a
ordem de entrega no aparelho nem para duas mensagens enviadas em sequência; esperar o wamid da 1 é o que dá para
garantir do nosso lado.

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

- **Erro ao criar a 2** (no `NoticeStopPartJob`, ou ao enfileirá-lo): a 1 já saiu; nada é refeito. O aviso fica `sent`,
  com `error_code: stop_part_failed`, o erro vai ao log e ao tracker, e o responsável é avisado pelo
  `Notices::AgentAlert`, evento novo `notice_stop_failed`: a mesma atividade do aviso que não saiu
  (`booking_notice_failed`, motivo `stop_part_failed`), título próprio ("O aviso … saiu, mas a mensagem com o botão
  'Parar avisos' não …") e UMA vez por reunião (e uma vez por aviso: só aviso `sent` sem marca é marcado).
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

## Prévia do editor

Na caixa oficial (`notice_channel === 'whatsapp_cloud'`) com o texto sem o link, a prévia (`BookingNoticeTextCard.vue`)
não mostra a linha de parar, como o cliente vê; a nota do botão (`BOOKING.NOTICES.TEXTS.BUTTON_NOTE`) passou a dizer
também "Em seguida vai uma mensagem com o botão 'Parar avisos'." (en "Right after, a message with a 'Stop
reminders' button is sent."). Nas outras caixas, e com o link no texto (sem botão), a prévia segue com a linha.

## Validação local

Specs (um arquivo por vez, banco isolado): `spec/services/crm/booking_v2/notices/*` (agent_alert, custom_text,
scheduler, sender_button, sender_hybrid, sender, text), `spec/jobs/crm/booking_v2/notice_dispatch_job_spec.rb` e
`notice_dispatch_job_concurrency_spec.rb`, `booking_pages_notices_spec`, `booking_routes_permissions_spec`; rubocop nos
arquivos tocados. `booking_v2.*.yml` não está em `config/fork_i18n.json`.

Depois da revisão: também `spec/jobs/crm/booking_v2/*` (com o novo `notice_stop_part_job_spec.rb`),
`booking_pages_notice_texts_spec`, vitest do `BookingNoticeTexts.spec.js`, eslint (0 erros; 18 avisos de i18n que
já existiam no arquivo), prettier e `scripts/check-fork-i18n.mjs` (o `booking.json` do front é do catálogo do fork).

## Fora deste passo

Teste real no número do Rodrigo (caixa 43 da conta 16), push, PR e deploy. A dica `FIELDS_HINT` do editor ("a frase
para parar os avisos vai sempre no fim") não mudou. O cartão do painel (`bookingAlert.js`)
não conhece o evento `notice_stop_failed`: mostra o título do backend com o cabeçalho genérico do alerta, sem
mudança no front.
