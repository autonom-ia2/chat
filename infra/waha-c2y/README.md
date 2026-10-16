# WAHA 2026.9.2 + patch c2y-rich-2 (autonom-ia2/chat#1709)

Este pacote é só código e build local. Não houve deploy, push nem contato com os motores de produção.

- Base do patch: WAHA tag `2026.9.2` = commit `90ba445a0e765701c8910f0fac08176250c3e0fd`
- Patch: `waha-2026.9.2-c2y-rich.patch`, sha256 `ec2861d600ba74377bd458f059b47a9951e4a492682f465688a1dbe12eefb52c` (47 arquivos). Passa em `git apply --check` sobre a tag limpa. Contém o c2y-rich-1 inteiro mais o c2y-rich-2, já com as correções da revisão (revisão **2b**, abaixo).
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
