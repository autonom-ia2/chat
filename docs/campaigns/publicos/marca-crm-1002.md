# Marca da campanha no CRM e marcas na conversa (#1002)

Refs #990. Aceites do PRD cobertos: K1–K7, P1, P2 e o topo da conversa (D20, §6.11).

## 1. Marca na resposta (D14)

"Respondeu" = mensagem recebida do contato na mesma caixa até **72h** depois do envio (vale para
WhatsApp e e-mail). A conversa dessa mensagem ganha a marca pelo mesmo mecanismo de Links e QR codes
(`Ctwa::CampaignBuilder.attribute!`):

| canal | destinatários lidos | `source` | `source_id` |
|---|---|---|---|
| WhatsApp Oficial | `campaign_recipients` (enviado, entregue ou lido) | `campaign_whatsapp` | `campaign:whatsapp:<id>` |
| WhatsApp API | `whatsapp_api_campaign_recipients` (enviado) | `campaign_whatsapp` | `campaign:whatsapp_api:<id>` |
| E-mail | `email_campaign_recipients` com o e-mail do contato, de campanha cujas respostas vão para a caixa (caixa de envio no modo direto; caixa de resposta do domínio no modo SES) | `campaign_email` | `campaign:email:<id>` |

- Nada é gravado no envio. A primeira origem da conversa nunca muda; a campanha entra como toque seguinte.
- Várias campanhas na janela: marca **só a do envio mais recente** (a que foi respondida).
- Idempotente por conversa + campanha.
- Fluxo: `CampaignJourney::ReplyMarkListener` (`message_created`, só mensagem recebida) →
  `CampaignJourney::ReplyMarkJob` → `CampaignJourney::ReplyMarker`. O listener entra no
  `AsyncDispatcher` por módulo prepended em `config/initializers/campaign_journey.rb`.
- Desligado com `CAMPAIGN_JOURNEY_ENABLED` off (inclusive o código de campanha abaixo).

## 2. Código de campanha no botão do e-mail (K4)

Tabela do fork `campaign_reply_codes (account_id, campaign_type, campaign_id, code)`, código único,
mesmo alfabeto e tamanho do link rastreado. O JSON da campanha de e-mail (`show`) traz
`whatsapp_reply_code`; `CampaignJourney::ReplyCodes.wa_link(campaign, inbox:, text:)` monta o
`wa.me` com `#CODIGO` no fim do texto. A inserção do botão no editor fica para outro PR.

`Ctwa::TrackedLinkAttributor` continua lendo o `#CODIGO` como antes (a regex dele não mudou);
código que não é link rastreado da caixa é procurado como código de campanha.

**Limite conhecido (aceito):** o gerador de código do link rastreado não consulta
`campaign_reply_codes`. Um link criado depois pode, por acaso (cerca de 1 em 10⁹ por par), pegar
um código que uma campanha já tem. Nesse caso o link rastreado da caixa vence (é procurado
primeiro) e o código da campanha deixa de marcar naquela caixa. Código de campanha apagada fica
na tabela e apenas deixa de marcar.

## 3. Leituras novas

`GET /api/v1/accounts/:account_id/campaign_journey/contact_origins/:contact_id`

```json
{ "payload": {
  "marks": [{ "source": "tracked_link", "source_id": "link:ABC234", "source_type": "tracked_link",
              "headline": "Feira 2026", "source_url": null, "touched_at": "…", "conversation_display_id": 42 }],
  "audiences": [{ "id": 1, "name": "Clientes auto" }] } }
```

Marcas de todas as conversas do contato que o agente pode ver (mesma regra da lista de conversas),
na ordem; públicos = importações com linha importada desse contato (base antiga mostra o nome da
campanha). Não depende do flag da jornada.

`GET /api/v1/accounts/:account_id/campaign_journey/campaign_names?campaign_ids=1,2&whatsapp_api_campaign_ids=3`
→ `{ "payload": { "campaigns": { "1": "…" }, "whatsapp_api_campaigns": { "3": "…" } } }` (só da conta).

## 4. Mensagem de campanha na conversa (P2)

- **WhatsApp Oficial, campanha ligada a público** (`CampaignJourney::SentMessageRecorder`). O envio
  **nunca cria conversa**: uma campanha para milhares de pessoas não pode disparar milhares de
  `conversation_created` (automações, webhooks, n8n de clientes) nem encher a lista.
  - **No envio:** se o contato já tem conversa não resolvida naquela caixa (mesma regra de
    reaproveitamento do WhatsApp; com "uma conversa por contato", a última), a mensagem aceita pela
    Meta entra nela. Se não tem, nada é gravado.
  - **Na resposta:** `CampaignJourney::ReplyMarker` acha o destinatário respondido; se a conversa
    da resposta (criada pelo fluxo normal) ainda não tem a mensagem, ela é inserida com
    `created_at` = `campaign_recipients.sent_at` e o status do destinatário, **antes** da marca.
    Por ser registro de mensagem passada, leva `content_attributes.history_import` — a trava do fork
    que já pula todos os efeitos de mensagem nova (eventos, webhooks, `SendReplyJob`), a mesma do
    histórico do WhatsApp. Consequência: com a conversa já aberta na tela, ela aparece ao recarregar.
  - Nos dois casos: mensagem de saída com o texto que a pessoa recebeu, `source_id` = id da Meta (o
    webhook de status atualiza entregue/lido; `Base::SendOnChannelService` não envia mensagem com
    `source_id`), `additional_attributes.campaign_id` + `campaign_template_name`. Idempotente por
    caixa + `source_id` (gravada no envio não duplica na resposta). Não grava marca (D14).
  - Campanha antiga por etiqueta segue o comportamento do Chatwoot.
  - `conversation.campaign_id` **não** é preenchido: preencher tiraria essas conversas da origem por
    clique inferido de link rastreado (decisão aceita).
- **WhatsApp API:** a mensagem já existia (`whatsapp_api_campaign_id`).
- **E-mail:** o envio não cria mensagem na conversa; não há rótulo (decisão aceita).
- A bolha mostra "Campanha: <nome> · modelo <modelo>" (`CampaignMessageLabel`).

## 5. Tela

- Painel do contato: "Origem e campanhas" (todas as marcas na ordem + públicos).
- Topo da conversa: a primeira marca de campanha da conversa, ou a origem se não houver.
- Gaveta do card: a sequência de marcas quando há mais de uma. Card: primeira marca + "+N".
- Filtro de campanha (Kanban e Conversas): as campanhas aparecem como "Campanha WhatsApp: <nome>".

## 6. Toques em arquivos do Chatwoot

| arquivo | linhas | motivo |
|---|---|---|
| `config/routes.rb` | +2 | duas leituras no namespace `campaign_journey` |
| `components-next/message/Message.vue` | +13 | rótulo da campanha acima da bolha |
| `routes/dashboard/conversation/ContactPanel.vue` | −10/+4 | pílula do fork trocada pelo painel "Origem e campanhas" |
| `components/widgets/conversation/ConversationHeader.vue` | +2 | marca da campanha no topo |
| `components-next/filter/provider.js` | +2/−1 | nome das opções de campanha |
| `db/schema.rb` | tabela nova | `campaign_reply_codes` |
