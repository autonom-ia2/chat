# #1709: re-teste curto em aparelho, rodada 3 (17/10/2026, 07:30 a 07:43)

Nada de produção. Mesmo ambiente das rodadas 1 e 2 (ver `../README.md`): motor `waha-c2y-teste1709` (c2y-rich-5, GOWS,
`GODEBUG=madvdontneed=0,netdns=cgo`) em 127.0.0.1:3712 no M2, demo 3709, banco `chatwoot_demo_1709_int`, conversa do
cliente display 89 (id 94). Horários de Brasília.

## Passo 0: demo atualizada

- Bundle só da ref `feat/1709-ricas-waha` (`ef4c1fd921..4fa3a10e48`, 3 commits: fa29f716b7, 8e024c7f01, 4fa3a10e48),
  levado ao clone do M2 como `bundle/feat-1709-4fa3`.
- Merge em `demo/integrado-1709`: **sem conflito** (nenhum dos 13 arquivos está na lista do `RESOLUCOES.md`). Commit
  `d84bcf2bf demo: integra #1709 4fa3a10e48`. Sem push.
- `reiniciar.sh` com o mesmo `rails-extra.env` (`WAHA_API_KEY`, `WAHA_RICH_NATIVE_ENGINES` com o 3712,
  `FRONTEND_URL=http://host.lima.internal:3709`): `rails=200 vite=2 sidekiq=3`.
- Sessões A 0656 e B 1242: WORKING, capping NONE, sem timelock, antes e depois de cada passo. Motor `restarts=0`
  (de pé desde 06:14:29).
- IA fora da caixa: `autonomia_agent_inboxes` da caixa 8 = 0, `autonomia_agent_events` da conversa 94 = 0.

## Passos

| Passo | Hora | Motor | chat2you (content_attributes) | Aparelho | Resultado |
|---|---|---|---|---|---|
| L1 lista COM cabeçalho (API do painel, atendente) | 07:31:44 | `POST /api/sendList` **201**; `native message sent: kind=sendList chatwoot_message_id=1282`. A sessão B recebeu `listMessage` com `title: "Vistoria"`, `description: "Qual período fica melhor para a vistoria?"`, `buttonText: "Ver horários"`, rows `manha\|1282`, `tarde\|1282`, `noite\|1282` | msg 1282: `rich_message` (options, header "Vistoria") + `rich_message_sent_as: "native"`, status read | **Rodrigo: a lista apareceu no 1242** e ele tocou Ver horários → Tarde | **OK** |
| L1 resposta do cliente | 07:32:42 | webhook de entrada | msg 1283 "Tarde 13h às 17h": `in_reply_to: 1282`, **`selected_option: {id: "tarde", title: "Tarde"}`**. Painel: a lista mostra "O cliente tocou em 'Tarde'" e a resposta cita a lista | — | **OK** |
| L2 options SEM cabeçalho | 07:34:12 | **1 `sendText` 201, nenhum `sendList`** (o único `sendList` da rodada é o do L1). B recebeu `extendedTextMessage` "Prefere atendimento por telefone ou WhatsApp?\n\n1. Telefone\n2. WhatsApp", ack READ | msg 1284: `rich_message_sent_as: "text"`, `rich_message_sent_text` com as opções numeradas. Painel: bolha com "1. Telefone / 2. WhatsApp" e "Enviado como texto" | **confirmação visual do Rodrigo pedida, sem resposta até 07:43** | **OK pelo motor e pelo painel; falta o olho no celular** |
| L3 cliente manda texto | 07:35:19 | seen/typing (11 s)/stop 201, `sendText` 201 | msg 1285 recebida | — | OK |
| L3 cliente apaga para todos | 07:36:18 | `DELETE …/messages/…3EB05DA2…` **200** | 1285: `deleted_by_contact_at: 2026-10-17T10:36:18Z`, conteúdo mantido. A nota do conector virou **atividade escondida** (msg 1286, `message_type` activity, `c2y_hidden`, `revoke_applied_to: 1285`, "Exclusão pelo cliente registrada na mensagem"). Painel: selo "Apagada pelo cliente", texto visível, **nenhuma nota amarela** | — | **OK** (corrige o achado C da rodada 2) |
| L4 empresa apaga mensagem própria (painel, menu Excluir) | 07:40:31 | `DELETE /api/5511941010656/chats/5511926791242@c.us/messages/…3EB02CB0…` ; `Message '3EB02CB0519E2A4A9EB1DD' deleted`. A lista some do histórico da sessão B | 1282 `deleted: true` ("Esta mensagem foi excluída"). A nota do conector virou **atividade escondida** (msg 1287, `c2y_hidden`, `revoke_applied_to: 1282`, "Exclusão pela empresa registrada na mensagem"). Painel: sem nota amarela; a citação na 1283 passa a "Esta mensagem foi excluída" | **confirmação do "mensagem apagada" no 1242 pedida, sem resposta até 07:43** | **OK pelo motor e pelo painel; falta o olho no celular** |

Observação do L4: a mensagem apagada foi a **lista do L1** (1282), e não a do L2, para não apagar a mensagem cuja
confirmação visual ainda estava pendente. O L1 já tinha sido confirmado pelo Rodrigo.

## Motor

- 07:30:15 a 07:43: **0** panic, fatal error, bad pointer, Stream error ou SIGTERM; `restarts=0`.
- Log sanitizado: `motor-log-rodada3-sanitizado.txt` (segredos de 32+ caracteres e o identificador da caixa trocados).

## Duplicidade

Uma mensagem por ação no chat2you (1282 a 1287). O L2 saiu uma vez (1 `sendText`). Nenhuma nota visível nova.

## Prints (1440, olhados)

- `r3-L1.png`: lista "Vistoria" com "O cliente tocou em 'Tarde'" e a resposta citando a lista.
- `r3-L3.png`: L2 como texto numerado ("Enviado como texto") e a bolha "Apagada pelo cliente" com o conteúdo.
- `r3-L4.png`: a lista virou "Esta mensagem foi excluída", sem nota amarela; o L2 continua lá.

## Pendente

- Confirmação visual do Rodrigo para o L2 (texto numerado, uma vez) e o L4 ("mensagem apagada" no 1242).

## Estado final (07:43)

Sessões A e B WORKING, não desconectadas. Motor de pé com o ajuste. Demo em `d84bcf2bf`. Seguidor do log parado.

## Confirmação visual do Rodrigo (17/10, celular do 1242)
- **L2:** "chegou uma vez só como texto", com as opções numeradas.
- **L4:** a lista "Vistoria" virou "mensagem apagada".

Os 4 passos da rodada 3 estão OK no motor, no painel e no aparelho.
