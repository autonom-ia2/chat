# WAHA 2026.9.2 + patch c2y-rich-3, revisão 3b (autonom-ia2/chat#1709, rodada 2)

Este pacote é só código e build local. Não houve deploy, push nem contato com os motores de produção.

- Base do patch: WAHA tag `2026.9.2` = commit `90ba445a0e765701c8910f0fac08176250c3e0fd`.
- Patch: `waha-2026.9.2-c2y-rich.patch`, sha256 `bd4668c1109f24284537c678704872c93b302f4a7128a9b57b675986ba8eb19f` (63 arquivos). Contém a c2y-rich-3 mais as correções da revisão do conector (**3b**, abaixo). Passa em `git apply --check` sobre a tag limpa (`git archive 90ba445a`).
- A c2y-rich-3 sem as correções (patch `980e37b8…a9d2`, imagem `…:2026.9.2-c2y-rich-3`, tarball `5a566498…88b4`) fica **substituída**: não usar em deploy. Guardada no M2 como `waha-2026.9.2-c2y-rich-3.patch`, `build-waha-c2y-rich-3.sh` e `dist-sha256-3.txt`.
- `/api/server/version` não muda: `autonomia.patch` continua `'c2y-rich-3'`, como a 2b continuou `'c2y-rich-2'`. A label `autonomia.patch-sha256` é o que diferencia as duas.

## Revisão 3b: achados da revisão do conector

1. **Resposta a evento criado no celular da empresa** (médio). Antes, o `isOurEvent` aceitava qualquer evento do nosso número, e o evento criado no app do celular também é espelhado e mapeado. Correção: além do número, o evento precisa ter sido enviado pelo conector. A marca é o `parts` do mapeamento: o `message_created` grava `parts` (≥ 1) em toda mensagem que o conector envia, e o espelhado do celular fica com `parts` nulo (`migrations/002_message_status.ts`, `ChatwootMessage.parts`: "null - mirrored from WhatsApp"). O `sendEvent` não aceita id (GOWS `sendEvent`, `MessageRequest` sem `id`), então não dá para usar um id determinístico como na enquete sem mexer no motor. Função nova: `SentByConnector`. O lado do chat2you (esconder a resposta a evento não nativo) fica com o chat2you.
2. **Falha de download com `media` nulo** (baixo). Agora só conta como falha quando o motor diz que falhou (`media.error`). Evidência no código: em `MediaManager.processMedia`, download desligado ou mimetype filtrado devolvem `{url:null, filename, mimetype}` **sem** erro, e o erro de download vira `media.error`. `media` nulo só aparece quando o processador nem rodou (`downloadMediaSafe` lançou, ou outro motor). Nesse caso fica a nota da main, sem `waha_media_failed` e sem nova tentativa (antes eram 2 chamadas `getMessageById` por mídia).
3. **Aviso de temporária oscilando** (médio, plausível). `ephemeral_expiration` passa a ser `null` quando a mensagem não informa: sem `contextInfo` (texto puro `conversation`), `contextInfo` sem `expiration`, ou `0` com `_data.IsEphemeral === true`. Só sai `0` quando vem `0` explícito. O `events.Message` do whatsmeow tem `IsEphemeral`, mas não tem os segundos, por isso ele só serve para descartar um `0` contraditório. O chat2you já ignora valor que não é Integer (`inbound/context.rb`), então `null` não muda o estado da conversa. Limite: se o motor nunca mandar `expiration: 0` explícito, o aviso "desativadas" não aparece. Fica para o teste em aparelho.
4. **Busca do evento com `from` em @lid** (médio, plausível): **recusado com evidência**. `MessageMappingService.getChatWootMessage` chama `WhatsAppMessageRepository.getByMessageId`, que filtra só por `app_pk` e `message_id`. O `chat_id` passado não entra na busca, então um cliente em @lid acha o evento mapeado com o jid do telefone. Ficaram um comentário no código e um teste com `from` em @lid.
5. **`from_me` ausente em `waha_media_failed` e `waha_order`** (alto). As duas chaves agora levam **sempre** `from_me` boolean (`payload.fromMe === true`). Sem `fromMe` no payload, vai `false`. Contrato com o chat2you: `media_failed` e `order` só transformam com `from_me == false`. Ausente = fica a main. Pulam também `outgoing? && !private`. **Atenção ao chat2you:** a nota privada que o conector cria sai sempre OUTGOING (`base.ts`: "Private notes can only be sent as outgoing messages"), **inclusive a do cliente**. A paridade mostra `failed_no_caption` e `order` como `outgoing/private` com `fromMe:false`. Por isso `message.incoming?` não serve de guarda.

## Validação da 3b (M2, 16/10/2026)

- `tsc --noEmit`: 0 erros. `yarn build`: ok. `oxlint --deny-warnings` nos 6 arquivos tocados: 0 avisos, 0 erros.
- Suíte unit completa: 47 suítes e 639 testes. Falham 10 testes em 4 suítes (PixMessage, message.ack.utils, PhoneNumbersCacheRepository e session.abc), os mesmos 10 da tag limpa. As 4 suítes do pacote rodaram depois do teste de presença de `from_me`: 164 de 164.
- Testes novos: download desligado, mimetype filtrado, `media` nulo e ausente não são falha e não pedem nova tentativa; `from_me` em `waha_media_failed` e `waha_order` com cliente, celular da empresa e `fromMe` ausente, sempre boolean, nos três caminhos (com legenda, sem legenda e pedido); `ephemeral_expiration` nulo sem `contextInfo` ou sem `expiration`, `0` explícito, `0` com `IsEphemeral`, e um chat de 24 h alternando texto com e sem `contextInfo` sem nunca dar `0`; evento espelhado do celular (`parts` nulo ou ausente) ignorado sem criar nem mapear nada; resposta com `from` em @lid achada pelo id.
- Mutação: 8 guardas quebradas, uma de cada vez, e todas derrubaram testes.
  - A checagem de origem do evento (2 falhas), `media` nulo tratado como falha (4), sem `expiration` virando `0` (5), `IsEphemeral` ignorado (1), `from_me` fixo em `false` na mídia (3) e no pedido (2).
  - Tirar o `from_me` das duas chaves derruba a suíte já na compilação de tipos (TS2741).
  - Os arquivos foram restaurados e conferidos por sha256.
- Com o Baileys real, sobre o `dist`: `validate/r5-real-baileys.js` passa 37 de 37 (com os nomes do Go para `ContextInfo`, `Expiration` e `OrderMessage`) e `listreply-real-baileys.js` passa 8 de 8.
- Paridade com a main: `r4-parity-run.js` sobre `dist-base` e sobre o `dist`, mais `r4-parity-compare.js`, dá 23 de 23. A fixture `failed_no_caption` (`media` nulo) agora sai sem `waha_media_failed`, que é o esperado pelo achado 2.
- Dist: mudam 3 dos 47 arquivos (`c2y3.js`, `event.response.js`, `UnsupportedMessage.js`). O dist inteiro comparado com `dist-base` dá exatamente os mesmos 47 (34 alterados e 13 novos), sem nenhum arquivo removido.

## Imagem construída (M2, 16/10/2026, c2y-rich-3b)

- Chamada: igual à da c2y-rich-3 (abaixo), com a tag `autonomia-waha-c2y-rich:2026.9.2-c2y-rich-3b`.
- Imagem linux/amd64 com 120 camadas, como a 3 (nenhum arquivo novo).
  - ID local (índice OCI): `sha256:900c80be6454f5e5f5b850b5bc43086a690e72487e681118ed93c41067b75a4e`;
  - manifest amd64: `sha256:79d2561675d64c22b8ca5b2280b2af44711648162482add0e041ea526f48d165`;
  - config: `sha256:6f7a748272786500d69d9105cd84e1cc6f920e67ef069930fb6fbb90c57567a0`;
  - LABELs `autonomia.patch=c2y-rich-3` e `autonomia.patch-sha256=bd4668c1…eb19f`.
- O script conferiu os 47 arquivos dentro da imagem.
- Tarball: `out/autonomia-waha-c2y-rich_2026.9.2-c2y-rich-3b.tar`, 2269913600 bytes, sha256 `d4172389f5e04df4ec65b40f7a114dce04eed7d110161d9ebfdfbc69358eed9a`.
- Rollback: para a 2b ou para a base de produção, como na seção ROLLBACK. A imagem e o tarball da c2y-rich-3 continuam no M2, mas não devem ser usados.
- Não validado: o smoke amd64 (o daemon do M2 é aarch64) e nada em aparelho. Em especial, ainda falta ver em aparelho se o GOWS manda `expiration: 0` explícito ao desligar a temporária, e a resposta a um evento criado no celular (deve ser ignorada).

---

## Histórico: c2y-rich-3 (antes da revisão 3b)

Este pacote é só código e build local. Não houve deploy, push nem contato com os motores de produção.

- Base do patch: WAHA tag `2026.9.2` = commit `90ba445a0e765701c8910f0fac08176250c3e0fd`.
- Patch: `waha-2026.9.2-c2y-rich.patch`, sha256 `980e37b8e08bf5865f7f3365cf6d91be4a2fc79b8a375697fc7a21c6d246a9d2` (63 arquivos). Contém o c2y-rich-2b inteiro mais a rodada 2.
  - Passa em `git apply --check` sobre a tag limpa (`git archive 90ba445a`).
  - Aplicado sobre a tag limpa e compilado (`yarn build`), reproduz os 47 hashes do `dist-sha256.txt` (47 de 47).
- Patch anterior (c2y-rich-2b, sha256 `ec2861d6…b52c`): guardado no M2 como `waha-2026.9.2-c2y-rich-2b.patch`, com o script `build-waha-c2y-rich-2b.sh` e a tabela `dist-sha256-2b.txt`, para rollback de código.
- `/api/server/version` passa a dizer `autonomia = {patch:'c2y-rich-3', rich_native:['options','location','contact','poll','link_button','event'], list_reply:true, poll_vote:true, reactions:true, edit:true, media_as_media:true, format:'c2y-1', event_response:true}`.

## Rodada 2 (c2y-rich-3): o que o conector faz

A regra continua a mesma: na entrada, o conector cria **a mesma mensagem da main** (mesmo `content`, `message_type`, `private`, anexos e `in_reply_to`) e só acrescenta chaves `waha_*` em `content_attributes`. Quem muda a apresentação é o chat2you, com a flag `whatsapp_rich_native`. A prova está em `validate/r4-parity-*.js`: 23 cenários passam pelo `dist` limpo da tag e pelo `dist` com o patch, e o resultado é idêntico depois de tirar as chaves `waha_*`.

Chaves novas (conector → chat2you):

| Chave | Quando | Formato |
|---|---|---|
| `waha_media` | mensagem com anexo baixado (`TextMessage`) | `{kind: voice\|audio\|image\|video\|document\|sticker, mimetype, filename\|null, ptt, view_once, animated, lottie}` |
| `waha_album` | cabeçalho de álbum (`AlbumMessage`) | `{expected_images, expected_videos}` |
| `waha_location` | localização e localização ao vivo | `{latitude:Number, longitude:Number, name, address, url, live, caption}`; não sai se as coordenadas não forem números |
| `waha_contacts` | contato(s) compartilhado(s) | `[{full_name, phones:[...], wa_id}]`, na ordem dos `.vcf`; não sai se algum vCard falhar |
| `waha_quote` | mensagem que cita outra (`payload.replyTo`) | `{wa_id, participant, from_me, body (≤280 caracteres), has_media, chatwoot_message_id}` |
| `waha_media_failed` | o download da mídia falhou | `{kind, mimetype, filename, caption, reason}`; `reason` = só a classe do erro |
| `waha_revoke` | nota "apagada no WhatsApp" | `{revoked_wa_id, from_me}` |
| `waha_context` | toda mensagem ao vivo do `message.any` | `{ephemeral_expiration (s, 0 = desligada), forwarded, forwarding_score}` |
| `waha_order` | pedido (`orderMessage`) na nota de não suportada | `{order_id, title, text, item_count, total_amount, currency, status, seller_jid}` |
| `waha_unknown.gif` | não suportada que é GIF | `true` (só aparece quando é) |
| `waha_event_response` | resposta a evento nosso (mensagem nova, INCOMING) | `{event_message_id, response: going\|not_going\|maybe, extra_guests, response_id, timestamp}` + `in_reply_to` |

E mais:
- **Áudio ouvido:** quando chega o ack `PLAYED` de mensagem nossa, o PATCH de status manda também `c2y_played_at` (ISO 8601). Sem o ack `PLAYED`, o corpo do PATCH é o da main (`{status}`).
- **Saída, botão de link:** `waha_native.kind = 'sendLinkCustomPreview'`, payload `{text, preview:{url, title, description, image?:{url, mimetype}}}`. Com imagem: `POST /api/send/link-custom-preview` (`linkPreviewHighQuality: true`, sem id: o endpoint não aceita). Sem imagem: `sendText` com `linkPreview: true` e o id determinístico (o GOWS dá 500 sem imagem). Texto sem a url, url que não é http(s), título ou descrição que não são texto: não envia e manda o texto uma vez (o controller do WAHA responde 500, não 4xx, nesses casos).
- **Saída, evento:** `waha_native.kind = 'sendEvent'`, payload `{event:{name, description?, startTime (s), endTime?, location?:{name}}}`. `POST /api/{sessão}/events`, sem id, `extraGuestsAllowed` sempre `false`. Nome vazio, hora que não é inteiro em segundos ou fim antes do início: não envia e manda o texto uma vez. Cancelar evento não existe no motor e não foi oferecido.
- **Entrada, resposta ao evento:** o conector ouve `event.response` (fila nova `chatwoot.waha | event.response`). `event.response.failed` não é ouvido.
- 4xx/501 nos dois envios novos: texto uma vez. 5xx ou timeout: `UnrecoverableError` sem texto, como as outras nativas.

## Desvios do contrato (e por quê)

1. **Nova tentativa de download desligada por padrão.** O contrato pede 2 tentativas (3 s e 10 s). Ela muda o resultado da main para quem não tem a flag (mídia em vez do aviso), e a decisão (b) é do Rodrigo. Ficou atrás de `WAHA_C2Y_MEDIA_RETRY=true` no motor. Além disso, as esperas viraram **2 s e 4 s**, com teto de 4 s por chamada (pior caso 14 s), porque o job segura o mutex do chat por no máximo 20 s (`JOB_LOCK_TTL`); com 3 s + 10 s + downloads o lock venceria e outra mensagem do mesmo chat entraria fora de ordem. A tentativa só acontece quando o motor **tentou e falhou** (`media.error`, ou `media` nulo); mídia não baixada de propósito (download desligado, mimetype filtrado) não é pedida de novo. Não roda na importação de histórico.
2. **`waha_context` sai em toda mensagem ao vivo**, mesmo com os valores padrão. O contrato dizia "quando algum valor não é padrão", mas o chat2you precisa do `0` para perceber que as mensagens temporárias foram desligadas. Não sai na importação de histórico (senão cada mensagem antiga mudaria o estado da conversa).
3. **`waha_quote.from_me`** só é calculado quando a citada **não** está mapeada (o único caso em que o chat2you usa o campo): compara o `participant` com o número e o lid da sessão (`GET /api/sessions/{sessão}`). Se não der para ler, fica `null` e o log leva só a classe do erro.
4. **Resposta de evento: perspectiva da chave.** O GOWS entrega a chave do evento como o **cliente** a escreveu (diferente do voto de enquete, que passa por `fixPollCreationKey`): o nosso evento chega como `{remoteJid: nosso número, fromMe: false}` e o evento do próprio cliente como `{remoteJid: nosso número, fromMe: true}`. Por isso o "só quando `eventCreationKey.fromMe`" do contrato daria o resultado ao contrário. O handler trata as duas perspectivas: chave apontando para o nosso número → nosso se `fromMe: false`; apontando para o cliente → nosso se `fromMe: true`; grupo → nosso se o `participant` da chave é o nosso número. Além disso, o evento precisa estar no mapeamento.
5. **Resposta de status (status reply) fica igual à main:** sem chaves `waha_*` e sem `waha_quote` (a citada é o status, e o conteúdo já é montado em volta dele).
6. **Item 11 (visualização única), parte do motor: NÃO implementada.** A ordem do contrato pede a verificação no canário antes de escrever o patch no `session.gows.core.ts`, e a decisão (f) é do Rodrigo. O que já existe: se a mídia de visualização única chegar, `waha_media.view_once = true` (pelos flags `IsViewOnce*` do whatsmeow, pelos invólucros `viewOnceMessage*` ou pelo campo `viewOnce` da mídia). O evento interno `c2y.message.unavailable` não existe nesta imagem.
7. **Normalização** (`normalizeMessageContent` do Baileys) também na detecção de localização e contato, como o item 8 pede. O whatsmeow já desembrulha `ephemeralMessage`/`viewOnce*`, então no GOWS isso não muda nada na prática; a prova de paridade confirma a mesma saída.

## Arquivos que mudam na rodada 2

Fonte (16 a mais, 63 no total): `c2y3.ts` e `c2y3.retry.ts` (novos, helpers puros), `consumers/waha/event.response.ts` (novo), `TextMessage.ts`, `LocationMessage.ts`, `ShareContactMessage.ts`, `AlbumMessage.ts`, `HasMediaWithNoMediaMessage.ts`, `UnsupportedMessage.ts`, `message.any.ts`, `base.ts`, `message.revoked.ts`, `message.ack.ts`, `MessageStatusService.ts`, `client/Conversation.ts`, `native.ts`, `message_created.ts`, `WAHASelf.ts`, a fila (`QueueName`, `QueueRegistry`, `QueueManager`, `ChatWootWAHAQueueService`, `app.module`), os 2 YAML, `version.ts`, `environment.dto.ts`, e 4 arquivos de teste novos.

Dist (47; eram 35): lista em `dist-sha256.txt`. Mudam 34 e surgem 13 (os 10 novos da 2b mais `c2y3.js`, `c2y3.retry.js` e `event.response.js`). Comparando o `dist` com o build da tag limpa (`dist-base`, sem `.map`, `.d.ts` e testes), mudam exatamente esses 47 e nenhum some.

## Validação da rodada 2 (M2, 16/10/2026)

- `tsc --noEmit`: 0 erros. `yarn build`: ok. `oxlint --deny-warnings` nos 29 `.ts` tocados: 0 avisos, 0 erros.
- `prettier`: **não aplicado**. O do repositório é o 1.19.1, que não lê `import type` nem `satisfies` e reformatava linhas do upstream e da 2b; a formatação foi feita à mão no padrão do arquivo.
- Suíte unit completa (`jest --selectProjects unit`): 47 suítes, 620 testes; 10 falham em 4 suítes (PixMessage, message.ack.utils, PhoneNumbersCacheRepository, session.abc). São exatamente os mesmos 10 da tag limpa (`diff` dos nomes vazio).
- 142 testes novos em 4 suítes (`c2y3.test.ts`, `inbound.c2y3.test.ts`, `event.response.test.ts`, `message_created.c2y3.test.ts`), todos passando.
- Mutação: 11 guardas quebradas uma de cada vez (falha de download sem erro, flag da nova tentativa, perspectiva da chave do evento, texto sem url, imagem do link, status reply, saneamento do `reason`, `from_me` só sem mapeamento, contexto no histórico, `played_at` só no `PLAYED`, resposta do próprio número): todas derrubam pelo menos 1 teste. Os arquivos foram restaurados e conferidos por sha256.
- Com o Baileys real, sobre o `dist`: `validate/r4-real-baileys.js` 29 de 29 (chaves do GOWS em camelCase e em PascalCase, invólucros `ephemeral`/`viewOnce*`/`documentWithCaption`, figurinha Lottie, pedido com os nomes do Go, i18n, handshake). `listreply-real-baileys.js` continua 8 de 8.
- Paridade com a main: `validate/r4-parity-run.js` + `r4-parity-compare.js`, 23 de 23.
- Logs novos: só ids (mensagem do Chatwoot, id curto do WhatsApp, sessão) e classe do erro. Testes garantem que telefone, chave e texto não aparecem.

## Imagem construída (M2, 16/10/2026, c2y-rich-3)

- Base: a mesma de produção, `devlikeapro/waha-plus@sha256:ac5d6c13…9598` (ID local `sha256:7179f432…aff4`). O passo 1 passou: os 34 arquivos originais batem com "antes" e os 13 novos não existem nela.
- Chamada:

  ```sh
  WAHA_C2Y_BASE=sha256:7179f432b837e5f902f49005ec5ca762bf5fbc09cf2b8538af95a077e6d5aff4 \
  WAHA_C2Y_BASE_SOURCE=devlikeapro/waha-plus@sha256:ac5d6c131155df16e4a29c29efdbdf977788a0a4908dbe9d8edf4366202e9598 \
  WAHA_C2Y_DIST_DIR=…/waha/dist WAHA_C2Y_OUT_DIR=…/out WAHA_C2Y_SKIP_SMOKE=1 \
  ./build-waha-c2y-rich.sh autonomia-waha-c2y-rich:2026.9.2-c2y-rich-3
  ```

- Imagem: `autonomia-waha-c2y-rich:2026.9.2-c2y-rich-3`, linux/amd64, **120 camadas** (28 da base e 92 de COPY). O limite do overlay2 é 128: sobram 8. Um pacote futuro com mais de 4 JS novos precisa juntar os COPY (por exemplo, um COPY por diretório).
  - ID local (índice OCI): `sha256:9ee4d8886d7cf22c9e6267990a3980001c3c8244def4cbedf1ebda16f488cf70`;
  - manifest amd64: `sha256:366af7ebcfe72d6d2e62b1ed80adbefbae0591f9cdf131d8b8b4d8c02b6d8c7f`;
  - config digest: `sha256:1ca4a90407f37aa7d36502939e8201bc5a741c9a849c51ce1b7c78b64344e545`;
  - LABELs: `autonomia.patch=c2y-rich-3`, `autonomia.patch-sha256=980e37b8…a9d2`, `base-digest`, `base-ref`, `base-image-id`, `waha-sha`, `waha-tag`, `issue=chat#1709`.
- Os 47 arquivos foram conferidos dentro da imagem pelo script e de novo à parte (`docker create` + `docker cp`): 47 hashes certos e os 45 `.map`.
- Tarball: `out/autonomia-waha-c2y-rich_2026.9.2-c2y-rich-3.tar`, 2269912064 bytes, sha256 `5a566498e509efab431ec4e83468fb6aa473bdc14acdb67263bd1f38f66588b4`.
- A imagem e o tarball da 2b continuam no M2 (rollback).

## Para ligar no canário (só com OK do Rodrigo)

- Ordem: primeiro o PR do chat2you que tira e transforma as chaves novas; depois a troca da imagem. Um chat2you sem o PR guarda as chaves `waha_*` em `content_attributes` sem efeito na tela.
- `WAHA_C2Y_MEDIA_RETRY=true` só depois da decisão (b). Sem a variável, o motor se comporta como a 2b nesse ponto.
- A sessão precisa receber o evento `event.response`: a lista de eventos do app muda com a imagem nova (`ListenEventsForChatWoot`).
- Rollback (para a 2b ou para a base de produção), tempo estimado e conferência de saúde: seção **ROLLBACK da imagem**, mais abaixo; vale para a c2y-rich-3. Na conferência, o `/api/server/version` da 2b mostra `"patch":"c2y-rich-2"` e o da base não tem o campo `autonomia`.

## O que NÃO foi validado na rodada 2

- Nada com WhatsApp, Chatwoot, Redis ou BullMQ de verdade: handlers testados com dublês. Em aparelho falta ver: PTT, álbum, localização (fixa e ao vivo), contato, citação de mensagem antiga, mídia que falha, apagada, temporária (24 h / 7 dias / desligada), figurinha (estática, animada, Lottie), visualização única, encaminhada (score), áudio ouvido (`PLAYED`), pedido, botão de link (com e sem imagem) e evento com as três respostas.
- O formato real da chave do `event.response` no GOWS (a perspectiva do item 4 dos desvios) foi lido do código, não visto em evento real; os dois lados estão cobertos.
- `link-custom-preview` e `events` no GOWS 2026.9.2: lidos do código-fonte (`chatting.controller.ts`, `events.controller.ts`, `session.gows.core.ts`), não chamados.
- Smoke de execução amd64 (`/api/server/version`, vazamento no log): o daemon do M2 é aarch64. Fica para o canário.
- Item 11, parte do motor (`c2y.message.unavailable`): não implementado (desvio 6).

## Histórico: c2y-rich-2 (revisão 2b)

- Patch: `waha-2026.9.2-c2y-rich-2b.patch`, sha256 `ec2861d600ba74377bd458f059b47a9951e4a492682f465688a1dbe12eefb52c` (47 arquivos). Contém o c2y-rich-1 inteiro mais o c2y-rich-2, já com as correções da revisão (revisão **2b**, abaixo).
- A revisão anterior do c2y-rich-2 (patch `7164eecd…7626`, imagem `…:2026.9.2-c2y-rich-2`, tarball `8bbe0262…1875`) fica **substituída**: não usar em deploy.
- Patch anterior (c2y-rich-1, sha256 `cf250286…b52e`): guardado no M2 como `waha-2026.9.2-c2y-rich-1.patch`, para rollback de código.
- `/api/server/version` ganha `autonomia = {patch:'c2y-rich-2', rich_native:['options','location','contact','poll'], list_reply:true, poll_vote:true, reactions:true, edit:true, media_as_media:true, format:'c2y-1'}`.

## Revisão 2b: achados da revisão do conector (todos corrigidos)

1. **Voto retirado pode cair em `poll.vote.failed`** (baixo, plausível). O GOWS separa os votos por `!!payload.vote.selectedOptions` (`session.gows.core.ts:~821`); se o Go serializar a lista vazia como `null`, o voto retirado vira `poll.vote.failed`. Correção: o conector também ouve `poll.vote.failed` e manda para a mesma fila e o mesmo handler. O handler não muda: só age em enquete nossa (id determinístico), e sem opções o conteúdo é "Voto retirado". O motor não foi alterado, então os webhooks de outros sistemas continuam recebendo os mesmos eventos. Risco residual: um voto que o motor de fato não conseguiu decifrar, numa enquete nossa, também aparece como "Voto retirado". É improvável, porque a enquete foi criada pela própria sessão (a chave está no store dela). Teste em aparelho 4 confirma o formato real.
2. **Nota de erro de reação/edição em mensagem recebida** (baixo, plausível). O reporter copiava `body.message_type`; com o alvo `incoming`, a nota privada sairia como `incoming`. Correção: `ChatWootInboxC2yReactionConsumer` e `ChatWootInboxC2yEditConsumer` sobrescrevem `ReportErrorForMessage` e `ReportErrorRecovered` e passam uma cópia do corpo com `message_type: 'outgoing'` (`ReportBody`). O corpo do job não muda e os outros consumidores ficam iguais.
3. **Eventos `c2y_*` sem assinatura** (baixo). Correção: os dois eventos só são aceitos com a assinatura que o chat2you já põe no webhook da caixa (`Webhooks::Trigger`, `X-Chatwoot-Timestamp` e `X-Chatwoot-Signature: sha256=HMAC-SHA256(secret da caixa, "<ts>.<corpo cru>")`).
   - O corpo cru vem do `verify` do `json()` em `main.ts` (`apps/chatwoot/api/rawbody.ts`), guardado só para `/webhooks/chatwoot/...`. Nenhuma outra rota muda.
   - O secret é lido da API do Chatwoot (`GET /api/v1/accounts/:conta/inboxes/:caixa`, campo `secret`) com o token do app, em cache por 5 min por app; uma assinatura que falha relê o secret no máximo uma vez a cada 30 s (troca de secret sem martelar o Chatwoot). Janela de relógio: 300 s para os dois lados. Comparação em tempo constante.
   - Sem assinatura válida: 401 e nada na fila. Sem secret legível (token sem papel de administrador, ou Chatwoot fora): 401 também, fechado. O log leva só o id do app; nunca o secret, a assinatura ou o corpo.
   - `message_created`, `message_updated` e os outros eventos seguem sem checagem, como antes.
   - **Pré-requisito no canário:** o token do app de cada caixa WAHA precisa ser de administrador (é o que já é exigido para criar e configurar a caixa). Conferir lendo a caixa com esse token e vendo se o campo `secret` vem preenchido (sem imprimir o valor). Caixa sem `secret` no chat2you não assina o webhook, e reagir/editar por ela vai dar 401.
   - **Ação no chat2you:** a coluna `channel_api.secret` entrou em `20260324070828_add_secret_to_channel_api.rb` **sem preencher as caixas antigas** (o `has_secure_token` só gera na criação). Caixa WAHA criada antes disso tem `secret` nulo. O `Waha::RichNative::MessageActions` precisa garantir o secret antes de mandar o evento (gerar quando vazio) ou esconder Reagir/Editar nessa caixa; senão o atendente reage e nada sai.
4. **Download sem teto na conversão de imagem** (baixo). Correção: `FetchLimited` (axios com `maxContentLength`/`maxBodyLength` de 16 MB, o limite de mídia do WhatsApp; o download é cortado durante o streaming) e `sharp(input, { limitInputPixels: 50_000_000 })` (cobre fotos de 48 MP). Acima de qualquer um dos dois, cai no `sendFile`, como hoje. Mantidos o mesmo agente TLS e o User-Agent do `fetchBuffer`.

## Regra que o conector segue

O conector roda para todas as contas. Por isso, na entrada (WhatsApp para Chatwoot), ele **não muda o que já manda**: mesmo `content`, mesmo `message_type`, mesmo `private`, mesmas mensagens. Ele só acrescenta chaves próprias em `content_attributes`. Quem decide a apresentação nova é o chat2you, e só com a flag `whatsapp_rich_native` ligada. Sem a flag, o chat2you tira as chaves e a mensagem fica igual à main.

Na saída, todo comportamento novo depende de uma chave que o chat2you só manda com a flag (`waha_native.kind = sendPoll`, `waha_text`, `waha_media_as_media`) ou de um evento novo (`c2y_message_reaction`, `c2y_message_edit`). Sem elas, o caminho é o de hoje, linha por linha.

## O que muda, item por item

**1. Enquete.**
- Saída: `waha_native.kind = 'sendPoll'`, payload `{poll:{name, options, multipleAnswers}}`. Do payload só se copiam esses três campos; `chatId` e `session` vêm do conector. Vai por `POST /api/sendPoll` com id determinístico (`DeterministicMessageId(sessão, id do Chatwoot, 'sendPoll')`) e `reply_to`. Recusa 4xx/501 manda o texto uma vez; 5xx ou timeout vira `UnrecoverableError`, como as outras nativas.
- Entrada: o conector passa a ouvir `poll.vote` e `poll.vote.failed` (fila nova `chatwoot.waha | poll.vote`, a mesma para os dois). Ele só cria mensagem quando a enquete está no mapeamento **e** o id dela é o determinístico desta sessão. Fora disso (enquete feita no celular, de outra sessão, mensagem comum), o voto é ignorado, como na main.
- A mensagem criada é INCOMING, não privada, na conversa da enquete: `content` = títulos separados por vírgula (ou "Vote removed" / "Voto retirado"), `content_attributes = {in_reply_to: <enquete>, waha_poll_vote: {poll_message_id, options:[títulos], vote_id, timestamp}}`. O voto é mapeado; um retry não cria a mensagem duas vezes.
- Decisão própria: voto com `fromMe` (o celular da empresa votando na própria enquete) é ignorado, porque não é resposta do cliente.
- O texto do voto retirado está em `en-US.yaml` e `pt-BR.yaml` (`whatsapp.to.chatwoot.poll.vote.removed`). Os outros 16 idiomas não têm a chave e o loader não tem fallback, então o código cai para o inglês. Por isso o overlay copia também esses dois YAML.

**2. Foto e vídeo sempre como mídia** (só com `content_attributes.waha_media_as_media === true`).
- Imagem fora de jpeg/png: GIF vai por `sendVideo` com `convert:true` (o ffmpeg do motor gera o mp4). As outras (webp, bmp, tiff, avif, heic) são baixadas pela url (`FetchLimited`: mesmo TLS e User-Agent do `fetchBuffer` do motor, com teto de 16 MB), convertidas com `sharp(..., {limitInputPixels: 50 MP}).rotate().jpeg({quality:85})` e enviadas por `sendImage` em base64, com nome `.jpg`, legenda, `reply_to` e menções. Se baixar ou converter falhar, cai no `sendFile` de hoje e o log leva só a classe do erro.
- Vídeo fora de mp4: `sendVideo` com `convert:true`.
- jpg, png e mp4 seguem idênticos. Sem a chave, webp e mov continuam indo como arquivo.
- A imagem de produção tem `sharp 0.35.3` com `@img/sharp-linux-x64` e `sharp-libvips-linux-x64`, e tem `/usr/bin/ffmpeg` (conferido com `docker cp` na base).

**3. Híbrido (citar e apagar).** Não se aplica ao conector.

**4. Ligação.** `call.received`, `call.accepted` e `call.rejected` mantêm `content` e `private` e acrescentam `content_attributes.waha_call = {call_id, event:'received'|'accepted'|'rejected', is_video, by_me, reason}`. `by_me` é o mesmo cálculo que já decidia a nota privada do rejected (Tag `reject`, Reason `rejected_elsewhere`, ou `api`); nos outros dois é `false`. `reason` é `_data.Reason` quando é texto, senão `null`.

**5. Tipo desconhecido.** A nota privada fica igual e ganha `content_attributes.waha_unknown = {content_type, from_me}`. `content_type` vem de `getContentType(normalizeMessageContent(proto))` do Baileys, dentro de try/catch: se falhar, sai `null` e um `warn` só com a classe do erro.

**6. Reações.**
- Entrada: a mensagem "Reagiu com" fica igual e ganha `content_attributes.waha_reaction = {emoji ('' = removida), reacted_wa_id, from_me}`. O `in_reply_to` continua apontando a mensagem reagida.
- Saída: evento `c2y_message_reaction` (`...webhook_data, c2y_reaction:{emoji}`), tratado pelo controller **antes** dos filtros de incoming e de eco, porque o alvo pode ser mensagem do cliente. Ignora nota privada e o chat de comandos, confere app e sessão (404 senão) e exige a assinatura HMAC da caixa (401 senão; ver revisão 2b). Fila `chatwoot.inbox | c2y_message_reaction`. O handler pega a primeira parte mapeada e chama `PUT /api/reaction` com `SerializeWhatsAppKey`. Sem mapeamento: `UnrecoverableError`, e o reporter posta a nota de erro na hora, sempre como nota privada de saída (também na edição). Emoji precisa ser texto de até 32 caracteres; payload inválido é ignorado com `warn`.

**7. Edição.**
- Entrada: a mensagem "Editado no WhatsApp" fica igual e ganha `content_attributes.waha_edit = {text, edited_wa_id, from_me}`. `text` já está em markdown do Chatwoot (`WhatsappToMarkdown`).
- Saída: evento `c2y_message_edit` (`c2y_edit:{waha_text}`), com o mesmo tratamento do controller. Fila `chatwoot.inbox | c2y_message_edit`. Exige exatamente 1 parte mapeada; senão `UnrecoverableError`. Chama `PUT /api/{sessão}/chats/{chat}/messages/{id}` com o `chat_id` gravado no mapeamento, `text = waha_text` e o link preview da config da caixa. Texto vazio ou maior que 65536: ignorado com `warn`.

**8. Formatação.** Quando `content_attributes.waha_text` é texto, ele vai como está, sem `MarkdownToWhatsApp`; menções de grupo são lidas sobre ele, e a legenda do anexo único usa o mesmo texto. Sem a chave, o `MarkdownToWhatsApp` de hoje. Nenhuma regex nova no conector.

## Arquivos que mudam

Fonte (47): `WAHASelf.ts` (sendPoll, setReaction, editMessage), controller do webhook, `main.ts` (só o `verify` do `json()`), `app.module.ts`, `QueueName.ts`, `QueueRegistry.ts`, `QueueManager.ts`, `ChatWootQueueService.ts`, `ChatWootWAHAQueueService.ts`, `message_created.ts`, `waha/base.ts`, os 3 de chamada + `call.0.base.ts`, `message.any.ts`, `message.reaction.ts`, `MessageEdited.ts`, `UnsupportedMessage.ts`, `version.ts`, `environment.dto.ts`, os 2 YAML, e os novos `c2y_actions.ts`, `poll.vote.ts`, `UnknownContentType.ts`, `actions.ts`, `hints.ts`, `media.ts`, `c2y.signature.ts`, `rawbody.ts`. Mais os do c2y-rich-1 e 12 arquivos de teste.

Dist (35): lista completa em `dist-sha256.txt`, no formato `antes depois caminho`; arquivo novo traz `NEW` em "antes". São 33 JS (cada um com `.map`) e 2 YAML (sem `.map`). Os `*.test.js` não entram. O script copia `.map` só para `.js`. A lista foi conferida contra o dist inteiro: comparando `dist` com o build da tag limpa (`dist-base`, sem `.map`, `.d.ts` e testes), mudam exatamente 25 arquivos e surgem exatamente 10; nenhum some.

## Script `build-waha-c2y-rich.sh`

Mesmo processo do c2y-rich-1: base fixada por digest ou image ID (sem pull), conferência dos 25 arquivos originais na base e dos 10 novos ausentes, dist conferido contra os hashes revisados, overlay só com `FROM`, `COPY` e `LABEL`, conferência dentro da imagem com `docker create` + `docker cp`, `docker save` e `.sha256`. Na revisão 2b mudou só a tabela de hashes (mais `main.js`, `c2y.signature.js` e `rawbody.js`) e o comentário do cabeçalho. `main.js` da base (`c558d676…dc01`) foi conferido igual ao do build da tag limpa antes de entrar na tabela.

## Validação feita (no M2, 16/10/2026, revisão 2b)

- `tsc --noEmit`: 0 erros. `yarn build`: ok. `oxlint --deny-warnings` nos 45 `.ts` tocados: 0 avisos, 0 erros. `prettier` nos arquivos tocados, diff relido.
- Suíte unit completa (`jest --selectProjects unit`): 43 suítes, 478 testes; 10 falham em 4 suítes (PixMessage, message.ack.utils, PhoneNumbersCacheRepository, session.abc). São exatamente os mesmos 10 da tag limpa e da revisão anterior (`diff` dos nomes vazio).
- Testes das 13 suítes do pacote: 204, todos passando. Novos na 2b:
  - `c2y.signature` (26): vetor gerado com `OpenSSL::HMAC` do Ruby sobre JSON com escapes do Rails e UTF-8; janela de 300 s para os dois lados; recusa por secret errado, nulo ou vazio, corpo alterado, sem corpo cru, timestamp antigo, futuro, não inteiro ou com espaço, sem prefixo, truncada, hex maiúsculo, header repetido; cache por app, releitura depois de 5 min, troca de secret relida uma vez após 30 s, sem martelar o Chatwoot em assinatura inválida, token sem admin e Chatwoot fora = fechado; `rawBody` só nas rotas `/webhooks/chatwoot/`.
  - `chatwoot.webhook.c2y2.e2e` (5): app Nest de verdade por HTTP, com o mesmo `json({limit, verify})` do `main.ts` antes do parser padrão do Nest: assinado = 201 e na fila; sem assinatura, outro secret ou corpo trocado depois de assinar = 401 e nada na fila; `message_created` sem assinatura continua aceito.
  - controller (+5): verificador recebe config do app, corpo cru e headers; `invalid` e `no-secret` = 401; app desconhecido = 404 antes da assinatura; outros eventos não passam pela assinatura.
  - `c2y_actions` (+5): reação e edição sobre mensagem `incoming` geram nota privada `outgoing` (erro e recuperação), sem mudar o corpo do job.
  - `poll.vote` (+5): formato do `poll.vote.failed` (`selectedOptions` `null`/ausente) em enquete nossa = "Voto retirado" mapeado; em enquete do celular = ignorado; o conector ouve os dois eventos e os dois vão para a fila `chatwoot.waha | poll.vote`.
  - `media` (6): download dentro do teto passa; acima é cortado durante o streaming (servidor local sem `Content-Length`); teto de pixels explícito e abaixo do padrão do sharp; imagem acima do teto recusada (sharp real).
- Mutação (2b): tirar `POLL_VOTE_FAILED` da escuta, o `ReportBody`, o `if (verdict !== 'ok')`, a janela de tempo ou os tetos do download/sharp faz os testes correspondentes falharem (1, 5, 5, 2 e 2 falhas). Os arquivos foram restaurados e conferidos por sha256 contra a cópia revisada.
- Sobre o dist: `validate/r2-real-baileys.js` com o Baileys real continua 14 de 14 e `listreply-real-baileys.js` 8 de 8; o `c2y.signature.js` compilado aceita o vetor do Ruby; `media.js` compilado expõe 16777216 bytes e 50000000 pixels.

## Imagem construída (M2, 16/10/2026, revisão 2b)

- Base: a mesma de produção, `devlikeapro/waha-plus@sha256:ac5d6c13…9598` (ID local `sha256:7179f432…aff4`). O passo 1 passou: os 25 arquivos originais batem com "antes" e os 10 novos não existem nela.
- Chamada:

  ```sh
  WAHA_C2Y_BASE=sha256:7179f432b837e5f902f49005ec5ca762bf5fbc09cf2b8538af95a077e6d5aff4 \
  WAHA_C2Y_BASE_SOURCE=devlikeapro/waha-plus@sha256:ac5d6c131155df16e4a29c29efdbdf977788a0a4908dbe9d8edf4366202e9598 \
  WAHA_C2Y_DIST_DIR=…/waha/dist WAHA_C2Y_OUT_DIR=…/out WAHA_C2Y_SKIP_SMOKE=1 \
  ./build-waha-c2y-rich.sh autonomia-waha-c2y-rich:2026.9.2-c2y-rich-2b
  ```

- Imagem: `autonomia-waha-c2y-rich:2026.9.2-c2y-rich-2b`, linux/amd64, **96 camadas** (28 da base e 68 de COPY). O limite do overlay2 é 128.
  - ID local (índice OCI): `sha256:d16836bece76cf04f2a981b65a6e0a6439bb7b7e0a800c3ee3a46a07982f458e`;
  - manifest amd64: `sha256:8b74278d8b243f1bf71b54b31c44919d809d42bd36f43eb62ce7a8f1eb3bbcf8`;
  - config digest: `sha256:a0758fa4ea26278e221e179a653f3594a927206ec22307cbb48275220efa3d4f` (é o image ID depois de um `docker load` num host com store clássico);
  - LABELs: `autonomia.patch=c2y-rich-2`, `autonomia.patch-sha256=ec2861d6…b52c`, `base-digest`, `base-ref`, `base-image-id`, `waha-sha`, `waha-tag`, `issue=chat#1709`.
- Os 35 arquivos foram conferidos dentro da imagem pelo script, e cada JS tem o `.map`.
- Tarball: `out/autonomia-waha-c2y-rich_2026.9.2-c2y-rich-2b.tar`, 2269844992 bytes, sha256 `bd57c4c771a4412658e93d72738c4058c1fd5bfd8981c648475f9cf7fe577863`. A imagem e o tarball da revisão anterior (`…-c2y-rich-2`) e os do c2y-rich-1 continuam no M2; os da revisão anterior não devem ser usados.

## Ordem de deploy (do contrato)

O PR A do chat2you (entrada e travas) precisa estar no ar **antes** da troca da imagem. Sem ele, um chat2you sem o PR recebe as chaves novas e não as tira (elas ficam gravadas em `content_attributes`, sem efeito na tela; o conteúdo continua igual). Rollback de código: voltar para a imagem c2y-rich-1 ou para a base (abaixo).

### Docker temporário no M2 (para remover depois)
Tudo foi instalado em espaço de usuário, sem sudo:
- lima `v2.2.1`: confere com o SHA256SUMS do release;
- colima `v0.10.3`: confere com o `.sha256sum` do release;
- docker CLI `29.9.1`, estático: o site não publica checksum, então o mesmo sha256 (`7f2c1637…8460`) foi baixado no M2 e no M4 e comparado;
- buildx `v0.38.0`: confere com o digest do asset no GitHub. O `checksums.txt` do release não lista binários darwin.

Para remover, nesta ordem:
1. `colima stop && colima delete`;
2. apagar `~/.colima` (5,6 GB: VM e imagens);
3. apagar `~/opt/c2y-docker` (330 MB: binários, `docker-config` e o `env.sh`).

`~/.docker` não foi criado. Para usar o docker: `. ~/opt/c2y-docker/env.sh`. O colima ignorou `COLIMA_HOME` e usou `~/.colima`.


## ROLLBACK da imagem (só documentação; executar só com OK do Rodrigo)

Estado lido em 16/10, só leitura, no manager `autonomia`:
- o serviço `waha_waha-plus` é do stack `waha`, `replicated 1/1`;
- a imagem atual é `devlikeapro/waha-plus@sha256:ac5d6c13…9598`;
- não há healthcheck na imagem nem no serviço;
- o update é `stop-first`, com `FailureAction=rollback` e `Monitor=5s`;
- o rollback é `stop-first`, com `FailureAction=pause`.

Como é uma réplica só com `stop-first`, a troca de imagem (para frente ou para trás) derruba o WAHA por alguns instantes. Repita o processo em cada motor que receber a imagem c2y.

**Antes do deploy**, guarde o spec atual no manager:

```sh
docker service inspect waha_waha-plus > /tmp/waha_waha-plus_spec_$(date +%Y%m%d%H%M%S).json
```

O arquivo tem env, então ele fica só no host e não é impresso.

**Comando de rollback**, no manager do Swarm de cada motor:

```sh
docker service update \
  --image devlikeapro/waha-plus@sha256:ac5d6c131155df16e4a29c29efdbdf977788a0a4908dbe9d8edf4366202e9598 \
  --with-registry-auth \
  waha_waha-plus
```

- O digest é fixo e a imagem já está no nó, então não há pull. O `--with-registry-auth` só cobre o caso de a tarefa cair em outro nó.
- **Rollback parcial, da c2y-rich-3 para a c2y-rich-2b** (mantém lista, enquete, reações e edição; tira as chaves da rodada 2, o `event.response`, o link e o evento): `docker load -i autonomia-waha-c2y-rich_2026.9.2-c2y-rich-2b.tar` no nó (conferir antes o sha256 `bd57c4c7…7863`), depois `docker service update --image autonomia-waha-c2y-rich:2026.9.2-c2y-rich-2b waha_waha-plus`. Mesmo tempo de troca do rollback total. Um evento ou link já enviado continua no WhatsApp; respostas a eventos deixam de chegar.
- Se a última mudança no serviço tiver sido justamente o deploy da c2y, `docker service rollback waha_waha-plus` volta ao spec anterior. O comando acima é preferível, porque não depende do histórico.
- Portainer: se o stack `waha` é gerido pelo Portainer, volte também a linha `image:` do stack para o digest acima e salve sem "re-pull". Sem isso, o próximo "Update the stack" reinstala a imagem c2y.

**Tempo estimado:** de 1 a 2 minutos até o container novo responder (parar a tarefa, até cerca de 10 s, mais a subida do WAHA, de 20 a 40 s), e de 1 a 3 minutos a mais até as sessões voltarem a `WORKING`.

**Conferência de saúde depois:**

```sh
docker service ps waha_waha-plus --no-trunc --format '{{.Image}} {{.CurrentState}} {{.Error}}' | head -3
# a primeira linha precisa mostrar o digest ac5d6c13… com "Running"

CID=$(docker ps -q --filter label=com.docker.swarm.service.name=waha_waha-plus | head -1)
docker exec "$CID" curl -fsS http://127.0.0.1:3000/ping
# a chave fica dentro do container e nunca aparece no terminal
docker exec "$CID" sh -c 'curl -fsS -H "X-Api-Key: $WAHA_API_KEY" http://127.0.0.1:3000/api/server/version'
# precisa ter "version":"2026.9.2" e "tier":"PLUS", e NÃO pode ter o campo "autonomia"
docker exec "$CID" sh -c 'curl -fsS -H "X-Api-Key: $WAHA_API_KEY" http://127.0.0.1:3000/api/sessions' \
  | grep -o '"status":"[A-Z_]*"' | sort | uniq -c
# todas as sessões em WORKING
```

- Se o `WAHA_API_KEY` do serviço estiver guardado como hash (`sha512:`), use a chave do cofre em vez dele.
- Depois, mande uma mensagem de teste numa caixa de teste. Uma caixa de cliente real não serve para isso.

## O que NÃO foi validado

- O smoke de execução (`/api/server/version`, vazamento no log) não rodou. Fica para o canário amd64.
- O modo builder do script (node em container, `yarn install --immutable`) não foi executado. O caminho usado foi o `WAHA_C2Y_DIST_DIR`.
- Não houve envio real ao WhatsApp nem teste com Chatwoot ou Redis de verdade. O handler e o reporter foram testados com dublês, e o caminho da BullMQ (UnrecoverableError sem retry) não foi exercitado.

## O que NÃO foi validado

- Smoke de execução amd64 (`/api/server/version`, vazamento no log): o daemon do M2 é aarch64. Fica para o canário.
- Modo builder do script (node em container, `yarn install --immutable`): não executado; o caminho usado foi `WAHA_C2Y_DIST_DIR`.
- Nada com WhatsApp, Chatwoot, Redis ou BullMQ de verdade. Os handlers foram testados com dublês. Em especial, falta ver em aparelho: o formato real do `poll.vote` do GOWS (lido do código-fonte: `poll.id` serializado e `selectedOptions` com títulos), reação a mensagem do cliente pelo `setReaction` do GOWS, edição pelo `editMessage`, GIF convertido pelo ffmpeg do motor e a citação (`reply_to`) na enquete.
- `sharp` foi exercitado só no darwin do M2. Na imagem ele existe para linux-x64, mas não rodou. HEIC do iPhone: o libvips pré-compilado não decodifica HEVC, então a expectativa é cair no `sendFile` (registrado no log com a classe do erro).
- Retry pelo `message_updated` (`external_error`): o chat2you só põe `waha_text` no `message_created`. Um reenvio pelo painel volta a usar o `MarkdownToWhatsApp`.
- O log `File message sent: … <data_url>` já existia na main e continua. Os logs novos levam só ids (mensagem do Chatwoot, sessão) e classe de erro.
- Revisão 2b: a assinatura foi testada com um vetor do `OpenSSL::HMAC` do Ruby e com HTTP real num app Nest, mas não com o chat2you de verdade mandando `c2y_message_reaction`. No canário: reagir pelo painel numa caixa de teste e ver 201 no log do conector; mudar o secret da caixa e ver a releitura; caixa com `secret` nulo deve dar 401 com o aviso "inbox secret not readable".
- Revisão 2b: o formato real do voto retirado no GOWS (`poll.vote` com `[]` ou `poll.vote.failed` com `null`) segue sem evento real; os dois caminhos estão cobertos. Teste em aparelho 4 decide qual acontece.
- Revisão 2b: o teto de 16 MB e de 50 MP foi testado no darwin do M2; na imagem linux-x64 não rodou.
