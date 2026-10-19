# #1709: a lista nativa chega ao WhatsApp do cliente, mas não aparece no app (17/10/2026)

Investigação feita só com leitura. Nada foi enviado pelo WhatsApp, o motor e as sessões não foram alterados e produção não foi tocada. Os bancos das sessões foram copiados com `docker cp` para `/tmp` no M2, lidos com `sqlite3 -readonly` e apagados no fim.

## 1. Fatos observados

### 1.1 O que a sessão B (cliente, 5511926791242) recebeu

A mensagem `3EB0CCE17F77617E88B399` (05:43:21) está no banco das duas sessões. Na sessão A ela tem `from_me=1`; na B, `from_me=0`, `is_real=1`. O `Message` e o `RawMessage` gravados na B são idênticos:

```json
{"listMessage": {
  "title": "Qual período fica melhor para a vistoria?",
  "buttonText": "Ver horários",
  "listType": "SINGLE_SELECT",
  "sections": [{"title": "Ver horários", "rows": [
    {"title": "Manhã", "description": "8h às 12h", "rowID": "manha|1234"},
    {"title": "Tarde", "description": "13h às 17h", "rowID": "tarde|1234"},
    {"title": "Noite", "description": "18h às 20h", "rowID": "noite|1234"}]}]}}
```

- `listType=SINGLE_SELECT`, `buttonText`, seção com título e linhas com `rowId`, `title` e `description`: tudo presente.
- **Não vem `description` (o corpo da lista) nem `footerText`.**
- Não tem invólucro: `IsViewOnce`, `IsViewOnceV2`, `IsEphemeral` e `IsDocumentWithCaption` são `false`, e o `RawMessage` é igual ao `Message`. Não tem `deviceSentMessage`.
- Não tem `messageContextInfo`: nem `messageSecret`, nem `deviceListMetadata`.
- No envelope (`Info`): `Type=media`, `MediaType=list`, `PushName=Autonom.ia`, `VerifiedName=null` (a 0656 não aparece como conta comercial verificada). O remetente chegou como LID (`109913195958474@lid`, com `SenderAlt` = 0656).
- Só existe **uma** lista em 17/10 nos dois bancos (05:43:21). O relatório do teste real também diz que ela não foi reenviada.

Por que o corpo sumiu: `app/services/waha/rich_payload.rb:141-149`. Sem `header`, o corpo vira `title` e `description` só vai quando há cabeçalho (`description: (@body if header)`). O rodapé só vai se vier no `rich_message`.

### 1.2 O que o motor põe no stanza

- O GOWS monta a lista em `gows-plus/src/server/messages.go:233-278`: um `ListMessage` direto (sem invólucro), `SINGLE_SELECT`, e acrescenta o nó `<biz><list v="2" type="product_list"/></biz>` por `extra.AdditionalNodes`.
- No whatsmeow upstream, `getMessageContent` ainda poria um segundo `<biz><list v="2" type="single_select"/></biz>` (`send.go:1173-1181`). O GOWS usa o fork `devlikeapro/whatsmeow` (`go.mod`: `replace … v0.0.0-20261014061703-201f37bd2d44`). Nesse commit o trecho está comentado, pelo commit `57e27fc` "[WAHA] No "biz" node". Então **o stanza leva um nó `biz` só, o `product_list`**.
- O binário `/app/gows` da imagem tem a string `product_list` e não tem `quality_control` nem `biz_bot`. Isso confere com o fonte acima, mas não prova byte a byte qual nó saiu. O whatsmeow não guarda o nó `biz` no lado de quem recebe.
- O tipo do stanza (`type=media`, `mediatype=list`) é o mesmo que o Baileys usa (`getMediaType` → `'list'`).
- O GOWS **não aceita proto livre**. O `MessageRequest` do gRPC (`gows.proto:418-460`) só tem campos tipados (`text`, `media`, `poll`, `list`, `location`, `event`, `contacts`, `pollVote` e `forward`, que reenvia uma mensagem já guardada). O `ListMessage` do gRPC tem `title`, `description`, `footer`, `button` e `sections`. O `SendListMessage` do WAHA exige `title` e `button` não vazios; `description` e `footer` são opcionais.

### 1.3 Incidente durante a leitura (para registro)

Às ~06:14 um `GET …/chats/5511941010656@c.us/messages` (só leitura) voltou "Empty reply from server". O container `waha-c2y-teste1709` estava sendo recriado: `Created=06:14:29 BRT`, `RestartCount=0`, `docker ps` "Up 47 seconds". Um container novo (e não um reinício) não vem de uma requisição HTTP. O mais provável é a outra sessão de teste. Depois disso não chamei mais a API de mensagens; li só cópias do banco.

## 2. O que as fontes dizem sobre a lista aparecer (2025–2026)

| Fonte | Data | O que mostra |
|---|---|---|
| [WAHA, Send List](https://waha.devlike.pro/docs/how-to/send-messages/) | atual | "List Messages are fragile creatures and may stop working at any time." Só em conversa 1:1. Recomenda texto ou enquete como alternativa. Sobre botões: "DEPRECATED – Buttons do not work at the moment!". |
| [Baileys PR #2849](https://github.com/WhiskeySockets/Baileys/pull/2849) + [evidências](https://github.com/digows/baileys/tree/1441cf324309bc0acb8e34ade6e0d65d38a90edc/baileys-native-interactive-evidence) | 06–07/10/2026 | O perfil **N04**, uma `listMessage` SINGLE_SELECT direta com `<biz><list type="product_list" v="2"/></biz>`, sem `messageContextInfo` e sem nó `bot`, foi **vista e tocada no iOS e no Web**, com `listResponseMessage` capturado. É o mesmo formato do GOWS. Diferenças: o N04 tem `description` e `footerText`. O próprio autor avisa que versões e contas não foram anotadas, e o roteiro do N04 parece ter sido em conversa consigo mesmo (`native-render-candidates.mjs`; os testes com outro destinatário ficaram no `…-recipient-candidates`). |
| [itsliaaa/baileys #25](https://github.com/itsliaaa/baileys/issues/25) | 10/07/2026, WA 26.26.73 | `!list` funciona em Android, Web e iOS. Esse fork manda `listMessage` com `description`, `messageContextInfo` (secret e `deviceListMetadata`) e `<biz actual_actors="2" host_storage="2" privacy_mode_ts=…><list v="2" type="product_list"/><quality_control …/></biz>`. É um relato só, de um tester. |
| [neonize #191](https://github.com/krypton-byte/neonize/issues/191) | 29/05/2026 | `nativeFlowMessage` com `single_select` aparece no Android e **não no iOS**; `quick_reply` aparece nos dois. |
| [whatsmeow #1144](https://github.com/tulir/whatsmeow/issues/1144) | 05/2026 | Com whatsmeow, `quick_reply` e `cta_url` aparecem no iOS e no Android; `single_select`, `flow` e `address_message` dão "mensagem não compatível". |
| [whatsmeow #1235](https://github.com/tulir/whatsmeow/issues/1235) | 27/08/2026 | Para `interactiveMessage`, o servidor julga o nó `biz` em texto puro: sem `biz` passa e não aparece; `<interactive>` cru dá `ack 479`; o formato completo (atributos e `quality_control`) é entregue e aparece. Mostra também que o whatsmeow upstream manda `<list type=…>` derivado do tipo da lista. |
| [AriOliv/whatsapp-mcp PR #15](https://github.com/AriOliv/whatsapp-mcp/pull/15) | 05/10/2026 | Diz que a lista precisa do nó com `product_list` e corrige o whatsmeow para isso. Não foi conferido no iPhone ("will be checked live after deploy"). Evidência fraca. |
| [Baileys #2465](https://github.com/WhiskeySockets/Baileys/issues/2465) | 04/2026 | Relatos de listas que não chegam ou não aparecem como lista no app, sem diagnóstico. |

Busquei "list message not showing", "buttons iOS", `interactiveMessage` e `nativeFlowMessage` nos repositórios devlikeapro/waha, tulir/whatsmeow, WhiskeySockets/Baileys e wppconnect. No WAHA não há issue sobre lista invisível no iOS. Os de botões (#1227) e do wppconnect (#2412) são de 2024–2025 e não trazem formato.

## 3. Causa provável

Separando o que está descartado, o que fica em aberto e o que é mais provável:

1. **"Falta o nó `biz`": descartado pelo código.** O GOWS manda exatamente o `<biz><list v="2" type="product_list"/></biz>` do N04, e o fork tirou o nó duplicado.
2. **"Falta o invólucro viewOnce": descartado como requisito.** O N04 apareceu no iOS sem invólucro. No neonize #191, o `single_select` com `viewOnceMessage` justamente **não** aparecia no iOS.
3. **"Lista de conta pessoal é bloqueada pelo app": não sustentado.** O N04, o itsliaaa #25 e a própria doc do WAHA mostram listas de sessão não oficial aparecendo em 2026. Não há fonte primária dizendo que o app exige conta Business para mostrar `listMessage`.
4. **Hipótese principal: falta o corpo (`description`).** É a diferença que sobra entre a nossa lista e as duas que apareceram no iOS (N04 e itsliaaa), e as duas trazem `description`. Toda lista oficial (Cloud API) também tem corpo obrigatório. Não há prova de que o iOS esconda a lista sem corpo: nenhuma fonte testou esse campo isolado. **Hipótese, a confirmar com o V1.** O rodapé é uma diferença secundária (V2).
5. **Hipótese alternativa: a versão do app quando a mensagem chegou.** A lista chegou durante ou antes da atualização do app. Uma mensagem que a versão antiga não soube mostrar pode ficar oculta depois. O V0 (o mesmo formato, reenviado) separa isso de 4.
6. **Hipótese menor: o nó `biz` sem atributos.** Para `interactiveMessage`, o #1235 mostra que o servidor exige atributos e `quality_control`. Para lista, a nossa foi **entregue** (não houve `ack 479`) e o N04 aparece com o `biz` sem atributos. Fica como último caso, e exigiria mudar o GOWS.

**Business ou comum importa?** Pouco para a causa, mas é uma variável que nenhuma fonte controlou. A 0656 chega com `VerifiedName=null`, então não é conta comercial verificada; pode ser o app Business sem verificação. Vale perguntar, para anotar junto do resultado: (a) qual app a 0656 usa; (b) qual app e qual iOS o 1242 usa; (c) se o 1242 mostra "mensagem não suportada" ou nada. Se a 0656 for Business, nada muda no plano. Se for o app comum e o V1 não aparecer, testar a partir de uma conta Business fica como passo seguinte.

## 4. Onde corrigir na raiz

- **(a) No patch JS do WAHA:** dá para mudar o pedido (`title`, `description`, `footer`, seções), mas não o proto nem os nós do stanza. O GOWS não aceita proto cru. Se a causa for o corpo, a correção nem é no conector: é no `Waha::RichPayload` do chat2you, que sempre manda `description` = corpo e `title` = cabeçalho ou um título curto. O WAHA exige `title` não vazio, então "só descrição" não é possível.
- **(b) No GOWS:** o fonte está disponível (Apache-2.0, `devlikeapro-gows-plus-8179447`, `go 1.26.0`), mas a imagem usa o binário pronto da 2026.9.2. Para atributos no `biz`, `quality_control` ou `messageContextInfo` na lista, seria preciso compilar um GOWS próprio, e o motor passaria a ter um binário Go nosso. Só vale se V0, V1 e V2 falharem.
- **(c) Alternativas:** `interactiveMessage` com `nativeFlowMessage` `single_select` **não** serve: falha no iOS (neonize #191, whatsmeow #1144), e o GOWS também não tem campo para ela. A **enquete** (`pollCreationMessageV3`) é a escolha única que comprovadamente aparece no 1242 (teste real de 17/10, voto aplicado) e é a recomendação do próprio WAHA. É a reserva natural.

## 5. Variantes para testar no aparelho (preparadas, NADA enviado)

Os scripts estão em `docs/audit/2026-10-17-1709-lista-nao-exibe/`:

- `enviar-variante.sh <V0|V1|V2>`: manda uma lista da 0656 para o 1242 pelo `POST /api/sendList` do motor de teste. Sem `CONFIRMO=sim`, só mostra o corpo (a simulação foi conferida nas três). Recusa se uma das sessões não estiver `WORKING` ou se o último envio foi há menos de 120 s. Imprime só a hora, o HTTP e o id.
- `conferir-lista.sh <id>`: copia o banco da sessão B, mostra o `listMessage` como chegou (segredos como `<REDACTED>`) e apaga a cópia. Não chama a API do motor.

| Variante | O que muda | Por quê |
|---|---|---|
| **V0** controle | O formato das 05:43: título = corpo, sem descrição, sem rodapé. | Se aparecer, a causa foi a versão do app quando chegou (hipótese 5), e V1/V2 não são necessários. |
| **V1** formato N04 | `title` "Vistoria", `description` = a pergunta, `footer` "Autonom.ia". | O formato visto e tocado no iOS em 06–07/10/2026. Se aparecer e o V0 não, a causa está no nosso payload (hipótese 4). |
| **V2** sem rodapé | O V1 sem `footer`. | Rode só se o V1 aparecer. Separa o corpo do rodapé, para a correção no `RichPayload` mexer só no necessário. |

Como rodar, **depois que o outro teste terminar**, uma de cada vez, a partir da pasta no M4:

```sh
cd /Users/rodrigosilva/dev/worktrees/chat2you/1709-ricas-waha/docs/audit/2026-10-17-1709-lista-nao-exibe
maccluster exec --node m2 -- /bin/bash -s V0 < enviar-variante.sh               # simulação: mostra o corpo
maccluster exec --node m2 -- /usr/bin/env CONFIRMO=sim /bin/bash -s V0 < enviar-variante.sh  # envia de verdade
# olhar o iPhone do 1242 (conversa com a 0656) e anotar: aparece? toca? mostra "não suportada"?
maccluster exec --node m2 -- /bin/bash -s <id impresso> < conferir-lista.sh     # como chegou na sessão B
# esperar 2 min ou mais; então V1, e V2 só se o V1 aparecer
```

O `maccluster exec` não repassa variáveis do shell do M4 (conferido: `CONFIRMO=sim maccluster exec …` chega vazio). Por isso o `CONFIRMO=sim` vai pelo `/usr/bin/env` do lado do M2, como acima.

Efeito no chat2you local: o envio é direto pelo motor, não pelo painel. O conector deve registrar a lista como mensagem enviada pelo celular na caixa da 0656 e como mensagem recebida na caixa do 1242. Os `rowId` não têm `|`, então um toque não se liga a nenhuma mensagem do Chatwoot.

## 6. Recomendação

1. Rodar o V0 e o V1 (e o V2, se o V1 aparecer) quando as sessões estiverem livres.
2. Se o V1 aparecer e o V0 não: corrigir no chat2you, no `Waha::RichPayload#build_list_message`: `description` sempre = corpo; `title` = cabeçalho, ou um título curto quando não houver (decisão de produto: qual texto usar); rodapé conforme o V2. Teste de unidade do payload e nova rodada no aparelho.
3. Se nenhum aparecer: manter a lista fora da saída nativa e usar a enquete como escolha única (ela já aparece e o voto volta), registrando a lista como "não aparece no iOS com GOWS 2026.9.2". Compilar um GOWS próprio com `biz` completo fica como investigação separada, com Issue própria.
4. Até lá, a lista não deve ir a cliente real como único caminho de resposta.

## Resultado no aparelho (17/10/2026, confirmado pelo Rodrigo no celular do 1242)

As variantes saíram da sessão 5511941010656 para 5511926791242, uma por vez, pelo `enviar-variante.sh`. O motor respondeu HTTP 201 nas três.

| Variante | Hora | id | Payload | No app do 1242 |
|---|---|---|---|---|
| V0 | 07:01:35 | `…3EB0EFA2B4EAD27A160B13` | título = pergunta, **sem description**, sem footer | **não apareceu** |
| V1 | 07:06:55 | `…3EB00A4D386EC3ADAA15F1` | título "Vistoria", **description = pergunta**, footer "Autonom.ia" | **apareceu**; o toque em "Tarde" voltou ao chat2you (msg 1280, `in_reply_to` 1279) |
| V2 | 07:10:13 | `…3EB0DEC74A5E6E4F9E033F` | título "Vistoria", **description = pergunta**, sem footer | **apareceu** ("chegou certinho") |

Conclusão: a `description` é obrigatória para o app exibir a lista; o `footer` é opcional. A hipótese do item 4 está confirmada.

O app tinha sido atualizado antes da V0 (a lista das 05:43 chegou durante a atualização). A V0, enviada depois, também não apareceu, então a atualização não explica a falha.

Correção: commit `8e024c7f01`. Com cabeçalho, sai lista com title = header e description = corpo. Sem cabeçalho, sai como texto. Decisão do Rodrigo, 17/10.
