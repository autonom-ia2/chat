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
| 1 Voz (PTT) | `waha_media.kind = voice` | `attachments[].meta.is_voice_message`; nome `no-filename.*` → `audio-<AAAAMMDD-HHMMSS no fuso da conta>.ogg` (blob renomeado antes do upload, testado). |
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
| Pedido | `waha_order` | mensagem do cliente com `order {catalog_id: nil, text, product_items: [], order_id, item_count, total_amount, currency, title}`. |

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
   validação no tipo (para flag desligada continuar igual à main): só é usado se for https e até 2000 caracteres;
   senão, sai texto.
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
- Ligar a flag numa conta Híbrida reinicia cada sessão mais uma vez (assinatura nova com `event.response`).
- Sem id pré-gerado, reenvio manual de link_button/evento pode duplicar.

## Validação no M4 (só specs focados, `: > log/test.log` antes e depois)

- RSpec: `spec/services/waha`, `spec/services/rich_messages`, `spec/services/whatsapp_hybrid/rich_native*`,
  `spec/requests/api/v1/accounts/{conversation_rich_native,waha_message_actions,waha_rich_native_forgery,waha_played_receipt}_spec.rb`:
  709 exemplos, 0 falhas, 14 pendentes (renderer do #1740, já pendentes antes).
- RuboCop (executável da gem) nos arquivos tocados: sem ofensas.
- Vitest (TZ=UTC) `components-next/message`: 183 testes, 0 falhas. ESLint: limpo.
- `i18n:fork:check`: ok. `autonomia:guia:formatos:check`: em dia. `guia:check`: em dia.
- Suíte ampla, build e snapshot: no M2, depois (passo 7 da ordem).
