# Matriz de envio e recebimento do WhatsApp (#1733)

17/10/2026. Parte do #1702. Leitura do código da branch `feat/1702c-ajustes-teste-prod` (HEAD `9bcde96fb5`), mais a
Issue #1733, o PR aberto #1741 (ricas nativas no WAHA, branch `feat/1709-ricas-waha`) e o documento
`docs/waha-customizado-lista-completa.md` daquela branch. **Nada aqui foi testado de verdade além do que a seção 6 diz.**
Cada célula é o que o código faz hoje, com o arquivo e a linha; a coluna "Falta testar" é o teste real que ainda falta.

## Como ler

**Caixas**

- **Cloud**: `Channel::Whatsapp` com `provider: 'whatsapp_cloud'` (API oficial da Meta).
- **360dialog**: `Channel::Whatsapp` com `provider: 'default'`. O envio aponta para `https://waba.360dialog.io/v1`
  (`app/services/whatsapp/providers/whatsapp_360_dialog_service.rb:55-58`), o formato On-Premises.
- **WAHA**: caixa `Channel::Api` com `additional_attributes.provider = 'waha'` (`app/services/waha/inbox_provisioner.rb:74-89`).
  Quem manda e recebe é o **conector Chatwoot embutido no WAHA** (`app: 'chatwoot'`, `inbox_provisioner.rb:104-135`),
  que não está neste repositório. O nosso código só alcança: o webhook da caixa (`RichMessages::ApiInboxWebhook`),
  a reação (`ConversaCanal::ReacaoNoWaha`) e a lida (`ConversaCanal::LeituraNoCanal`).
- **Híbrida**: caixa Cloud com `WhatsappHybrid::Connection`. Recebe **tudo pela Cloud**: o webhook do WAHA só traz
  estado da sessão e confirmação de entrega (`app/controllers/webhooks/whatsapp_hybrid_controller.rb:1-4`,
  `app/jobs/whatsapp_hybrid/webhook_event_job.rb:11-34`). Dentro das 24 h envia pela Cloud; fora delas, texto e anexo
  pela sessão WAHA auxiliar (`app/services/whatsapp_hybrid/router.rb:17-22`, `send_on_whatsapp_extension.rb:7-17`).

**Janela**

- Recebimento não depende da janela: a mensagem do cliente é que abre ou renova as 24 h. Por isso há uma coluna só de
  "Recebe" por caixa.
- Cloud e 360dialog: janela de 24 h (`app/services/conversations/message_window_service.rb:27-28`). Fora dela só sai
  modelo; o resto falha com "fora da janela" (`app/services/whatsapp/send_on_whatsapp_service.rb:11-19`).
- WAHA: sem janela. `Channel::Api` só tem janela se `agent_reply_time_window` estiver preenchido
  (`message_window_service.rb:40-44`), e o provisionamento não preenche. Dentro = fora.
- Híbrida fora das 24 h: só `content_type == 'text'` (com ou sem anexo), origem ligada e tipo rico com versão em texto
  (`router.rb:41-45`). Modelo e pedido de dados de contato vão sempre pela Cloud (`send_on_whatsapp_extension.rb:19-23`).

**Legenda das células**

| Código | Quer dizer |
|---|---|
| S | Suportado no código |
| S\* | Suportado só com a chave `conversa_cara_do_canal` ligada na conta (a "pele") |
| T | Sai como texto (versão em texto do tipo, `RichMessages::OutgoingText`) |
| X | Recusado ou falha com motivo na tela |
| N | Não existe no nosso código, mas a plataforma permitiria |
| L | Limite da plataforma (a API não oferece) |
| E | Depende do conector WAHA (fora do repositório); em parênteses, o que o documento do #1709 diz que ele faz hoje |
| P | Pendente: código pronto em PR aberto, ainda não está nesta branch |
| — | Não se aplica |

## 1. Grade-resumo

Rec = recebe; ≤24 = envia com a janela aberta; >24 = envia com a janela fechada.

| Tipo | Cloud Rec | Cloud ≤24 | Cloud >24 | 360 Rec | 360 ≤24 | 360 >24 | WAHA Rec | WAHA envia | Híb Rec | Híb ≤24 | Híb >24 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Texto | S | S | X | S | S | X | E (sim) | E (sim) | S | S | S |
| Foto | S | S | X | S | S | X | E (sim) | E (JPG/PNG) | S | S | S |
| Vídeo | S | S | X | S | S | X | E (sim) | E (MP4) | S | S | S |
| Áudio / voz | S (voz: S\*) | S | X | S | S (sem voz) | X | E (sem marca de voz) | E (voz) | S (voz: S\*) | S | S (sempre voz) |
| Documento | S | S | X | S | S | X | E (sim) | E (sim) | S | S | S |
| Figurinha | S\* | N | X | S\* | N | X | E (vira imagem) | E (vira arquivo/imagem) | S\* | N | N |
| Contato | S | S\* | X | S | T | X | E (texto + .vcf) | T (P: nativo) | S | S\* | T |
| Localização | S | S\* | X | S | T | X | E (texto com link) | T (P: nativo) | S | S\* | T |
| Pedido de localização | — | S\* | X | — | T | X | — | T | — | S\* | T |
| Opções / botões | S | S | X | S | S (antigo) / T (+) | X | E (só texto) | T (P: lista) | S | S | T (+) / X (antigo) |
| Lista | S | S | X | S | S (antigo) / T (+) | X | E (só texto) | T (P: lista) | S | S | T (+) / X (antigo) |
| Modelo | — | S | S | — | S | S | — | L | — | S | S (pela Cloud) |
| Carrossel (modelo) | — | S | S | — | ? | ? | — | L | — | S | S (pela Cloud) |
| Produto | S\* (pedido) | S (modelo) / N (interativo) | S (modelo) | S\* (pedido) | ? | ? | E (resumo) | L | S\* (pedido) | S (modelo) | S (modelo, pela Cloud) |
| Enquete | L (não suportada) | L | L | L | L | L | E (P) | P | L | L | L |
| Reação | S\* | S\* | X | S\* | X | X | E (bolha nova) | S\* | S\* | S\* | X |
| Citação | S | S (não no antigo) | X | S | N | X | E (vínculo some) | E (sim) | S | S | N |
| Encaminhada | S\* | S\* (só painel) | X | S\* | S\* (só painel) | X | E | S\* (só painel) | S\* | S\* (só painel) | S\* (só painel) |
| Editada | S\* | L | L | S\* | L | L | E (duas versões) | N | S\* | L | N |
| Apagada | S\* | L | L | S\* | L | L | E (nota privada) | E (sim) | S\* | L | N |
| Visualização única | L | L | L | L | L | L | E (não se sabe) | L | L | L | L |
| Álbum | S\* (agrupa na tela) | S (uma por foto) | X | S\* | S (uma por foto) | X | E (bolha extra) | E (uma mensagem com N anexos) | S\* | S | S (uma por foto) |

"Antigo" = `input_select` do Chatwoot; "+" = opções do "+" da pele (`rich_message.type = 'options'`).
"?" = o código monta, mas ninguém sabe se o 360dialog On-Premises aceita (ver buraco B1).

## 2. Detalhe por tipo

Arquivos citados sem pasta: `cloud` = `app/services/whatsapp/providers/whatsapp_cloud_service.rb`;
`360` = `app/services/whatsapp/providers/whatsapp_360_dialog_service.rb`; `base` =
`app/services/whatsapp/incoming_message_base_service.rb`; `helpers` = `app/services/whatsapp/incoming_message_service_helpers.rb`;
`rich` = `app/services/rich_messages.rb`; `wt` = `app/services/whatsapp_hybrid/web_transport.rb`;
`envio` = `app/services/whatsapp/send_on_whatsapp_service.rb`.

### Texto

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S | X | rec: `helpers:31`; envio: `cloud:161-175`; com endereço e a pele, `preview_url` (`app/services/conversa_canal/previa_de_link_no_envio.rb:12-35`); fora: `envio:17-19` | texto longo (4096), emoji, quebra de linha, link com prévia |
| 360dialog | S | S | X | rec: `helpers:31` pelo `Whatsapp::IncomingMessageService` (`app/jobs/webhooks/whatsapp_events_job.rb:148-154`); envio: `360:60-72` | tudo: não há registro de envio real nesta frente (ver B1) |
| WAHA | E | E | E | o painel cria a mensagem; o conector WAHA a entrega pelo webhook da caixa | texto, emoji, formatação (PR #1740 traz a tabela do que sai) |
| Híbrida | S | S | S | ≤24: Cloud; >24: `wt:120-122` (`sendText`), com "digitando" (`app/services/whatsapp_hybrid/typing.rb:28-34`) | >24 com a sessão conectada e com ela caída (falha "desconectado", `wt:51`) |

### Foto

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S | X | rec: `base:187-205`, legenda em `content` (`base:191`); envio: `cloud:177-195`, sobe a mídia e manda por id (`cloud:221-228`), legenda (`cloud:224`) | foto com legenda; PNG, JPG, HEIC e WebP (WebP vai como `image`: a Meta só documenta JPEG/PNG para imagem) |
| 360dialog | S | S | X | rec: `base:187-205` com `helpers:2-4`; envio por link público (`360:74-94`) | o link do ActiveStorage precisa ser alcançável pelo 360dialog |
| WAHA | E | E | E | documento do #1709: hoje só JPG e PNG saem como foto; o resto chega como arquivo | foto em formato fora de JPG/PNG |
| Híbrida | S | S | S | >24: `sendImage` (`wt:16`, `wt:124-127`) com legenda | >24 com legenda; a tela da pele esconde "Fotos e vídeos" no número reserva (ver B3) |

### Vídeo

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S | X | rec: `base:187-205` (`helpers:48`); envio: `cloud:180` (`video`) | MP4 grande (limite da Meta 16 MB), MOV, vídeo com legenda |
| 360dialog | S | S | X | `360:74-94` | idem |
| WAHA | E | E | E | documento do #1709: só MP4 toca na conversa | MOV e 3GP |
| Híbrida | S | S | S | >24: `sendVideo` (`wt:16`) | >24 com MP4 e com MOV |

### Áudio / voz

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S; voz S\* | S | X | rec: `helpers:47`; `audio.voice` vira `meta.is_voice_message` com a pele (`app/services/conversa_canal/audio_de_voz_recebido.rb:13-23`); envio: `voice: true` só se a marca existir e o arquivo for `audio/ogg` (`cloud:202-204`, `cloud:226`), marca gravada pelo gravador (`app/builders/messages/message_builder.rb:75-77`); `audio/opus` vira `audio/ogg` (`cloud:210-219`) | nota de voz gravada no painel chega como voz (onda) no app; MP3 chega como arquivo de áudio; "ouvido" (`played`, `conversa_canal/recebimento_do_whatsapp.rb:58-62`) |
| 360dialog | S | S (sem voz) | X | envio sem `voice` (`360:74-94`); recebimento pelo mesmo serviço, mas o On-Premises pode não mandar `audio.voice` | nota de voz do painel no app; a marca `voice` no recebimento |
| WAHA | E | E | E | documento do #1709: hoje chega como arquivo "no-filename", sem marca de voz; sai como voz | gravação do painel e áudio recebido |
| Híbrida | S; voz S\* | S | S | >24: todo áudio vai por `sendVoice` (`wt:16`), inclusive MP3 que era arquivo | >24 com MP3: chega como voz ou falha? (ver B5); a tela tira o microfone no número reserva (`ReplyBottomPanel.vue:203-213`) |

### Documento

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S | X | rec: `helpers:52` (`file`), nome original preservado (`app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:23-27`); envio: `document` com `filename` e legenda (`cloud:180`, `cloud:224-225`); "Documento" do "+" manda foto/vídeo como documento (`app/services/conversa_canal/como_documento.rb:7-16`, `message_builder.rb:61`) | PDF com legenda; nome com acento. Foto e vídeo como documento: **testado** (seção 6) |
| 360dialog | S | S | X | `360:76-81` (`document` + `filename`) | foto como documento (`document_indexes`) |
| WAHA | E | E | E | `ComoDocumento` também vale na caixa WAHA (`como_documento.rb:14-16`): o anexo vai como `file`; o resto é do conector | foto como documento chega como arquivo? |
| Híbrida | S | S | S | >24: `sendFile` (`wt:124`), `filename` e `mimetype` (`wt:125`) | >24 com PDF; a tela esconde "Documento" no número reserva (B3) |

### Figurinha

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* | N | X | rec: `sticker` vira `image` (`helpers:46`) com `meta.is_sticker` (`app/services/conversa_canal/figurinha_recebida.rb:12-18`); envio: nenhum caminho manda `type: 'sticker'` (`cloud:180`): um `.webp` sai como `image` | figurinha recebida (estática e animada); o que a Meta faz com WebP mandado como `image` |
| 360dialog | S\* | N | X | mesmo recebimento; envio `360:76` | idem |
| WAHA | E | E | E | `figurinha_recebida.rb:4-5`: o conector entrega só o `.webp`, sem dizer que era figurinha | — |
| Híbrida | S\* | N | N | recebe pela Cloud; envio idem Cloud e WAHA | — |

### Contato

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S\* | X | rec: `app/services/whatsapp/incoming_contact_message_handler.rb:2-10`, um anexo por telefone (`:25-43`); envio: "+" → `rich_message` `contact` (`app/services/rich_messages/types/contact.rb:38-43`) por `app/services/rich_messages/whatsapp_cloud_delivery.rb:7-29`; corpo junto é recusado (`rich.rb:29-30`) | cartão chega com nome e botão "Conversar"; contato com dois telefones recebido |
| 360dialog | S | T | X | `rich.rb:42-43`: só a Cloud manda o formato; o 360dialog recebe `Nome: +55…` (`contact.rb:46-48`) | — |
| WAHA | E | T | T | texto pelo webhook da caixa (`app/services/rich_messages/api_inbox_webhook.rb:32-38`); nativo no PR #1741 (`send_contact_vcard`) | depois do #1741: cartão nativo |
| Híbrida | S | S\* | T | >24: `RichMessages.text_capable?` (`router.rb:44`) → texto e marca "Enviado como texto" (`wt:93`) | >24 chega como texto e a bolha mostra a marca |

### Localização

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S\* | X | rec: anexo `location` (`base:207-218`) e `shared_location` estruturado (`app/services/rich_messages/received_location.rb:21-31`); envio: `type: 'location'` (`app/services/rich_messages/types/location.rb:46-51`) | localização fixa e localização ao vivo recebidas; envio com nome e endereço |
| 360dialog | S | T | X | texto nome, endereço e link do Maps (`location.rb:54-56`) | — |
| WAHA | E | T | T | documento do #1709: chega como texto com link; nativo no PR #1741 | depois do #1741: mapa nativo |
| Híbrida | S | S\* | T | >24 texto (`router.rb:44`) | — |

### Pedido de localização

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | — | S\* | X | `interactive.location_request_message` (`app/services/rich_messages/types/location_request.rb:21-24`); a resposta do cliente volta como localização com `in_reply_to` (`received_location.rb:1-7`) | botão "Enviar localização" no app; resposta liga à pergunta |
| 360dialog | — | T | X | versão em texto = só o corpo (`location_request.rb:29-31`) | — |
| WAHA | — | T | T | idem, pelo webhook da caixa | — |
| Híbrida | — | S\* | T | >24 só o corpo | — |

### Opções / botões (até 3, sem descrição)

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S | X | rec: título em `content` (`helpers:33-34`) e `selected_option` (`app/services/rich_messages/selected_option.rb:13-19`); envio "+": `interactive.button` (`app/services/rich_messages/types/options.rb:69-73`, `:116`); envio antigo `input_select`: `cloud:276-291` | toque no botão volta ligado à pergunta |
| 360dialog | S | S (antigo) / T (+) | X | antigo: `360:113-127`; "+": texto numerado (`options.rb:84-90`) | — |
| WAHA | E | T | T | documento do #1709: hoje só o texto da opção; PR #1741: sempre lista (o motor GOWS não tem botão) | depois do #1741: lista nativa e `selected_option` |
| Híbrida | S | S | T / X | >24 "+" vira texto; `input_select` não é `text` e falha (`router.rb:44`, `send_on_whatsapp_extension.rb:14`) | — |

### Lista (mais de 3 opções, ou com descrição, ou com seções)

Igual a Opções, com `list` em vez de `button` (`options.rb:108`, `base_service.rb:113-115` para o antigo). Limites da
Meta conferidos no tipo: 10 opções, 10 seções, título de seção 24, descrição 72, botão 20 (`options.rb:16-22`).
**Falta testar:** lista com seções no app; lista com 10 opções; descrição longa.

### Modelo

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | — | S | S | `envio:11-14` (modelo vem antes da janela); `cloud:39-58`; componentes novos (oferta, carrossel, formulário, catálogo) em `app/services/whatsapp/templates/send_components.rb:1-10`; resposta ao botão rápido = `button` (`helpers:32`, `selected_option.rb:17-18`) | modelo com cabeçalho de imagem, botão de link, botão rápido |
| 360dialog | — | S | S | `360:13-25`, com `namespace` (`360:101-111`) | modelo simples |
| WAHA | — | L | L | o WhatsApp Web não tem modelo; o conector nasce com `templates: {}` (`inbox_provisioner.rb:127`) | — |
| Híbrida | — | S | S | sempre pela Cloud (`send_on_whatsapp_extension.rb:19-23`) | — |

### Carrossel

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | — | S | S | só como modelo: `app/services/whatsapp/templates/send_params.rb:64-76`, mídia dos cartões em `card_media.rb`; a tela mostra pelo `enviado/cartoes.rb`. Carrossel interativo fora de modelo: N (a Meta lançou em 2025; a confirmar na doc) | carrossel de mídia com 2 e 10 cartões; toque em botão rápido de cartão |
| 360dialog | — | ? | ? | o mesmo `TemplateProcessorService` monta, e o `360:13-25` envia; não se sabe se o On-Premises aceita carrossel | — |
| WAHA | — | L | L | sem modelo | — |
| Híbrida | — | S | S | pela Cloud | — |

### Produto

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* (pedido) | S (modelo) / N (interativo) | S (modelo) | rec: `order` vira resumo e `content_attributes.order` com a pele (`app/services/conversa_canal/recebimento_do_whatsapp.rb:35-56`, `pedido_recebido.rb`); envio: um produto, vários e carrossel de produtos só como modelo (`app/services/whatsapp/templates/product_params.rb:1-7`, `dispatch_products.rb`); mensagem interativa `product`/`product_list` fora de modelo não existe | pedido do carrinho recebido (com e sem a pele, ver B6) |
| 360dialog | S\* (pedido) | ? | ? | mesmo recebimento; modelo de catálogo no On-Premises: desconhecido | — |
| WAHA | E | L | L | `pedido/pedido.js:5-6`: o conector manda só o resumo (`orderId`, `itemCount`, `totalAmount`) | — |
| Híbrida | S\* (pedido) | S | S | pela Cloud | — |

### Enquete

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | L | L | L | a Cloud API não manda nem entrega enquete: chega `unsupported` com `unsupported.type = poll_creation`, que vira `unsupported_kind: 'poll'` com a pele (`app/services/conversa_canal/tipo_nao_suportado.rb:12-18`) | enquete recebida mostra "abra no celular" |
| 360dialog | L | L | L | idem | — |
| WAHA | E (P) | P | P | a tela já desenha `rich_message.type = 'poll'` com `poll_votes` (`enquete/enquete.js:1-6`); quem grava é o conector customizado (`infra/waha-c2y`, PR #1741, documento do #1709: "Testado: chega e volta") | depois do motor customizado: enquete recebida, voto, troca de voto |
| Híbrida | L | L | L | recebe pela Cloud | — |

### Reação

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* | S\* | X | rec: sem a pele o Chatwoot descarta (`base:36-38`); com a pele vira o selo (`app/services/whatsapp/incoming_reaction_extension.rb:11-21`); envio: `app/services/conversa_canal/reacao_na_cloud.rb:18-22` (só em recebida, só com a janela), corpo `:51-59` | reagir, trocar e tirar (emoji vazio); reação a mensagem de 30 dias (erro 131009 chega depois, pelo webhook) |
| 360dialog | S\* | X | X | rec: mesmo serviço; envio: o atendente recebe "caixa sem reação" (`app/services/conversa_canal/reacao_do_atendente.rb:65-81`) | reação recebida no formato On-Premises |
| WAHA | E | S\* | S\* | rec: documento do #1709, hoje vira bolha nova "Reagiu com 👍"; envio: `PUT /api/reaction` sem janela, recebida ou enviada (`app/services/conversa_canal/reacao_no_waha.rb:15-26`, `:40-49`) | reagir a mensagem recebida e a enviada |
| Híbrida | S\* | S\* | X | `reacao_do_atendente.rb:75-77` trata como Cloud; fora da janela recusa, mesmo com o WAHA conectado (ver B9) | — |

### Citação (responder citando)

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S | S (não no antigo) | X | rec: `context.id` → `in_reply_to` (`helpers:83-91`); envio: `context` no texto (`cloud:167`), no anexo (`cloud:187`) e no rico (`whatsapp_cloud_delivery.rb:19`); `input_select` não leva `context` (`cloud:276-291`), nem o modelo (`cloud:42-49`) | citar foto e citar áudio; citar mensagem antiga (fora do histórico carregado) |
| 360dialog | S | N | X | nenhum envio do `360` monta `context` (`360:60-127`) | — |
| WAHA | E | E | E | documento do #1709: envio "Caixa comum: sim"; recebimento "o vínculo some sem aviso" | — |
| Híbrida | S | S | N | >24: `send_text`/`send_media` sem resposta (`wt:120-128`); documento do #1709: "Reserva do Híbrido: não" | — |

### Encaminhada

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* | S\* (só no painel) | X | rec: `context.forwarded` / `frequently_forwarded` (`recebimento_do_whatsapp.rb:68-73`); envio: cópia nova com `forwarded = true` só no nosso balão (`app/services/conversa_canal/encaminhamento.rb:1-15`); a Cloud API não marca "Encaminhada" no aparelho do cliente; destino fora da janela é recusado (`encaminhamento.rb:12-13`) | encaminhada e "encaminhada com frequência" recebidas; encaminhar foto, documento, localização, contato (`copia_encaminhada.rb:29-39`) |
| 360dialog | S\* | S\* (só no painel) | X | mesmo serviço, se o On-Premises mandar `context.forwarded` | — |
| WAHA | E | S\* (só no painel) | S\* | sem janela | — |
| Híbrida | S\* | S\* | S\* | `Conversation#can_reply?` conta o Híbrido (`app/services/whatsapp_hybrid/conversation_extension.rb:5-9`), então o destino fora das 24 h aceita e a cópia sai pelo WAHA | encaminhar para destino fora das 24 h numa caixa híbrida |

### Editada

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* | L | L | rec: `edit` só existe na coexistência e está "temporariamente" desligado pela Meta (`recebimento_do_whatsapp.rb:6-8`, `mudanca_na_original.rb:61-71`); fora da coexistência vem `unsupported` tipo `edit` (`tipo_nao_suportado.rb:17`); envio: a Cloud API não edita mensagem enviada (a confirmar na doc da Meta) | cliente edita numa caixa em coexistência |
| 360dialog | S\* | L | L | mesmo serviço | — |
| WAHA | E | N | N | documento do #1709: hoje aparecem as duas versões; editar "até ~15 min" é Pacote 2 | — |
| Híbrida | S\* | L | N | recebe pela Cloud | — |

### Apagada

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* | L | L | rec: `revoke` (coexistência) marca a original com `deleted_by_contact_at`, conteúdo fica (`mudanca_na_original.rb:54-59`); envio: apagar no painel não chega ao aparelho (a Cloud API não apaga mensagem enviada; a confirmar na doc) | cliente apaga numa caixa em coexistência |
| 360dialog | S\* | L | L | idem | — |
| WAHA | E | E | E | documento do #1709: recebimento vira nota privada; "apagar para todos" funciona na caixa comum | apagar pelo painel some do aparelho? |
| Híbrida | S\* | L | N | documento do #1709: "Reserva do Híbrido: não" | — |

### Visualização única

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | L | L | L | a Meta não entrega a mídia: chega `unsupported` sem tipo próprio (`app/services/conversa_canal/visualizacao_unica.rb:5-9`) | foto "ver uma vez" recebida vira "não suportada" |
| 360dialog | L | L | L | idem | — |
| WAHA | E | L | L | a marca `meta.is_view_once` (`visualizacao_unica_no_anexo.rb:5-11`) é gravada pelo conector do #1709; o documento do #1709 diz "testar antes de decidir"; o motor não envia | decisão do Rodrigo pendente |
| Híbrida | L | L | L | recebe pela Cloud | — |

### Álbum

| Caixa | Rec | ≤24 | >24 | Evidência | Falta testar |
|---|---|---|---|---|---|
| Cloud | S\* | S | X | rec: a Meta manda uma mensagem por foto; a tela junta 2 ou mais da mesma pessoa em até 30 s (`app/javascript/dashboard/components-next/conversa-canal/album/agruparAlbuns.js:1-5`, `:23-25`); envio: o painel parte em uma mensagem por anexo, legenda só na primeira (`app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:911-924`, `:1259-1284`); o provedor manda só `attachments.first` (`cloud:178`) | 4 fotos do painel viram álbum no app? |
| 360dialog | S\* | S | X | idem (`ReplyBox.vue:914`, `360:75`) | — |
| WAHA | E | E | E | `Channel::Api` não está na divisão (`ReplyBox.vue:911-914`): sai **uma** mensagem com N anexos para o conector; documento do #1709: recebe com "bolha extra sem conteúdo" | 3 fotos pelo painel numa caixa WAHA: quantas chegam? (B10) |
| Híbrida | S\* | S | S | >24: uma mensagem por foto, cada uma por `sendImage` | — |

## 3. As diferenças a mais (fora da lista da Issue)

| Recurso | Cloud | 360dialog | WAHA | Híbrida | Evidência | Falta testar |
|---|---|---|---|---|---|---|
| Formatação (`*negrito*`, `_itálico_`, `~riscado~`, mono) | S | S | E | S | texto puro; a conversão do editor e a tela estão no PR #1740 (aberto) | a tabela do PR #1740 no aparelho |
| Botão de link | S\* ≤24, X >24 | T | T | S\* ≤24, T >24 | `app/services/rich_messages/types/link_button.rb:38-52`; texto `Rótulo: endereço` (`:54-56`) | botão abre o endereço |
| Formulário (Flow) | S\* ≤24, X >24 | X | X | S\* ≤24, X >24 | sem versão em texto (`types/flow.rb:44`), recusado fora da Cloud ou fora da janela (`rich.rb:250-266`); o "+" esconde (`mais/MaisDoWhatsapp.vue:93-109`); resposta `nfm_reply` (`base:241-248`) | enviar, preencher e ver a resposta |
| Prévia de link | S\* | N | L (conector com `linkPreview: 'OFF'`, `inbox_provisioner.rb:125`) | S\* ≤24; >24 ligada pelo motor (documento do #1709: "sem querer") | `previa_de_link_no_envio.rb:12-35` | prévia aparece no app |
| Nota privada | nunca sai | nunca sai | nunca sai | nunca sai | `rich.rb:84-86`; a trava só olha o que vai ao canal (`app/services/rich_messages/send_guard.rb:9-11`) | — |
| Lida (tiques azuis no cliente) | S\* | N | S\* | S\* (pela Cloud) | `app/services/conversa_canal/leitura_no_canal.rb:24-30`, prazo de 30 dias (`:18`) | abrir a conversa marca lida no aparelho |
| Digitando | S (agente Autonomia) | N | E (2 s fixos) | S >24 | `cloud:20-37`; `whatsapp_hybrid/typing.rb:28-34` | — |
| Ligação | — | — | E | — | a tela lê `waha_call_summary` (`ligacao/ligacao.js:1-4`); quem grava é o conector | ligação perdida e recusada |
| Mensagens temporárias | L | L | E | L | a tela lê `waha_ephemeral` (`temporarias/temporarias.js:1-4`) | — |
| Pedir dados do contato | S | X | — | S (pela Cloud) | `envio:15`, `envio:24-30`, `app/models/channel/whatsapp.rb:146` | — |
| Não suportada (com o tipo) | S\* | S\* | E | S\* | `base:140-147` + `tipo_nao_suportado.rb` | gif, mensagem fixada |
| PDF com miniatura | L | ? | ? | ? | teste real de 14/10 (fora deste repositório): documento só mostra ícone na Cloud API | — |

## 4. Buracos encontrados (candidatos a Issue)

Hipóteses estão marcadas como tal; nada aqui foi confirmado em produção.

- **B1. 360dialog On-Premises.** O provedor fala com `waba.360dialog.io/v1` (`360:55-58`). Hipótese a conferir: a Meta
  anunciou o fim da On-Premises API em 2025; se o endereço não responde mais, toda a coluna 360dialog é teórica.
  Primeiro passo: contar caixas `provider: 'default'` ativas (leitura, com OK).
- **B2. Citação perdida.** Não sai no 360dialog (nenhum `context`), no plano B do Híbrido (`wt:120-128`) e no
  `input_select` da Cloud (`cloud:276-291`). O atendente cita e o cliente recebe sem citação, sem aviso.
- **B3. Tela e servidor discordam no número reserva.** O "+" esconde Documento e Fotos (`MaisDoWhatsapp.vue:102-109`) e
  tira o microfone (`ReplyBottomPanel.vue:203-213`), mas o servidor manda anexo pelo WAHA (`wt:120-128`), e o clipe do
  Chatwoot continua aberto. Decidir: liberar na tela ou barrar no servidor.
- **B4. Figurinha não sai como figurinha.** Nenhum envio usa `type: 'sticker'`; `.webp` vai como `image` na Cloud.
- **B5. Áudio de arquivo vira voz no plano B.** `wt:16` manda todo `audio` por `sendVoice`, sem olhar
  `is_voice_message`.
- **B6. Pedido do catálogo sem a pele.** Sem a pele, o `order` cai no `attach_files` do Chatwoot, que pede à Meta a
  mídia de um id que não existe (`recebimento_do_whatsapp.rb:51-56`). Conferir o que a main grava hoje.
- **B7. Produto e carrossel só como modelo.** `product`, `product_list` e carrossel interativo fora de modelo não
  existem (a Meta permite os dois primeiros com a janela aberta).
- **B8. Opções antigas (`input_select`) falham no plano B.** Por desenho (`router.rb:44`), mas o robô que ainda usa o
  formato antigo fica sem resposta fora das 24 h.
- **B9. Reação no Híbrido fora das 24 h.** Recusada pela regra da Cloud, embora o WAHA reaja sem janela.
- **B10. Vários anexos numa caixa WAHA.** O painel não divide para `Channel::Api` (`ReplyBox.vue:911-914`); depende do
  conector mandar todos.
- **B11. 360dialog sem reação, sem lida, sem "digitando" e sem prévia de link.** Tudo isso só existe para Cloud e WAHA.

## 5. Roteiro do teste real

1. **Cloud** (conta 1, caixa 118, número autorizado pelo Rodrigo), janela aberta: uma mensagem de cada linha da grade,
   na ordem da tabela; depois, com a janela fechada (conversa sem mensagem do cliente há mais de 24 h): texto (espera
   "fora da janela"), modelo, carrossel e produto de modelo.
2. **Híbrida**: a mesma caixa, se a conexão WAHA auxiliar estiver ligada nela; fora das 24 h, texto, foto, áudio de
   arquivo (B5), documento, contato, opções do "+" e do `input_select` (B8), citação (B2), reação (B9).
3. **WAHA comum**: só depois de escolher a caixa e com OK; repetir depois do motor customizado (#1741).
4. **360dialog**: só se B1 mostrar caixa ativa.

Em cada envio, anotar: id devolvido (wamid ou id do motor), status no painel, o que o celular mostra, e a marca
"Enviado como texto" quando houver. Recebimento: o Rodrigo manda do celular, e se confere a bolha com e sem a pele.

## 6. O que já foi testado de verdade

| Data | Caixa | O quê | Resultado |
|---|---|---|---|
| 17/10/2026 | Cloud (conta 1, caixa 118), janela aberta | Foto PNG como documento; vídeo MP4 como documento (código do #1724, `document_indexes`) | aceito pela Meta (wamid); no celular chegou como arquivo, com legenda e nome (comentário na Issue #1733) |
| 14/10/2026 | Cloud | Documento PDF e cabeçalho de documento em modelo | só ícone, sem miniatura (limite da plataforma) |

Todo o resto da matriz é leitura de código.
