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
`Notices::Sender` cria só a 1 e enfileira o `Crm::BookingV2::NoticeStopPartJob` com `WAIT = 10 s`. O job:

- relê o aviso; só segue se ele está `sent` e sem `error_code`;
- mensagem 1 `failed`: a 2 não sai; o `NoticeDispatchJob` marca `delivery_failed` e avisa o responsável;
- mensagem 1 apagada: `stop_part_failed` + alerta;
- mensagem 1 sem `source_id` (wamid): ainda não saiu. O `Message` não tem estado "enviando" (`sent` é o padrão na
  criação; os estados são sent/delivered/read/failed), então o sinal de "saiu" é o wamid. Reagenda (`attempt + 1`);
  na tentativa `MAX_ATTEMPTS = 6` (~1 min) desiste com `stop_part_failed` e alerta;
- passada a `WINDOW` (30 min depois da criação da 1) não cria mais: `stop_part_failed` + alerta;
- com o wamid, com o aviso travado (`with_lock`): reavalia a parada (`Sender.stop_reason`, o mesmo do `Sender`:
  opted_out, `Crm::BookingNoticeStop`, `reminders_stopped_at`) e `meeting.scheduled?`; parou ou cancelou → não cria e
  não alerta (motivo quieto). Senão cria a 2, a menos que ela já exista: busca pela marca na conversa, sem corte de
  quantidade, entre a criação da 1 e a `WINDOW`, e confere a marca em Ruby. Como o job nunca cria fora da `WINDOW`, a
  conferência cobre todo o período em que a 2 pode existir.

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

`Crm::MeetingNotice` não muda (sem migration): `message_id` = a mensagem 1. Os tetos (4 por número e 300 por conta em
24 h) contam avisos, não mensagens; as duas contam como 1.

`Notices::Button.fits?` agora mede só o corpo da mensagem 1 (a linha de parar foi para a 2). A 2 é curta.

## Falhas

Todas deixam o aviso `sent` (a 1 saiu), com `error_code: stop_part_failed`, sem reenviar nada, e avisam o responsável
pelo `Notices::AgentAlert`, evento `notice_stop_failed`: a atividade do aviso que não saiu (`booking_notice_failed`,
motivo `stop_part_failed`), título próprio ("O aviso … saiu, mas a mensagem com o botão 'Parar avisos' não …") e UMA
vez por AVISO (dedupe por reunião + tipo do aviso; o `notice_failed` continua uma vez por reunião). Só aviso `sent`
sem marca é marcado, e o alerta que falha vai ao log e ao tracker sem desfazer a marca.

- **Erro no job** (criar a 2, ou enfileirar): sempre log e tracker. Erro de banco (`ConnectionNotEstablished`,
  `StatementInvalid`) relança para o retry do Sidekiq; a trava, a conferência e o `error_code` seguram a repetição.
  Outro erro: o aviso é relido por id e marcado.
- **Job perdido** (crash entre o aviso e o enfileiramento, Redis fora): `Notices::StopPartSweep#flag_missing!`, no
  cron (`NoticeDispatchJob`). Aviso "com botão" é o que tem `rich_message` na mensagem 1, o único caminho que o põe;
  por isso não precisou de campo novo. Sem a 2 depois de `GRACE` (5 min), até `WINDOW + GRACE` → marca e alerta.
  Cliente que parou ou reunião cancelada: nada.
- **A 2 marcada `failed` depois** (provedor ou `SendGuard`): `Notices::StopPartSweep#flag_failed!` (janela de 2 h).
  O SQL acha as mensagens `failed` da conversa da 1, criadas depois dela e pelo mesmo remetente; a marca é conferida
  em Ruby (`messages.content_attributes` é json gravado como texto, `->>` devolve NULL), com guarda para mensagem
  ausente. Busca em páginas ordenadas pelo par (mensagem, aviso), sem cortar casos.
- **A 1 falhou**: `delivery_failed` de sempre (o aviso vira `failed`), com ou sem a 2.

Um erro na conferência não impede a rodada do cron de mandar os avisos vencidos (`sweep_stop_parts!`). `error_code`
num aviso `sent` só aparece aqui; o `Scheduler::RESET` o limpa ao reprogramar, e nenhuma tela o lê.

## O que não muda

- Caminho de texto (WAHA, Híbrido, canal API, 360dialog, modelo da Meta, corpo acima do limite, texto próprio com o
  link): uma mensagem só, com a linha de parar, igual a antes.
- RA-18: a saída de parar existe sempre, em botão (mensagem 2) ou em texto. Se a 2 não sair, a página de gestão
  (`/b/<código>`, sem `?stop_notices=1`), que abre pelo botão "Ver meu horário" da 1, tem o botão "Parar avisos"
  (`public_booking_v2/components/ManageMeeting.vue`, `BOOKING_V2.MANAGE.STOP`, que abre `ManageStop`) enquanto os
  avisos não estão parados. É a saída quando a 2 não sai.
- `TestInvite` ("Testar no meu WhatsApp"): o convite não tem linha de parar (`InviteText` + prefixo do teste, sem
  `stop_line`), então não ganha a mensagem 2. Conferido no spec de request (`conversation.messages.outgoing.sole`).

## Prévia do editor

A prévia (`BookingNoticeTextCard.vue`) mostra sempre o caso de texto, com a linha de parar: é o que vale em qualquer
caixa, e o botão depende da janela aberta, do Híbrido e do limite, que a tela não sabe. Na caixa oficial com o texto
sem o link, a nota (`BOOKING.NOTICES.TEXTS.BUTTON_NOTE`) explica o caso com botão, condicional: "No WhatsApp oficial,
quando a conversa com o cliente está aberta, o link vai num botão "Ver meu horário" e, em seguida, chega uma
mensagem com o botão "Parar avisos". Senão, o link e a frase de parar vão no texto." `FIELDS_HINT` passou a dizer que
a saída de parar vai na frase do fim ou, no oficial com a conversa aberta, no botão.

## Validação local

Specs (um arquivo por vez, banco isolado): `spec/services/crm/booking_v2/notices/*` (incluindo o novo
`stop_part_sweep_spec.rb`), `spec/jobs/crm/booking_v2/*` (incluindo `notice_stop_part_job_spec.rb` e
`notice_dispatch_job_spec.rb`), `booking_pages_notices_spec`, `booking_pages_notice_texts_spec`,
`booking_routes_permissions_spec`; vitest do `BookingNoticeTexts.spec.js`; rubocop, eslint (0 erros; 18 avisos de
i18n que já existiam no arquivo), prettier e `scripts/check-fork-i18n.mjs`.

## Fora deste passo

Teste real no número do Rodrigo (caixa 43 da conta 16), push, PR e deploy. O cartão do painel (`bookingAlert.js`)
não conhece o evento `notice_stop_failed`: mostra o título do backend com o cabeçalho genérico do alerta, sem
mudança no front.
