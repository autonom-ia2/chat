# #1709: teste real em aparelho, 17/10/2026, relatório

**Resultado da rodada 1: teste interrompido às 06:02, depois de 9 dos 27 passos.** O motor GOWS caiu duas vezes, e a regra do Rodrigo manda parar quando o motor cai.

**Resultado da rodada 2 (06:14 a 06:59, motor com `GODEBUG=madvdontneed=0`): os 18 passos que faltavam foram feitos, sem nenhuma queda nem panic.** Detalhes na seção "Rodada 2 (GODEBUG)", no fim.

Horários de Brasília. Nada de produção: motor `waha-c2y-teste1709` (c2y-rich-5, GOWS) em 127.0.0.1:3712 no M2, demo chat2you 3709, banco `chatwoot_demo_1709_int`.

## Montagem conferida antes de começar (só leitura)

- **Cache de capacidades** do motor 3712 preenchido.
  - `types`: options, location, contact, poll, link_button, event.
  - `actions`: react, edit.
  - `GET /api/server/version` declara list_reply, poll_vote, reactions, edit, media_as_media, event_response e view_once_notice.
- **Rails**: `WAHA_RICH_NATIVE_ENGINES` inclui `http://127.0.0.1:3712`, e `engine_for` da caixa 8 cai no 3712. A flag `whatsapp_rich_native` está ligada na conta 1, e o dono do token é o user 1.
- **Sessões**: A (0656) e B (1242) em WORKING, com capping NONE e sem timelock.
- **Conversa certa do cliente**: display **89** (id **94**), contato 92 (+5511926791242). A display 88 (id 93) indicada no pedido é a conversa "Integração WhatsApp" da própria sessão, não a do cliente.
- **Ajuste de ambiente**, problema da demo e não do #1709 (pedido do preparador, antes de qualquer anexo da empresa):
  - `FRONTEND_URL=http://host.lima.internal:3709` entrou em `teste-real/rails-extra.env`, para o motor dentro do colima conseguir baixar a mídia que sai do painel. Backup do arquivo: `teste-real/run/rails-extra.env.bak-*`.
  - Rails reiniciado pelo `reiniciar.sh`. O Playwright usa `--host-resolver-rules=MAP host.lima.internal 127.0.0.1` só para os prints.

## Ritmo

- Uma ação por vez, com espera aleatória de 25 a 36 s entre ações.
- Antes de texto do cliente: sendSeen, depois startTyping proporcional ao texto (9,5 s no R1), depois stopTyping.
- **Ações no WhatsApp: 9** (R1, E8, R2, E1, R3, E2, R4, voto R13 pela API que falhou, voto R13 pelo celular).
- Só entre o 1242 e o 0656. Nenhuma outra conversa da caixa 8 foi lida.

## Tabela de passos

| Passo | Horário | Resultado | Evidência |
|---|---|---|---|
| R1 texto do cliente | 05:40:51 | **OK** | sendText 201, id `…3EB06E67317198FE0B3CCB`. Chat2you: msg 1231, incoming, conversa 94 nova. B: ack READ (markAsRead ligado). |
| E8 texto formatado | 05:41:50 | **OK** | API 200, msg 1232, status read. Painel: `**confirmada**, _amanhã cedo_, ~~sábado~~, \`VST-1709\``. B recebeu extendedTextMessage com `*confirmada*, _amanhã cedo_, ~sábado~ e … \`VST-1709\``. A conversão está certa. |
| R2 localização | 05:42:32 | **OK** | sendLocation 201. Msg 1233 com anexo tipo location e `shared_location {lat -23.5613, lng -46.6565, name "Minha casa"}`. O print mostra o cartão "Ver no mapa". |
| E1 lista de opções | 05:43:20 | **FALHA no aparelho** | API 200, `rich_message_sent_as: native`, msg 1234 lida. Log do motor: `native message sent`. B recebeu `listMessage` (ack DEVICE, depois READ), mas **o app do celular do 1242 não exibiu**, mesmo depois de o app terminar de atualizar (confirmado pelo Rodrigo). A lista não foi reenviada. Fica como "entregue ao protocolo, não exibida no app; investigação depois do teste". |
| R14 escolha na lista | — | **NÃO FEITO** | Depende do E1. A API do WAHA não tem `sendListReply` (404); foi pedido toque humano, e a lista não apareceu. |
| R3 contato (vcard) | 05:53:40 | **OK** | sendContactVcard 201. Msg 1235 com anexo contact e `shared_contacts [{full_name "Teste Vistoria 1709", phones ["+55 11 4000-1709"], wa_id "551140001709"}]`. O print mostra o cartão com "Conversar / Salvar contato". |
| E2 enquete | 05:54:26 | **OK** | API 200, `rich_message_sent_as: native`, msg 1236 lida. B recebeu `pollCreationMessageV3`. O Rodrigo confirmou que a enquete apareceu no 1242. |
| R4 voz (ptt) | 05:55:27 | **OK** | sendVoice 201, ogg/opus de 4,4 s com voz sintética do macOS. Msg 1237 com anexo audio/ogg. O print mostra o player de mensagem de voz, 0:04, com o microfone. |
| R13 voto pela API | 06:01:49 | **FALHA (motor)** | `POST /api/sendPollVote` → **500**: panic do GOWS (nil pointer) ao ler a enquete no banco da sessão B. Ver bug 2. Não foi repetido. |
| R13 voto pelo celular (Rodrigo, "Quarta") | ~06:02 | **OK, com atraso** | O motor caiu às 06:02:06 (bug 1) e voltou às 06:04:26. Chegou **depois do reinício**: msg 1246 "Votou: Quarta" com `c2y_hidden`, `poll_vote_applied_to: 1236` e `c2y_ai_turn.kind=poll_vote`. A msg 1236 ganhou `poll_votes: [{Contact 92, ["Quarta"]}]`. O print mostra Quarta 1. |
| R13 troca do voto | — | **NÃO FEITO** | Teste parado antes. |
| R5–R12, R15, R16 | — | **NÃO FEITO** | Teste parado. |
| E3–E7, E9–E12 | — | **NÃO FEITO** | Teste parado. |

**Duplicidade: nenhuma.**
- Na sessão B, desde as 05:40: 1 contactMessage e 1 pollCreationMessageV3.
- No chat2you, uma mensagem para cada evento (1231 a 1237 e 1246).
- O Rodrigo conferiu pelo print do 0656: tudo aparece uma vez só.

**Tiques:** as mensagens da empresa ficaram com status read no chat2you (1232, 1234 e 1236), e as do cliente com ack READ na sessão B.

**Prints (1440):**
- `00-inicio.png`: conversa 88, a de integração, antes do teste.
- `01-conversa-89-final.png`: conversa do cliente no fim, com localização, lista, contato, enquete com voto e voz.

## Quedas do motor

1. **05:55:40.**
   - O container morreu com `die exit=143` e voltou pela política `unless-stopped`. Sessões WORKING às 05:56:02.
   - Não houve docker stop/kill, e o log não registra erro antes da queda: a última linha é 05:55:34.
   - Aconteceu 13 s depois do R4. As duas leituras minhas que caíram nessa janela falharam (500 e conexão cortada).
   - Nenhum script meu chama `/start`. O `POST /api/sessions/…/start` no log é o contexto que o MediaManager carrega desde a criação da sessão.
2. **06:01:40 a 06:02:06.**
   - 06:01:40: panic na sessão B, `handleReceipt` → `message_mapper.go:154`, "oneof type already set".
   - 06:01:49: panic no `sendPollVote`, `message_mapper.go:117`, nil pointer em `json.RawMessage`.
   - 06:02:06: **`fatal error: found bad pointer in Go heap`**. As duas sessões passaram a "Stream error, reconnecting", e o Node recebeu SIGTERM.
   - Container reiniciado às 06:04:06 (die exit=143, restarts=2). Sessões WORKING às 06:04:26.
   - Stacks completos em `panics-gows.txt`. Log sanitizado do motor desde 05:40 em `motor-log-sanitizado.txt`.

## Bugs

| # | Severidade | Onde | Reprodução |
|---|---|---|---|
| 1 | **Crítico, no ambiente de teste** | GOWS dentro da imagem c2y-rich-5: `fatal error: found bad pointer in Go heap`, mais 2 panics ao ler mensagem do banco (`storage/sqlstorage/message_mapper.go:117` e `:154`) | Sessão B recebe enquete (05:54), recibos e voto. Ao ler a mensagem guardada, o GOWS dá panic e depois corrompe o heap. **Hipótese, não comprovada:** a imagem é **amd64 emulada** num colima **aarch64** (`docker image inspect` → amd64; `colima list` → aarch64). Isso explicaria um heap corrompido sem causa no código. Se for isso, produção (amd64 nativo) não reproduz. Precisa ser confirmado num host amd64 antes de concluir qualquer coisa sobre o #1709. |
| 2 | Alto, só na simulação do cliente | WAHA `sendPollVote` (GOWS `SqlMessageStore.GetMessageWithRetries` → `MessageMapper.Unmarshal`, `message_mapper.go:117`) | `POST /api/sendPollVote` com `pollMessageId=false_109913195958474@lid_3EB01446A3EBFEB24549DD` na sessão B → 500. Não envolve o código do chat2you. Mesma trilha de leitura do banco do bug 1. |
| 3 | Médio | Lista nativa (E1) no app do celular | `rich_message type=options` sai como `listMessage`, aceito pelo motor e marcado como lido, mas o app do 1242 não exibe. O escopo já avisa que "List Messages are fragile". Investigar: versão do app, conta Business ou pessoal, formato da `listMessage` do GOWS. |
| 4 | Baixo, só no ambiente | Demo: `FRONTEND_URL=http://localhost:3709` | O motor dentro do colima não baixa a mídia que sai do painel. Ajustado só na demo. Não é do #1709. |

Nenhum bug foi achado no código do chat2you ou do conector nos passos que rodaram. Recebimento de texto, localização, contato e voz, e envio de formatação, enquete e lista ao protocolo saíram como o escopo descreve. O voto chegou e foi aplicado, com 2 min de atraso por causa da queda.

## Estado final

- Sessões **A 0656 e B 1242: WORKING**, capping NONE, sem timelock (06:06:04). **Não foram desconectadas**, a decisão é do Rodrigo.
- Motor de pé (restarts=2). Rails da demo com `FRONTEND_URL=host.lima.internal`.
- Nenhuma ação no WhatsApp depois das 06:02.
- **Ficou de fora: 18 de 27 passos.** Para retomar: rodar o motor num host amd64, ou numa imagem arm64, ou confirmar a hipótese do bug 1 antes, para a queda não se repetir.

## Arquivos

- `relatorio.md` (este arquivo)
- `panics-gows.txt`: os 3 stacks completos, sem segredo
- `motor-log-sanitizado.txt`
- `acoes-cliente.jsonl`: log das ações do cliente, com HTTP e ids
- `00-inicio.png` e `01-conversa-89-final.png`
- Scripts do teste no M2: `/Users/Shared/maccluster-demo-1709-int/teste-real/run/`
  - `cli.py`: cliente, com espera humana e conferência das sessões
  - `emp.py`: empresa
  - `painel.cjs` e `p.sh`: prints e ações pelo painel
  - `db.sh`, `bm.py`, `w.py`, `cw.py`: leituras
  - todos imprimem com os segredos trocados por `<REDACTED>`

Observação: numa chamada inicial ao `GET /api/v1/profile` da demo, o `access_token` do john (demo local, 24 caracteres) apareceu uma vez na saída da minha ferramenta, antes de eu ajustar o filtro. Não foi gravado em arquivo. É token só da demo; dá para trocar quando a demo for apagada.

## Rodada 2 (GODEBUG)

### O que mudou e por quê

- **Hipótese em teste:** as quedas da rodada 1 vêm da emulação. A imagem é amd64 e roda no colima aarch64 do M2 sob QEMU user-mode 7.0. O QEMU não devolve zerada a página que o Go libera com `MADV_DONTNEED`, e o heap do GOWS se corrompe (ver `../2026-10-17-1709-gows-panic.md`). O ajuste conhecido é `GODEBUG=madvdontneed=0`.
- **Esta rodada é o teste A/B, com o ajuste.** O código, a imagem, as sessões, o banco do motor e o roteiro são os mesmos da rodada 1. Muda só a variável.
- **06:14:29: motor recriado** por `teste-real/recriar-motor.sh` (no M2), com as mesmas opções:
  - imagem `c2y-rich-5`, rede `waha-teste1709`, porta `127.0.0.1:3712`, `unless-stopped`;
  - volume `waha-c2y-teste1709-sessions` preservado, e o mesmo Redis;
  - as 11 variáveis do container antigo, lidas do `docker inspect`, sem imprimir valor;
  - mais `GODEBUG=madvdontneed=0,netdns=cgo`. O `netdns=cgo` já vinha da imagem e foi mantido.
- **Conferido no processo do GOWS** (`/proc/<pid>/environ` do `qemu-x86_64 /app/gows`): `GODEBUG=madvdontneed=0,netdns=cgo`.
- **Sessões A (0656) e B (1242): WORKING às 06:14:50, sem QR novo**, capping NONE, sem timelock.
- **Rollback.** O container antigo ficou parado como `waha-c2y-teste1709-old` até o fim e foi removido às 06:59, depois da rodada. O volume das sessões não é afetado.

### Ritmo

Foi o mesmo da rodada 1:

- uma ação por vez, com espera aleatória de 20 a 60 s;
- antes de cada texto do cliente: sendSeen, startTyping proporcional (6,5 s e 12 s) e stopTyping;
- só entre o 1242 e o 0656;
- conferência das duas sessões (status, capping, timelock) antes e depois de cada ação;
- `docker inspect` (restarts) e varredura do log do motor atrás de panic, fatal ou Stream error depois de cada passo.

Nenhuma lista foi enviada.

### Tabela de passos (horário de Brasília)

| Passo | Hora | Motor | O que o chat2you gravou (conversa 94 / display 89) | Sessão B / aparelho | Resultado |
|---|---|---|---|---|---|
| R5 foto | 06:17:45 | sendImage 201 | msg 1254, anexo image/jpeg, legenda | ack DEVICE→READ | **OK** |
| E5 convite de evento (API do painel) | 06:19:43 | sendEvent nativo (`native message sent: kind=sendEvent`) | msg 1255, `rich_message.type=event`, `rich_message_sent_as: native`, status read | Rodrigo viu o convite no 1242 | **OK** |
| R15 "Vou" (toque humano) | 06:21:07 | evento `event.response` | 1255 ganhou `event_responses [{Contact 92, going}]`; msg 1256 escondida (`c2y_hidden`, `event_response_applied_to: 1255`, `c2y_ai_turn.kind=event_response`). Print: "Vou: 1 · Não vou: 0 · Talvez: 0" | tocado pelo Rodrigo | **OK** |
| R6 álbum (2 fotos, 2 s) | 06:21:21 e 06:21:24 | sendImage 201 e 201 | msgs 1257 e 1258; o painel agrupa as duas como álbum ("Foto 1 de 2") | ack READ | **OK** |
| E6 cartão de link (API do painel) | 06:22:09 | sendLinkCustomPreview nativo | msg 1259, `link_button`, e o `image_url` passou a ser a cópia própria (`host.lima.internal:3709/rails/active_storage/...`), como o SafeFetch exige | B recebeu extendedText com a URL. Rodrigo confirmou o cartão com imagem | **OK** |
| R7 figurinha | 06:23:05 | sendSticker 201 | msg 1260, anexo image/webp. O painel mostra só a figurinha, sem balão | stickerMessage, READ | **OK** |
| E7 foto webp (painel, anexo) | 06:26:16 | sendImage (motor) | msg 1261, anexo webp com legenda, status read | imageMessage. Rodrigo confirmou | **OK** |
| E7 vídeo (painel, anexo) | 06:27:18 | sendVideo (motor). A linha `ERROR … ffmpeg … scale=72` é só o nível do log da miniatura | msg 1262, anexo mp4 | videoMessage. Rodrigo confirmou | **OK** |
| R8 reação a mensagem da empresa | 06:28:53 | PUT /api/reaction 200 | 1232 ganhou `reactions [{👍, Contact 92}]`; msg 1263 escondida (`reaction_applied_to`) | — | **OK** |
| R9 texto + edição pelo cliente | 06:29:28 / 06:30:28 | sendText 201 / PUT …/messages/{id} 200 | msg 1264 trocou o texto e ganhou `edit_history` (anterior "…as 14h") e `edited_at`; msg 1265 escondida (`edit_applied_to`). O painel mostra "Editada" | — | **OK** |
| E9 resposta citando o cliente (painel) | 06:32:42 | texto com reply | msg 1266, `in_reply_to: 1264` | B: `reply=True`. Rodrigo confirmou a citação | **OK** |
| E11 edição da empresa (painel, menu Editar) | 06:39:55 (7 min após o envio) | edit | 1266 ganhou `edit_history` (sender User 1); msg 1267 escondida com `external_echo` e `edit_applied_to` | Rodrigo viu "Combinado, 15h fica ótimo. Até lá!" | **OK** |
| E10 reação da empresa | 06:40:55 | PUT /api/reaction 200, `reaction set` | 1254 ganhou `reactions [{❤️, User}]`; o eco (msg 1268, escondida) trocou `sender_id` para nulo, que é a "empresa como um autor só" do desenho | Rodrigo viu o ❤️ | **OK, mas não pela tela** (ver o achado A) |
| R10 cliente apaga a 2ª foto do álbum | 06:41:56 | DELETE …/messages/{id} 200 | 1258 ganhou `deleted_by_contact_at` e a foto ficou guardada, com o selo "Apagada pelo cliente"; msg 1269 (nota privada do conector, `revoke_applied_to`) | — | **OK** (ver o achado C) |
| R11 citação de mensagem antiga da empresa | 06:42:50 | sendText 201 com `reply_to` | msg 1270, `in_reply_to: 1232` (a E8 das 05:41). O painel mostra a citação com a formatação certa | — | **OK** |
| R12 encaminhar | 06:44:13 | forwardMessage 201 | msg 1271, `forwarded: true`. O painel mostra "Encaminhada" | — | **OK** (ver o achado D) |
| R13b troca do voto para "Sexta" (API, 1 tentativa) | 06:44:51 | **sendPollVote 201** (na rodada 1 deu 500 com panic) | 1236: `poll_votes [{Contact 92, ["Sexta"]}]`, com o voto anterior substituído; msg 1272 escondida (`poll_vote_applied_to`, `c2y_ai_turn.kind=poll_vote`). Print: Segunda 0, Quarta 0, **Sexta 1** | — | **OK** |
| E12 empresa apaga o vídeo (painel, Excluir) | 06:45:45 | DELETE no motor; conector: `Message '…' deleted` | 1262 com `deleted: true` ("Esta mensagem foi excluída"); msg 1273 (nota privada do conector) | Rodrigo confirmou que sumiu para todos | **OK** (ver o achado C) |
| R16 ligação perdida (toque humano) | 06:49:20 e 06:49:39 | eventos de chamada (received → rejected) | 1ª ligação: linha "Ligação de voz **recusada**" (`by_me: true`) + atividade escondida. 2ª: "Ligação de voz **perdida**" (`outcome: missed`) + atividade escondida. Uma linha por ligação | — | **OK** (ver a observação E) |

**Confirmação visual do Rodrigo no 1242:** "Tudo certo. Chegou tudo". Isso cobre o link com imagem, a foto webp, o vídeo apagado para todos, a resposta citada editada e o ❤️.

**Duplicidade:**
- Nenhuma mensagem duplicada no chat2you. Cada ação gerou 1 mensagem, ou 1 mensagem e 1 atividade escondida.
- As duas notas privadas de "excluída" (achado C) não são duplicatas de mensagem, mas repetem visualmente uma informação que a bolha já mostra.
- Nenhuma nota ou aviso saiu para o cliente. As msgs 1269 e 1273 são `private=true`, e a sessão B não recebeu texto nenhum depois do encaminhamento.

**Tiques:** as mensagens da empresa ficaram read no chat2you (1255, 1259, 1261, 1262, 1266). As do cliente ficaram com ack DEVICE→READ na sessão B, porque o `read_receipt` foi enviado pelo chat2you.

**Conversa:** ficou aberta (status 0) o tempo todo. As ligações e os eventos escondidos não reabriram nada nem criaram conversa nova. Não há agente de IA na caixa 8 (`autonomia_agent_inboxes` vazio para a caixa e 0 `autonomia_agent_events` na conversa 94), então não há página de Desempenho a mostrar.

### Veredito da hipótese

- **Com `GODEBUG=madvdontneed=0`: nenhuma queda em 44 min e 47 s de motor** (06:14:29 a 06:59:16, `restarts=0`). Houve **0** panic, fatal error, bad pointer, Stream error ou SIGTERM no log inteiro.
- **Carga desta rodada** sobre o motor e o banco de mensagens do GOWS:
  - 18 ações no WhatsApp: 11 do cliente pela API, 5 da empresa e 2 toques humanos;
  - **13 leituras de mensagem guardada pela API** (`GET …/chats/…/messages`), contra 10 na rodada 1 até a queda;
  - mais as leituras internas: o **`sendPollVote`, que lê a enquete guardada (o exato caminho do panic de `message_mapper.go:117` na rodada 1)**, o encaminhamento, que lê a mensagem guardada, 2 edições, 2 apagamentos, 3 reações, recibos e a decifragem do voto.
- **Rodada 1, sem o ajuste:**
  - 1ª queda 31 min depois de o container subir, logo depois de um sendVoice;
  - 2ª queda **6 min e 25 s depois do reinício**, com 2 panics ao ler mensagem guardada e `fatal error: found bad pointer in Go heap`.
- **Conclusão:** o resultado é **compatível com a hipótese e forte a favor dela**. O mesmo `sendPollVote` que derrubava agora responde 201, e o processo durou mais que as duas janelas de queda somadas, com mais leituras.
  - Não é prova matemática: uma rodada de 45 min não exclui uma queda rara.
  - A prova definitiva continua sendo rodar a imagem num host amd64 nativo, que é o caso de produção, ou repetir sem o ajuste, para ver a queda voltar.
  - Para os testes no M2, **o motor emulado deve sempre subir com `GODEBUG=madvdontneed=0`**.

### Achados novos

| # | Severidade | Onde | O quê |
|---|---|---|---|
| A | **Alto** (reação da empresa pela tela, caixa WAHA comum) | `components-next/conversa-canal/reacaoDoAtendente.js` (`estadoDaReacao`) e o "Reagir" do menu (`Message.vue`: `react: isReactable && !pele`) | Na pele nova (#1702), o botão de reagir e o "Reagir" do menu só aparecem com `mensagem.sourceId`. Na caixa WAHA da demo, **nenhuma** das 43 mensagens tem `source_id` (o conector WAHA não grava esse campo), e o atendente não acha onde reagir. A conversa traz `whatsapp_api_message_actions: ["react","edit"]` e a rota funciona: o E10 foi feito pela mesma rota da tela (`POST …/messages/1254/reaction`) e chegou ao celular. **Falta conferir (só leitura) se em produção as mensagens da caixa WAHA comum também vêm sem `source_id`.** Se vierem, a reação pela tela não existe lá. "Editar" e "Excluir" aparecem normalmente. |
| B | Baixo | Bolha editada da empresa (print T13) | O selo "Editada" encosta no fim do texto ("…Até lá!Editada"), sem espaço. |
| C | Médio (ruído) | Conector WAHA, ao apagar (R10 e E12) | Além da marca na própria bolha ("Apagada pelo cliente" / "Esta mensagem foi excluída"), entra uma **nota privada amarela** "❌ Esta mensagem foi excluída no WhatsApp" citando a mensagem. Na apagada pelo cliente, a citação mostra a miniatura quebrada ("Mensagem de imagem" com ícone de imagem faltando). A informação aparece duas vezes. Não sai para o cliente. |
| D | Médio | Texto formatado recebido (R12, encaminhado) | A E8 encaminhada de volta chegou como `**confirmada**, *amanhã cedo*, ~~sábado~~`, e a bolha recebida mostra os asteriscos crus ("**\*confirmada, \*amanhã cedo**"). Na citação (R11) e na saída (E8), a mesma formatação aparece certa. É a conversão de negrito e itálico no texto **recebido**. Não é exclusivo do encaminhamento, mas foi a primeira vez que um texto formatado entrou pelo lado do cliente. |
| E | Observação de produto (não é bug) | `app/services/waha/rich_native/inbound/call.rb` | A 1ª ligação virou "recusada" porque o evento veio com `by_me: true`: o 0656 estava em **Não Perturbe**, e o próprio aparelho recusou. A classificação está coerente com o evento, conforme o Rodrigo confirmou. Melhoria opcional, sem mudança agora: para o atendente, "recusada" pode parecer gesto humano quando foi o aparelho. |

Bugs 1 e 2 da rodada 1 (GOWS): não se repetiram com o ajuste (veredito acima). Bug 3 (lista) segue na investigação separada.

### Prints

A pasta `prints-painel/` tem os prints do painel em 1440, conversa 89, todos olhados.

**Um print por item marcante (T01 a T16):**

| Print | Item |
|---|---|
| T01 | localização |
| T02 | contato |
| T03 | voz |
| T04 | enquete com a troca para Sexta |
| T05 | convite com "Vou: 1" |
| T06 | foto do cliente com o ❤️ da empresa |
| T07 | álbum com a foto apagada pelo cliente |
| T08 | link |
| T09 | figurinha |
| T10 | foto webp e vídeo apagado |
| T11 | 👍 do cliente |
| T12 | edição do cliente |
| T13 | resposta citada editada |
| T14 | citação |
| T15 | encaminhada |
| T16 | ligações recusada e perdida |

Nos prints por item, a bolha fica centrada, e uma bolha muito alta pode encostar na caixa de resposta.

**A conversa inteira em trechos (T17 a T24):** cada trecho começa na primeira bolha que o anterior cortou.

### Estado final (06:59)

- Motor `waha-c2y-teste1709` de pé com o ajuste (`restarts=0`). O container `-old` foi removido; volume e Redis estão intactos.
- **Sessões A 0656 e B 1242: WORKING**, capping NONE, sem timelock. **Não foram desconectadas.**
- Demo: as sessões de login do john foram renovadas (`revoke_all_sessions` no login local), porque o limite de sessões barrava o Playwright com 409. Isso é só da demo. O `agent.token` da API não foi afetado.
- `painel.cjs` ganhou os modos `attach`, `menu`, `store` e `tour`. O botão de envio passou a ser clicado, porque o Enter não envia nesse compositor; e o menu da mensagem agora abre pelo botão "Opções da mensagem". Backup em `run/painel.cjs.bak-r2`.

### Arquivos da rodada 2

- `motor-log-rodada2-sanitizado.txt`: log do motor, do subir às 06:14 até 06:59, sem segredo.
- `acoes-cliente-rodada2.jsonl`: log das ações do cliente nas duas rodadas, com HTTP e ids.
- `prints-painel/T01…T24`.
- No M2: `teste-real/recriar-motor.sh`, `run/st.sh`, `run/motor-log-rodada1-final.txt` (o log do container antigo, salvo antes de recriar) e `run/shots/r2-*.png`, que são os prints de cada ação da empresa.
