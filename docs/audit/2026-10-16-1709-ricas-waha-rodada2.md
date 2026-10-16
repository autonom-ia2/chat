# #1709 rodada 2 — lado do chat2you (entrada na caixa WAHA comum, link e evento)

Branch `feat/1709-ricas-waha` (PR #1741). Construído por cima da rodada 1, sem push. O conector `c2y-rich-3` (lado
do WAHA, `infra/waha-c2y/`) é construído à parte; este documento só cobre o chat2you.

## Regra de sempre

- Tudo novo atrás da flag por conta `whatsapp_rich_native`. Na caixa WAHA comum, só com o conector customizado.
- Flag desligada = main: as chaves `waha_*` do conector SEMPRE saem (`Waha::RichNative::Inbound`) e a mensagem fica
  igual (texto, tipo, privacidade, anexos). Exceções, mensagens que a main nunca recebe, viram atividade escondida:
  voto de enquete nativa, resposta a evento nativo e o aviso de visualização única que o motor não abriu.
- Só o conector (dono do token da caixa) manda as chaves. As chaves que o chat2you grava estão em
  `Waha::RichNative::ContractGuard::STORED_KEYS` e nunca entram pela API (`ForgeryGuard`).

## Item 0 — formato da tela do Frontend geral (#1702)

| Dado | Onde | Formato |
|---|---|---|
| Reação | mensagem reagida | `reactions = [{emoji, sender_type: Contact\|User, sender_id\|null, at}]`. Contact: uma por contato. User = número da empresa: UMA só (painel: `sender_id` = atendente; celular: `null`). Emoji `''` remove; lista vazia tira a chave. |
| Edição | mensagem editada | `content` novo, `edited_at`, `edit_history = [{content, edited_at, sender_type, sender_id\|null}]`, antigo→novo, máx. 10. |
| Ligação | atividade | `waha_call_summary = {call_id, outcome: missed\|rejected\|accepted (+ringing enquanto toca), is_video, at, ended?: true}`. |
| Desconhecida | mensagem do cliente | `is_unsupported: true`, `unsupported_kind ∈ poll\|gif\|pinned\|edit\|view_once\|unknown` (tabela exata, sem regex). |
| Enquete | mensagem da enquete | `poll_votes = [{sender_type: Contact, sender_id, options: [títulos], at}]`, um por eleitor; retirado = `options: []`. A mensagem do voto vira atividade escondida (`poll_vote_applied_to`). |
| Absorvida | atividade | `c2y_hidden: true` + `*_applied_to`. |

Max avisado por SendMessage ("Frontend geral Max") com o branch e o SHA `e0e79657a0`.

## Itens de entrada (com a flag, caixa WAHA comum)

| Item | Chave do conector | O que o chat2you grava |
|---|---|---|
| 1 Voz (PTT) | `waha_media.kind = voice` | `attachments[].meta.is_voice_message: true` (áudio que é arquivo, `kind = audio`: `false` explícito); nome `no-filename.*` → `audio-<AAAAMMDD-HHMMSS no fuso da conta>.ogg` (blob renomeado antes do upload, testado). |
| 2 Álbum | `waha_album` | o cabeçalho vira atividade escondida; as fotos seguem como mensagens e o painel as agrupa. |
| 3/10 Localização | `waha_location` | anexo `location` + `shared_location {latitude, longitude, name?, address?, live?}`, `content` nil. Coordenada inválida: fica o texto. |
| 4 Contato | `waha_contacts` | os `.vcf` saem; um anexo `contact` por telefone (meta `firstName/lastName`) + `shared_contacts`. 1 telefone = cartão com "Adicionar contato". |
| 5 Citação | `waha_quote` | mesma conversa: `in_reply_to`; outra conversa: `quoted_message {message_id, conversation_id, content (280), sender_type, attachment_type}`; desconhecida: `quoted_message {message_id: nil, content, from_me, has_media}`. |
| 6 Mídia que falhou | `waha_media_failed` | mensagem do cliente VISÍVEL com a legenda ou "Foto não pôde ser baixada. Peça para o cliente reenviar." + `media_unavailable {kind, reason: download_failed, at}`. |
| 7 Apagada | `waha_revoke` | na original: `deleted_by_contact_at`, conteúdo intacto, sem `deleted`; a nota vira atividade escondida. Do celular da empresa: nota da main. |
| 8 Temporária | `waha_context.ephemeral_expiration` | uma atividade visível a cada mudança ("Mensagens temporárias ativadas (1 dia)…") com `waha_ephemeral`; a conversa guarda `c2y_ephemeral_expiration`. |
| 9 Figurinha | `waha_media.kind = sticker` | anexo `image` com `meta.is_sticker`, nome `sticker.webp`, `content` nil. |
| 11 Visualização única | `waha_media.view_once` ou `waha_unknown.content_type = viewOnceMessage` | mídia que chegou: `meta.is_view_once` (fica gravada e visível); não chegou: `is_unsupported` + `unsupported_kind: view_once`. |
| Encaminhada | `waha_context.forwarded/forwarding_score` | `forwarded: true`; `frequently_forwarded: true` com score ≥ 5. |
| Áudio ouvido | parâmetro `c2y_played_at` no PATCH de status | `played_at` (1ª vez), só do conector, em áudio nosso (`Waha::RichNative::PlayedReceipt`, after_action). |
| Pedido | `waha_order` | mensagem do cliente com `order {catalog_id: nil, text, items: [], order_id (sempre, texto), item_count, total_amount (texto "150.00"), currency, title}`. |

Ordem fixa no `Inbound`: absorventes (voto, resposta ao evento, reação, edição, apagada, ligação, álbum: a primeira
decide) → conteúdo (mídia que falhou, localização, contato, pedido, desconhecida) → mídia → citação → contexto. Erro
num passo não derruba os outros.

`SilentUpdate::SILENT_KEYS` ganhou `poll_votes`, `event_responses`, `deleted_by_contact_at`, `played_at`: a gravação na
mensagem não vai ao conector como pedido de reenvio.

## Envio

- **12 Botão de link**: `Waha::RichPayload` monta `sendLinkCustomPreview` `{text: "<corpo>\n\n<url>", preview: {url,
  title: header||label, description: footer||label, image: {url, mimetype: image/jpeg}}}`. Híbrido:
  `Waha::Client#send_link_custom_preview` (`POST /api/send/link-custom-preview`).
- **13 Convite de evento**: tipo novo `RichMessages::Types::Event` (flag; sem ela, tipo desconhecido como na main):
  corpo = nome (1–255), `start_at` ISO 8601 COM fuso e no futuro, `end_at?` depois do início, `location_name?`,
  `description?`. Cloud e fallback: texto `📅 nome / 🕐 data / 📍 local / descrição` (data no fuso que veio, sem nome
  de fuso) com a marca "Enviado como texto". Motor: `sendEvent` (`POST /api/{session}/events`), sem id gerado antes. O
  motor só conta `event` com `autonomia.event_response: true`. Respostas: caixa WAHA comum por `waha_event_response`;
  Híbrido pelo evento `event.response` (mesma assinatura do `poll.vote`, `EventResponseJob`). Ficam em
  `event_responses = [{sender_type: Contact, sender_id, response: going|not_going|maybe, extra_guests, at}]`. Bolha
  `types/Event.vue` (data no fuso da conta, local, contagem). Sem cancelar.

### Como o Agendamento usaria o convite

1. Ao confirmar a reunião (`Crm::BookingV2::InviteDeliverer` ou o aviso `Crm::MeetingNotice`), criar a mensagem com
   `content` = título da reunião e `content_attributes.rich_message = {type: 'event', start_at: meeting.starts_at
   (iso8601 com o offset do fuso da conta), end_at, location_name: endereço ou link, description}`. Sem a flag na conta,
   o tipo é recusado: mandar o texto de hoje.
2. Ouvir `message.updated` dessa mensagem e ler `event_responses`: `going` → reunião confirmada; `not_going` →
   recusada (avisar o responsável). `maybe` não muda o estado.
3. Remarcar ou cancelar: o WhatsApp não aceita pelo motor; mandar texto e, se remarcar, um convite novo.

## Desvios do contrato (com motivo)

1. **link_button sem `image_url` sai como texto** (o de hoje), e não `send_text` com `linkPreview`: o motor dá 500 sem
   imagem e o texto de hoje já leva o link, que o WhatsApp mostra com a prévia automática. O `image_url` não ganhou
   validação no tipo (para flag desligada continuar igual à main). Depois da revisão, só a CÓPIA da instalação vai ao
   motor (Waha::RichNative::PreviewImage, ver a seção da revisão); o endereço externo nunca.
2. **`selected_options` continua em STORED_KEYS** (chave antiga, segue barrada contra forja). `waha_unknown_type`
   também.
3. **Commits intermediários**: o initializer entrou no commit da base (`4049f086ea`) já registrando `PlayedReceipt` e
   `Context`, que só chegam nos commits seguintes. Só o HEAD sobe (sem push nesta rodada); os intermediários não
   carregam a app sozinhos. O 12 e o 13 ficaram em três commits por camada (envio, volta da resposta, bolha), porque
   dividem os mesmos arquivos.
4. **Specs da entrada** (`inbound_round2_spec.rb`) e as traduções entraram no último commit da série de entrada.

## Decisões do Rodrigo pendentes

- (a) A IA não recebe mais o voto da enquete nem a resposta do evento como mensagem do cliente (viram atividade
  escondida + dado agregado). Aceitar, ou definir outro sinal para o robô.
- (b) Nova tentativa de download no conector (lado do conector).
- (c) `image_url` opcional no link_button (feito como opcional, ver desvio 1).
- (d) `.vcf` do contato sai (fica `shared_contacts`); mantê-lo quebra o cartão.
- (e) A IA deve ignorar mensagem com `deleted_by_contact_at`? Hoje ela continua lendo o conteúdo.
- (f) Patch no motor para a visualização única (lado do conector).

## Item 11 — evidência

Ainda sem evidência de aparelho: a verificação no canário (linha `Undecryptable message … content lost` no log do
motor) é do lado do conector, passo 5 da ordem. O chat2you já trata os dois casos.

## Riscos

- AgentBot (n8n) recebe `message_updated` a cada reação, voto, resposta, apagada e áudio ouvido.
- Reação `User` com `sender_id` nulo (celular da empresa): a tela precisa tratar.
- `ringing`, `ended`, voto retirado como `options: []` e o formato de `order`: combinar com o Max.
- Ligar a flag numa conta Híbrida: a sessão que já tem `poll.vote` só ganha `event.response` pela assinatura agendada
  (`rake whatsapp_hybrid:poll_vote:subscribe`, um reinício por sessão, numa janela combinada). As outras sincronizações
  não reiniciam mais por isso (revisão, achado 7).
- Sem id pré-gerado, reenvio manual de link_button/evento pode duplicar.

## Validação no M4 (só specs focados, `: > log/test.log` antes e depois)

- RSpec: `spec/services/waha`, `spec/services/rich_messages`, `spec/services/whatsapp_hybrid/rich_native*`,
  `spec/requests/api/v1/accounts/{conversation_rich_native,waha_message_actions,waha_rich_native_forgery,waha_played_receipt}_spec.rb`:
  709 exemplos, 0 falhas, 14 pendentes (renderer do #1740, já pendentes antes).
- RuboCop (executável da gem) nos arquivos tocados: sem ofensas.
- Vitest (TZ=UTC) `components-next/message`: 183 testes, 0 falhas. ESLint: limpo.
- `i18n:fork:check`: ok. `autonomia:guia:formatos:check`: em dia. `guia:check`: em dia.
- Suíte ampla, build e snapshot: no M2, depois (passo 7 da ordem).

## Revisão independente da rodada 2 — o que mudou

Cada achado, a correção e onde está o spec (`spec/services/waha/rich_native/round2_review_spec.rb`, salvo indicação).

| # | Achado | Correção |
|---|---|---|
| 1 | Localização com `content` nil chega vazia à IA Autonomia | `Waha::RichNative::AiLocationText` + prepend `ResponderLocation` no histórico e na pergunta: "Localização compartilhada pelo cliente: <nome, endereço>. Mapa: <link das coordenadas>" (ao vivo: avisa que é só o ponto inicial). Só caixa WAHA comum com a flag. AgentBot (n8n): recebe `content` nil + `shared_location` + anexo `location`, o MESMO contrato da Cloud oficial hoje — não mudei o payload dele. |
| 2, 16 | `AttachmentMeta` mudava o JSON de todo áudio gravado pelo painel, em qualquer canal | Marcas só em anexo de mensagem da caixa WAHA comum com a flag. Spec: Cloud com flag e WAHA sem flag mantêm o JSON da main. |
| 3 | `STORED_KEYS` de nome genérico apagadas em qualquer caixa | `INTERNAL_KEYS` (`c2y_hidden`, `waha_*`, `*_applied_to`) saem em toda caixa; `SCOPED_KEYS` (`reactions`, `forwarded`, `quoted_message`…) só na WAHA comum e na do WhatsApp (Híbrido). Vale no modelo e no controller. |
| 4, 9 | `Context.after_commit` sem rescue: 500 ao conector e mensagem duplicada | `rescue StandardError` (log só da classe), atividade com `save!(validate: false)`, conversa com `save!(validate: false)`. Não virou job: com o rescue, a ordem dos after_commit deixa de importar (nada sobe). |
| 5 | `PlayedReceipt` sem rescue | `rescue` em `record!` e no after_action; o PATCH responde como na main. |
| 6, 11 | Citação podia apontar ou copiar nota privada | `.where(private: false)` no alvo; sem alvo público, cai no trecho do aparelho. |
| 8 | `waha_media_failed`/`waha_order` sem `from_me`: a nota do celular da empresa virava mensagem do cliente | Guarda `from_me == false` explícito nos dois; `true` ou ausente (conector antigo) fica como a main. Conector c2y-rich-3b manda `from_me` boolean sempre. **Verificação final:** a guarda `message.incoming?` desta rodada estava errada — toda nota privada do conector sai OUTGOING, inclusive a do cliente (`base.ts`, "Private notes can only be sent as outgoing messages", igual na tag limpa), então ela desligava a mídia sem legenda e o pedido. Specs com a forma real (nota OUTGOING privada + `from_me`). |
| 10 | `processed_message_content` com o texto do conector (link do job) | `Inbound` recalcula pela regra do modelo depois de transformar (e no rescue). Spec: `webhook_data` da mídia que falhou sem o link. |
| 12 | Voto, resposta e reação pela ordem de chegada | `Waha::RichNative::EventTime`: `at` = hora do WhatsApp (voto em s, resposta em ms); a entrada do mesmo autor só é trocada por outra igual ou mais nova. Híbrido passa `timestamp` do `poll.vote` e `timestampMs` do `event.response`. Reação: o conector c2y-rich-3 ainda não manda a hora; o chat2you já lê `waha_reaction.timestamp` quando vier (pedido ao construtor do conector). |
| 13 | `waha_call_summary.at` = hora do processamento, e cada desfecho o trocava | `at` = hora do primeiro evento da ligação (`timestamp` do conector quando vier, senão a chegada); o desfecho mantém o `at` da linha. O conector ainda não manda `timestamp` em `waha_call` (pedido ao construtor). |
| 14 | Chaves gravadas sem tela que as leia; apagada piorava | A nota da main da apagada CONTINUA visível (só ganha `revoke_applied_to`); a original ganha `deleted_by_contact_at`. **Dependência de deploy: não ligar a flag em conta nenhuma antes do PR #1724 (Frontend geral, #1702) no ar, com cada chave conferida.** Depois dele, a nota passa a atividade escondida em PR próprio. |
| 15 | SSRF pelo `image_url` do link_button | `Waha::RichNative::PreviewImage` (before_create, `prepend: true`, antes da decisão de envio): com a flag, na WAHA comum ou na do WhatsApp, baixa pelo SafeFetch (rede privada recusada a cada salto, só https, 5 MB, 5 s, só PNG/JPEG/WebP) e troca o `image_url` pelo endereço público da cópia (FRONTEND_URL). O `Waha::RichPayload` só monta o cartão com a cópia DESTA conta e manda o content-type real dela. Falhou o download: o campo sai e vai o texto. Custo: o download roda dentro da transação da criação (até 5 s), só para link_button com imagem. |
| 17 | Trecho citado sem alvo podia ser forjado (from_me) | `quoted_message.unverified: true`. Combinar com o Max: a bolha mostra "trecho enviado pelo aparelho do cliente, não conferido" e nunca atribui à empresa pelo `from_me`. A IA Autonomia não lê `quoted_message` hoje. |
| 18 | Em grupo, todos os participantes eram o mesmo eleitor | Enquete e evento nunca saem nativos em conversa de grupo (contato com identificador `@g.us`, que é como o conector cria o grupo); voto ou resposta que chegue em grupo fica como o texto do conector, visível. |
| 19 | O robô perde o sinal do voto e da resposta | **Não mudei o código: é a decisão (a), pendente do Rodrigo e BLOQUEANTE do merge.** O `message_updated` da enquete vai ao AgentBot com `event: 'message_updated'` (agent_bot_listener.rb:46-54), não como mensagem nova; fluxo n8n que não filtra o evento reprocessa. |
| 20 | Aviso para a equipe com voz de comando no `content` do cliente | Texto neutro: "Foto não recebida (o download falhou)" (en/pt_BR). O aviso "peça para reenviar" fica com a bolha (`media_unavailable`). |
| 21 | I18n sem `default:` no aviso de temporárias | `default:` no idioma padrão, também em horas e dias. |
| 22 | Chaves i18n mortas; data do evento no fuso do offset | `waha.event.cloud_when/cloud_where` removidas. `PollGate#build` passa o fuso da conta (Crm::Timezone::Resolver) ao tipo `event`. As mensagens de erro do tipo continuam no código, em português, como as dos outros tipos (resposta 422 da API, não texto de tela) — recusado com esse motivo. |
| 23 | Event.vue sem `aria-live` e ícones lidos | `aria-live="polite"` nas respostas; ícones dentro de `span aria-hidden` (o `Icon` é funcional e não repassa `aria-hidden`). Spec no Event.spec.js. |
| 24 | `from_connector?` com fallback para administrador | **Não mudei: o backfill do `account_token_owner_user_id` é escrita em banco de produção (exige OK do Rodrigo).** Plano: backfill de todas as caixas WAHA, conferir, e em PR seguinte tirar o fallback. Até lá, um administrador pode forjar `waha_revoke`/`waha_quote`/`waha_media_failed`/`c2y_played_at` pela API. |
| 7 | Reinício de toda sessão híbrida depois do deploy | `event.response` só é exigido na assinatura agendada (`subscribe_poll_vote!`). |

### Validação da revisão (M4, specs focados, `: > log/test.log` antes e depois)

- Commits: `cbc6b82f29` (recebimento e envios), `1f43c98795` (bolha do evento).
- RSpec: `spec/services/{rich_messages,waha}`, `spec/services/whatsapp_hybrid/rich_native*`, os 4 request specs da
  rodada, `responder_spec`, `responder_pessoa_da_equipe_historico_spec`, `responder_eco_do_celular_spec`,
  `responder_regra_do_turno_spec`: 797 exemplos, 0 falhas, 14 pendentes (renderer do #1740, já pendentes antes).
  `formatos_spec` do Guia: 23 exemplos, 0 falhas.
- RuboCop nos 38 arquivos Ruby tocados: sem ofensas. ESLint: 0 erros (4 avisos `RICH_MESSAGE` já existentes, os
  mesmos do Poll.vue). Vitest (TZ=UTC) `components-next/message`: 184 testes, 0 falhas. `i18n:fork:check`: ok.

### Pendências que não são deste lado

- Prévia de link (`linkPreview`) na caixa WAHA: operação separada, com o OK do Rodrigo, depois de confirmar no código
  do GOWS como o motor busca a página (rede, proxy, bloqueio de IP privado). Fora deste PR.

- Construtor do conector: `timestamp` em `waha_reaction` e `waha_call` (o `from_me` em `WahaMediaFailedOf`/`WahaOrderOf` entrou na c2y-rich-3b, sincronizada em `infra/waha-c2y/`).
- Rodrigo: decisões (a) a (f) e o backfill do achado 24.
- Max (#1724): `quoted_message.unverified`, selo da apagada, aviso da localização ao vivo, `media_unavailable`.

## Ajuste final combinado com o Frontend geral (#1702)

- `order.items` (não `product_items`); `order_id` sempre em texto; `total_amount` em texto decimal com ponto e 2 casas.
- `media_unavailable.has_caption` (true/false); sem legenda, o `content` é o aviso do servidor.
- Áudio que é arquivo (não PTT): `meta.is_voice_message: false`, só com a flag e na caixa WAHA.
- `shared_contacts[].wa_id` só com dígitos (sem `@c.us`/`@lid` e sem `:<aparelho>`); `shared_location.live` só `true`
  ou ausente; `quoted_message.sender_type` 'Contact' (cliente) ou 'User' (empresa, inclusive robô e automação).
- Citação: `in_reply_to` = id local quando a citada está na conversa; senão `quoted_message` com o conteúdo.
- Prévia de link na caixa WAHA: NÃO entra neste PR (o provisioner fica com `linkPreview: 'OFF'`, como na main). Ligar
  muda toda caixa nova mesmo com a flag desligada e, com HQ, o motor busca a página de todo link que sai no texto,
  possivelmente fora do proxy e alcançando endereço interno da rede do servidor (risco de SSRF se o robô repetir um link
  do cliente). Vira operação separada, com o OK do Rodrigo, depois de confirmar no código do GOWS como ele busca a
  prévia (rede, proxy, bloqueio de IP privado).
- `shared_contacts[].wa_id` com `@lid` fica nil: o LID não é telefone.
- `order.total_amount`: o sinal sai do valor já arredondado (nunca "-0.00"); meio centavo arredonda para cima
  (1.005 → "1.01"); texto numérico vale; o que não é número fica nil.
- Exceção do `Waha::RichNative::SilentUpdate`: vale também com a flag DESLIGADA. As 9 chaves (reactions,
  read_receipt_sent_at, link_preview, played_at, deleted_by_contact_at, poll_votes, event_responses, edit_history,
  edited_at) não vão ao webhook da caixa WAHA em `message_updated`, porque o conector reenviaria a mensagem (ele lê todo
  `message_updated` com `external_error`, mesmo nulo, como pedido de reenvio) e ninguém na main grava essas chaves.

## Decisões aprovadas pelo Rodrigo (16/10/2026) — agente de IA

- Voto na enquete e resposta ao convite são TURNO DO CLIENTE para a IA (`Waha::RichNative::AiTurn`): com a flag, a
  mensagem do voto (ou da resposta) fica RECEBIDA, com texto claro no idioma da conta ("Votou na enquete 'Qual
  horário?': Tarde"; "Respondeu ao convite 'Visita técnica': Vou") e `c2y_hidden: true` (a tela esconde; o voto segue
  agregado em `poll_votes`/`event_responses`). Segue o caminho normal da mensagem do cliente (debounce, posse do turno,
  espera do assunto); voto trocado dentro do debounce responde só à última escolha. Voto retirado ou antigo continua
  atividade escondida. No Híbrido, a janela da Cloud não abre por ele (`c2y_window_neutral`). Sem a flag, igual à main.
- A IA fica calada diante da bolha "abra no celular" (`is_unsupported`) na caixa WAHA com a flag, com o evento
  `skipped_mensagem_sem_suporte` (valor 15 do enum, pulando 10 a 14 de outros PRs; conta como não atendimento).
- A IA não responde mensagem apagada pelo cliente (`deleted_by_contact_at`) e ela sai do histórico que vai à IA
  (`Waha::RichNative::AgentTurnGuard`).
- Edição só pelo autor ou administrador: já coberta (spec de ações de mensagem). Contato só como cartão: já coberto
  (o .vcf sai). Nova tentativa de download: sem mudança.
