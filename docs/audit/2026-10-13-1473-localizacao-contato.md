# #1473 P5: pedido de localização, localização e contato pelo painel (13/10/2026)

Três tipos novos de `content_attributes.rich_message`, pelo mesmo
`POST /api/v1/accounts/:account_id/conversations/:id/messages` do botão de link, e a localização que o cliente
manda passa a chegar estruturada. Encaixe, trava, criação pela API (422), reenvio, texto de saída, webhook da caixa
API e plano B do Híbrido são os do módulo (`app/services/rich_messages.rb`); esta entrega só acrescenta arquivos.

Formatos conferidos nas páginas oficiais da Meta em 13/10/2026:
[location-request-messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/location-request-messages),
[location-messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/location-messages),
[contacts-messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/contacts-messages).

## Contratos

### `location_request` — pedir a localização

```json
{ "content": "Para achar a unidade mais perto, me envie onde você está.",
  "content_attributes": { "rich_message": { "type": "location_request" } } }
```

- Corpo obrigatório, até 1024 caracteres (limite da Meta), medido no texto que sai.
- Meta: `{ "type": "interactive", "interactive": { "type": "location_request_message", "body": { "text": … },
  "action": { "name": "send_location" } } }`. Cabeçalho e rodapé não são enviados: a sintaxe e a tabela de
  parâmetros da página trazem só `body.text` (obrigatório, "Maximum 1024 characters.") e `action.name`, e as palavras
  "header" e "footer" não aparecem na página (conferido em 13/10/2026). Ausência na página não prova que a Meta
  recusa; só que não está documentado.
- Versão em texto: só o corpo (o próprio corpo já pede o endereço).

### `location` — enviar um ponto no mapa

```json
{ "content": "",
  "content_attributes": { "rich_message": { "type": "location", "latitude": -23.5489, "longitude": -46.6388,
                                            "name": "Unidade Centro", "address": "Rua das Flores, 123 - Centro" } } }
```

- `latitude` (-90 a 90) e `longitude` (-180 a 180): obrigatórias, **número JSON** (texto é recusado). O agente
  nativo converte endereço em coordenadas antes (Google Places, outra frente); este tipo recebe as coordenadas prontas.
- `name` (até 100) e `address` (até 300): opcionais, em uma linha. A Meta não documenta limite; os números são
  nossos, para caber no cartão e na versão em texto. Em branco (`""` ou só espaços) contam como ausentes: não dão
  422 e não vão à Meta.
- **Sem corpo**: o formato da Meta não tem texto. `content` não vazio é recusado (422 na criação, `failed` no envio).
- Meta: `{ "type": "location", "location": { "latitude": "-23.5489", "longitude": "-46.6388", "name": …,
  "address": … } }`. A tabela de parâmetros da Meta dá às duas o tipo _String_: `<LOCATION_LATITUDE>` "**Required.**
  Location latitude in decimal degrees." (exemplo `37.44216251868683`) e `<LOCATION_LONGITUDE>` "**Required.**
  Location longitude in decimal degrees." (exemplo `-122.16153582049394`); na sintaxe, `"latitude":
  "<LOCATION_LATITUDE>"`. Por isso vão como texto, em notação decimal comum (`BigDecimal#to_s('F')`: `0.00001`,
  nunca `1.0e-05`), sem perder casas.
- Versão em texto: nome, endereço e `https://maps.google.com/?q=<lat>,<lng>`, um por linha (os que vierem).
- O endereço do mapa (`MAP_LINK`) existe em dois lugares, o tipo Ruby e a bolha `types/Location.vue`, porque o
  front não importa constante do Ruby. Cada um tem um comentário apontando o outro.

### `contact` — enviar um cartão de contato

```json
{ "content": "",
  "content_attributes": { "rich_message": { "type": "contact", "name": "Recepção da Unidade Centro",
                                            "phone": "+55 11 4000-0473", "wa_id": "551140000473" } } }
```

- `name`: obrigatório, até 100 caracteres, em uma linha (limite nosso; a Meta não dá).
- `phone`: obrigatório, texto começando com `+` e o código do país, de 8 a 15 dígitos (máximo do padrão
  internacional E.164), aceitando espaço, hífen, ponto e parênteses. Vai à Meta como foi escrito. A Meta não dá
  regra de formato: a linha de `<PHONE_NUMBER>` diz só "WhatsApp user phone number.", tipo _String_, exemplo
  `+16505559999`. O `+` obrigatório e a contagem de dígitos são regra nossa (decisão: sem `+` é recusado).
- `wa_id`: opcional, só dígitos (8 a 15); em branco conta como ausente. Linha de `<WHATSAPP_USER_ID>` na Meta:
  "WhatsApp user ID. If omitted, the message will display an Invite to WhatsApp button instead of the standard
  buttons."
- **Sem corpo**, como a localização.
- Meta: `{ "type": "contacts", "contacts": [{ "name": { "formatted_name": …, "first_name": … },
  "phones": [{ "phone": …, "wa_id": … }] }] }` (na sintaxe da Meta: `"phones": [{ "phone": "<PHONE_NUMBER>",
  "type": "<PHONE_NUMBER_TYPE>", "wa_id": "<WHATSAPP_USER_ID>" }]`; o `type` não é enviado). `first_name` vai com o
  mesmo nome para o aparelho do cliente salvar com nome. Um contato por mensagem; a Meta aceita mais: "Each message
  can include information for up to 257 contacts".
- Versão em texto: `Nome: telefone`.

## Onde cada canal fica

Os três têm versão em texto, então seguem a tabela do botão de link
(`docs/audit/2026-10-13-1473-botao-de-link.md`): formato nativo no WhatsApp oficial com a janela aberta; `failed`
com o erro de janela quando fechada (ou texto pelo Híbrido); versão em texto no 360dialog, Twilio, Telegram (com
escape), caixa API e demais; recusa em e-mail e chat do site.

## Localização recebida do cliente

**Antes (fato, lido no código):** `Whatsapp::IncomingMessageBaseService#attach_location`
(`app/services/whatsapp/incoming_message_base_service.rb:205`) cria um anexo `location` com `coordinates_lat`,
`coordinates_long` (colunas próprias) e `fallback_title` = `"nome, endereço"` cortado em 255. Nome e endereço não
ficavam separados, e **o endereço se perdia quando o cliente não mandava nome** (`fallback_title` vazio).

**Agora:** `RichMessages::ReceivedLocation` (`app/services/rich_messages/received_location.rb`), prepend em
initializer próprio (`config/initializers/rich_messages_received_location.rb`), acrescenta ao fim de
`attach_location`:

```json
"content_attributes": { "shared_location": { "latitude": -23.5505, "longitude": -46.6333,
                                             "name": "Praça da Sé", "address": "Praça da Sé, São Paulo - SP" } }
```

- `name` e `address` só quando o cliente compartilha (a Meta diz que vêm só nesse caso).
- O anexo continua igual (a bolha de localização recebida do atendente e o que já lê o anexo não mudam).
- O webhook do robô leva `content_attributes` (`Message#webhook_data`), então recebe `shared_location`. A resposta
  ao pedido traz `context.id`; o recebimento já grava `in_reply_to` com o id da mensagem do pedido — o robô liga a
  resposta ao pedido por aí. Provado em `spec/services/rich_messages/received_location_spec.rb`.
- Vale para o WhatsApp oficial e o 360dialog (mesmo serviço base). Outra frente (#1433) mexe nesse arquivo: aqui
  nada dele é editado e o método que escolhe o agente não é tocado; o prepend só cobre `attach_location`.

## Conversa do atendente

- `types/LocationRequest.vue`: corpo + botão "Enviar localização" (imagem do que o cliente vê, não clicável, com
  texto para leitor de tela dizendo que o botão aparece no WhatsApp do cliente) e o aviso "Pedimos ao cliente onde
  ele está". O botão só aparece quando a caixa da conversa é WhatsApp oficial (Cloud), lido do store de caixas pelo
  `useInbox` (sem tocar arquivo comum); no 360dialog, Twilio e demais o cliente recebe só o corpo, e a bolha mostra
  só o corpo e o aviso.
  **Limite conhecido (Híbrido):** numa caixa Cloud com WhatsApp Híbrido, o plano B (janela fechada ou recusa 131047
  da Meta) manda só o texto pelo WAHA. A bolha não sabe por qual transporte a mensagem saiu e continua mostrando o
  botão nesse caso.
- `types/Location.vue`: cartão no desenho do anexo de localização ("<quem> compartilhou uma localização", nome,
  endereço por extenso), **sem mapa externo**; "Ver no mapa" abre `maps.google.com` em outra aba, só quando as duas
  coordenadas são números finitos na faixa.
- `types/Contact.vue`: cartão no desenho do anexo de contato, com nome e telefone, sem ação.
- Cores do ícone por tokens do tema (`bg-n-teal-9` na localização, `bg-n-ruby-9` no contato), não por hexadecimal.
  O contato fica num tom rubi um pouco diferente do rosa (`#D6409F`) do anexo de contato recebido do Chatwoot: o tema
  não tem rosa.
- `RichMessage/SharedCard.vue` (fora de `types/`): o cartão dos dois. Não usa `BaseAttachment.vue` porque ele exige
  ação (o contato não tem) e o botão dele não tem o alvo de toque de 44 px; a ação aqui é o `ActionRow`.
- Mensagem sem texto: o `Message.vue` já mostra a bolha de tipo rico com `content` vazio; provado nos specs pela
  montagem completa (`montarMensagem`).

## Arquivos

Novos: `app/services/rich_messages/types/{location_request,location,contact}.rb`,
`app/services/rich_messages/received_location.rb`, `config/initializers/rich_messages_received_location.rb`, os
specs em `spec/services/rich_messages/`, `RichMessage/types/{LocationRequest,Location,Contact}.vue`,
`RichMessage/SharedCard.vue`, `RichMessage/specs/{LocationRequest,Location,Contact}.spec.js` e
`RichMessage/specs/montarRica.js`.

Comuns tocados: só os blocos `LOCATION_REQUEST`, `LOCATION` e `CONTACT` de `i18n/locale/{en,pt_BR}/richMessage.json`.
Nenhum arquivo do Chatwoot oficial editado.

## Fora desta entrega

- A bolha da localização **recebida** (`bubbles/Location.vue`, do Chatwoot) continua mostrando só o
  `fallback_title`; quando o cliente manda endereço sem nome, ela fica sem texto. O dado está em `shared_location`;
  mostrar exigiria editar a bolha do Chatwoot (ou um prepend de front), fora do escopo.
- Contato com mais de um telefone, e-mail, empresa ou vários contatos numa mensagem.
- Coordenadas em texto (`"-23.5"`): recusadas de propósito, para não interpretar texto.
- Prova real na conta 16 e troca de nós do n8n: depois do deploy, como as outras entregas.
