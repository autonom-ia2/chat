# WAHA 2026.9.2 + patch c2y-rich-1 (autonom-ia2/chat#1709, Fase 2)

Este pacote é só código e build local. Não houve deploy, push nem contato com os motores de produção.

- Base do patch: WAHA tag `2026.9.2` = commit `90ba445a0e765701c8910f0fac08176250c3e0fd`
- Patch: `waha-2026.9.2-c2y-rich.patch`, sha256 `cf25028650d86ae7bcb8beb63caf4d9f112ab46b5aee18b302783f7418bdb52e`. Passa em `git apply --check` sobre a tag limpa.
- `/api/server/version` ganha o campo `autonomia = {patch:'c2y-rich-1', rich_native:['options','location','contact'], list_reply:true}`.

## O que o conector faz

**Saída** (`message_created`). Quando `content_attributes.waha_native.kind` é `sendList`, `sendLocation` ou `sendContactVcard` e a mensagem não tem anexo:

- o `chatId` é sempre o do conector, e o `session` também. Do payload só se copiam os campos documentados de cada endpoint;
- a mensagem vai pelo endpoint nativo com o `reply_to`. Ela grava o mesmo mapeamento do `sendText` (parte 1 de 1) e sincroniza o status, então ack e eco funcionam como hoje;
- recusa definitiva (HTTP 4xx ou 501): o `content` vai uma vez como texto, pelo caminho normal;
- 5xx, gRPC (chega como 5xx) ou timeout de 60 s: lança `UnrecoverableError`, sem nova tentativa. O reporter do conector posta uma nota privada ligada à mensagem;
- localização e contato usam um id determinístico: `3EB0` + 18 hex de `sha256(sessão:id da mensagem no Chatwoot:kind)`. A lista não aceita id;
- o log traz só kind, status HTTP, id da mensagem no Chatwoot e sessão. O objeto de erro nunca é logado.

**Entrada.** Quando a mensagem do WhatsApp é resposta a uma lista, `content_attributes.waha_list_reply = {row_id, title}`. A leitura usa `resolveProtoMessage` + `extractMessageContent` do Baileys, que cobrem mensagem temporária e visualização única em GOWS e NOWEB.

Essa leitura roda em toda mensagem recebida, de todas as caixas, e por isso nunca lança erro. Ela fica dentro de um try/catch. Se algo falhar (`esm.b` não carregado, formato inesperado), sai um `warn` curto com a classe do erro, sem conteúdo nem telefone, e a mensagem segue para o Chatwoot sem `waha_list_reply`. Isso foi pedido na revisão final.

## Dois ajustes fora dos arquivos pedidos (necessários)

1. `utils/bull/BaseWorkerHost.ts`: sem este ajuste, todo erro era embrulhado em `JobDetailedError`, a BullMQ não reconhecia o `UnrecoverableError` e repetia o job. O embrulho ainda fazia `util.inspect` do erro do axios, com config e headers, e isso ia para o Redis. Agora o `UnrecoverableError` passa intacto, como já acontecia com o `DelayedError`.
2. `apps/chatwoot/error/ChatWootErrorReporter.ts`: o reporter só posta a nota quando não sobra tentativa. Como a fila `message_created` tem retry exponencial, a nota não sairia. Agora o `UnrecoverableError` é tratado como última tentativa.

Ninguém mais no WAHA 2026.9.2 lança `UnrecoverableError`, então os dois ajustes não mudam outro fluxo.

## Arquivos de dist que mudam

A lista completa está em `dist-sha256.txt`, no formato `antes depois caminho`. Quando o arquivo é novo, a coluna "antes" traz `NEW`.

O overlay copia esses 9 JS e os `.map` correspondentes. Os `*.test.js` não entram.

## Script `build-waha-c2y-rich.sh`

```sh
WAHA_C2Y_BASE=<repo@sha256:...|sha256:<image id>> ./build-waha-c2y-rich.sh [tag]
```

1. Exige uma base fixada por digest ou image ID, já presente na máquina, e recusa tag e pull. A base precisa ser `linux/amd64`.
2. Confere o sha256 dos 7 JS originais na base e confere que os 2 JS novos não existem nela. Se algo divergir, o script para.
3. O builder usa `node:24.11.0-bookworm-slim`, que também precisa estar local, e confere `node --version`. Ele busca a tag e confere o SHA, aplica o patch, roda `yarn install --immutable` (o equivalente do `--frozen-lockfile` no yarn 4.17.1, que é o `packageManager` da tag) e `yarn build`. Depois exige que os 9 JS saiam idênticos aos hashes revisados.
4. O overlay copia só esses JS e `.map`, com `--platform linux/amd64` e `--pull=false`. Ele grava as LABELs `autonomia.base-digest`, `base-image-id`, `waha-sha`, `waha-tag`, `patch`, `patch-sha256` e `issue`, e confere de novo os hashes dentro da imagem.
Atualizações: os arquivos da base e da imagem final agora são lidos com `docker create` + `docker cp`, sem executar nada. `WAHA_C2Y_DIST_DIR` aceita um dist já construído e confere os hashes; nesse modo o builder é dispensado. O overlay roda com `docker buildx build --platform linux/amd64 --pull=false` sobre uma tag local fixa no ID da base. `WAHA_C2Y_BASE_SOURCE` grava a referência upstream na label `autonomia.base-digest`. `WAHA_C2Y_OUT_DIR` faz o `docker save` e gera o `.sha256`. Num daemon que não é amd64, o smoke só é pulado com `WAHA_C2Y_SKIP_SMOKE=1` explícito.

5. O smoke roda isolado, com `--network none` e sem mount. Ele confere a versão `2026.9.2` e o campo `autonomia` em `/api/server/version`, e verifica que nem a chave nem `x-api-key` aparecem no log.

## Validação feita (no M2)

- `tsc --noEmit`: 0 erros. `yarn build`: ok. `oxlint --deny-warnings` nos arquivos tocados: 0.
- Testes novos: 3 suítes, 56 testes, todos passando. Os casos de lista, localização e contato usam o chatId do conector, o reply_to, o id determinístico e o mapeamento. Há casos de 400, 422 e 501 caindo para texto uma vez, e de 500, 502 e timeout virando `UnrecoverableError` sem texto e sem mapeamento. Outro teste confere que o log não tem chave, header, telefone nem nome. A resposta de lista é testada em NOWEB e GOWS, nas versões temporária e de visualização única. Quatro testes cobrem a exceção: o extrator lança, o Baileys não está carregado, um getter quebrado, e a chamada sem logger. Nos quatro a função devolve `null`, e o log não leva telefone nem conteúdo. Sem o try/catch, os quatro falham; isso foi conferido.
- Suíte unit completa: 10 testes falham em 4 suítes, exatamente as mesmas da tag sem patch (ESM do Baileys no jest e ambiente). O patch não traz falha nova.
- `listreply-real-baileys.js`: roda o `ListReply.js` do dist com o **Baileys real**. Os 8 casos passam.
- Servidor local (`node dist/main`, NOWEB, sem sessão): `/api/server/version` devolveu o campo `autonomia`, e o log não tem a chave.

## Imagem construída (M2, 16/10/2026)

- Base: `devlikeapro/waha-plus@sha256:ac5d6c131155df16e4a29c29efdbdf977788a0a4908dbe9d8edf4366202e9598`. É a mesma dos dois motores de produção. Veio do host por `docker save | docker load`, em stream, sem gravar arquivo no host. Depois do load:
  - o config digest é `sha256:a6b5fc41fcfd1a8eec373663675a9fb2f247a677744fdb08876fd79a66c70641`, que é o image ID no host;
  - os 28 diff_ids batem com os do host;
  - no store containerd do colima, o ID local vira o digest do manifest, `sha256:7179f432…aff4`.
- O passo 1 do script passou na base de produção: os 7 JS originais batem com os hashes "antes" e os 2 novos não existem nela.
- Chamada usada:

  ```sh
  WAHA_C2Y_BASE=sha256:7179f432b837e5f902f49005ec5ca762bf5fbc09cf2b8538af95a077e6d5aff4 \
  WAHA_C2Y_BASE_SOURCE=devlikeapro/waha-plus@sha256:ac5d6c13…9598 \
  WAHA_C2Y_DIST_DIR=…/waha/dist WAHA_C2Y_OUT_DIR=…/out WAHA_C2Y_SKIP_SMOKE=1 \
  ./build-waha-c2y-rich.sh autonomia-waha-c2y-rich:2026.9.2-c2y-rich-1
  ```

- Imagem final: `autonomia-waha-c2y-rich:2026.9.2-c2y-rich-1`, linux/amd64, 46 camadas (28 da base e 18 de COPY).
  - ID local (índice OCI): `sha256:e69aa891582b70f8ce2484702ba551d871162b4e295fd92b76419a2e690c7221`;
  - manifest amd64: `sha256:657d6e5c30f6df1a5a289e6cf6b5e0223b1a06dbbf8a9758b0b7c3d1279416a5`;
  - config digest: `sha256:6831d87ea851e878e01ef2f58572bec5aca33209f64d8a11e7109bf36c40e97f`. É esse o image ID que aparece depois de um `docker load` num host com o store clássico.
  - O índice também traz uma attestation de proveniência do buildx (`sha256:741d2724…b2d`).
- Os 9 JS foram conferidos dentro da imagem com `docker create` + `docker cp` + sha256 local, e todos batem com a coluna "depois".
- Tarball: `out/autonomia-waha-c2y-rich_2026.9.2-c2y-rich-1.tar`, com 2269703168 bytes e sha256 `b89d2ec8ef1e5079947ffa3dbad024a233a10c99483cefe22492df2212f76261`.
- O smoke de execução não rodou: o daemon do M2 é aarch64 e não há emulação amd64. Ele fica para o canário.

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
