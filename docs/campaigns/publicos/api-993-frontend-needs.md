# Públicos e Nova campanha — contrato que a tela do #993 usa

Refs #990. Tudo o que a tela do #993 (Novo público, Nova campanha em 3 passos para WhatsApp
Oficial) chama já existe no backend desta branch (#992, #998, #1005 e os itens do #993 abaixo).
Atrás de `CAMPAIGN_IMPORT_ENABLED` (Públicos) e `CAMPAIGN_JOURNEY_ENABLED` (jornada). Leitura com
`campaign_view`; escrita e prévia com dado real com `campaign_manage`. Cliente:
`app/javascript/dashboard/api/campaignJourney.js`.

Base: `/api/v1/accounts/:account_id/campaign_imports`.

## 1. Endpoints de #998 e #1005 que a tela usa

- Canais: `PATCH /:id/channels` `{ "email": false }` (api-1005.md §5). `422 channel_without_data`
  volta o interruptor; `422 audience_in_use` mostra as campanhas.
- Empresas: `PATCH /:id/companies` `{ "create_companies": false }`; prévia em
  `validation_summary.companies` (`available`, `companies_created`, `companies_reused`,
  `contacts_linked`, `contacts_kept`), números finais em `companies` (api-992.md §9).
  `available: false` ou sem coluna de empresa → o bloco não aparece (C6).
- Excluir público: `DELETE /:id`; `422 audience_in_use` com `campaigns[]`.

## 2. Linhas com problema (B5) — #993

`GET /:id/problem_rows?page=1` (`campaign_view`) → `200`

```json
{ "payload": [ { "row_number": 3, "contact_masked": "***", "errors": ["invalid_brazilian_mobile_number"] } ],
  "meta": { "count": 1, "page": 1, "per_page": 50 } }
```

Linhas `invalid` da validação atual, por `row_number`, 50 por página. `contact_masked` =
`raw_phone_masked` ou, sem celular, `email_masked` (mascaramento que já existia); **sem nome**.
`errors` são os códigos de `error_messages`; a tela traduz e código desconhecido vira "Outro
problema". Spec: `spec/requests/api/v1/accounts/campaign_import_audience_preview_spec.rb`.

## 3. Primeiro contato para a prévia — #993

`GET /:id/sample_contact` (`campaign_manage`) →
`{ "payload": { "name", "first_name", "company_name", "extra_values" } }` ou `payload: null`.
Primeira linha `valid` ou `imported` do próprio público (nome e empresa do contato quando já
salvo). Só esse público, da conta da requisição.

## 4. Também no JSON — #993

- `schema_resolution.columns[].example_masked`: o primeiro exemplo no formato mascarado que vai
  ao Jev (`Aaa Aaaaa`, `00000000000`, `[email address]`), nunca o valor.
- `GET /campaign_imports?saved=true&q=…&page=…`: públicos salvos (`completed`,
  `completed_with_failures`) e busca no nome (curingas de LIKE escapados); `meta.count` é o
  total filtrado. O passo 1 usa isso, com "Ver mais públicos".
- `reachability` no `show` (B8), a partir de `ready_to_confirm`:

```json
{ "whatsapp": { "total": 98, "receive": 95, "opted_out": 3 },
  "email": { "total": 40, "receive": 35, "unsubscribed": 2, "bounced": 2, "suppressed": 1 } }
```

  Compara os hashes das linhas com contatos que recusaram mensagens (#737, com ou sem o 9) e
  com as supressões de e-mail da conta (descadastro, bounce permanente, demais). Canal
  desligado → `receive: 0`. A tela mostra "não recebem" em Novo público e desconta em "vão
  receber" (passo 3). Spec: `spec/services/campaign_imports/audience_reachability_spec.rb`.

## 4b. Painel lateral, "vão receber", máscara, Chat ao vivo e SMS — #993

- **Contatos do público** (painel "Ver contatos e empresas"): `GET /:id/contacts?page=` →
  `{ payload: [{ id, name, email, phone_number, company_name }], meta: { count, page, per_page: 25 } }`,
  `campaign_view`; vale também para importações antigas (F1). Contatos não tem filtro por lista.
- **Campanhas que usaram**: `show` traz `linked_campaigns: [{ type, id, title, channel, status }]`
  (vínculos de `campaign_audience_links`, inclusive os do backfill de campanhas antigas).
- **"Vão receber" exato** (decisão de 05/10): `POST /api/v1/accounts/:id/campaign_journey/recipient_previews`
  `{ campaign_import_id, channel: whatsapp_cloud|whatsapp_api|sms|email, variable_bindings,
  variable_defaults, message_body }` → `{ payload: { channel, total, receive, reasons, missing_by_variable } }`.
  Mesma regra do envio (consentimento por linha, recusa #737, supressão de e-mail, variáveis sem
  valor), **cada pessoa num motivo só**, nesta ordem: `channel_disabled`, `opted_out`,
  `unsubscribed`/`bounced`/`suppressed`, `missing_variables`. Nada é gravado. `campaign_manage`.
  Spec: `spec/requests/api/v1/accounts/campaign_journey/recipient_previews_spec.rb`.
- **Máscara de celular única** (decisão de 05/10): `CampaignImports::PhoneMask` — só o código do
  país e os 4 últimos dígitos (`+55 •• •••••-7890`), usada pelas linhas do público, CSV de erros,
  `problem_rows` e destinatários do WhatsApp API.
- **Chat ao vivo** (#1008): fluxo próprio na tela sobre a API de campanhas `ongoing` de sempre;
  quem conversa por uma campanha do site ganha a marca `campaign_live_chat` (ReplyMarker do #1002,
  `conversation.campaign_id`).
- **SMS** (#1004, api-1004.md §5a): selo `channels.sms` (ausente = desligado com a contagem do
  WhatsApp), "sem caixa" sem caixa SMS ou com `422 channel_without_inbox`, cartão SMS no passo 2
  com `POST campaign_journey/campaigns channel: "sms"`; o contador de partes da tela segue
  `CampaignJourney::SmsSegments` (spec de paridade em `smsSegments.spec.js`); `recipient_previews`
  e `reachability` incluem SMS.

## 5. Criar a campanha (WhatsApp Oficial)

`POST /api/v1/accounts/:account_id/campaign_journey/campaigns` (JSON)

```json
{
  "campaign_import_id": 42,
  "channel": "whatsapp_cloud",
  "campaign": {
    "title": "Renovação auto — outubro",
    "inbox_id": 7,
    "scheduled_at": "2026-10-06T12:00:00.000Z",
    "template_params": {
      "name": "renovacao_auto_v2",
      "namespace": "…",
      "category": "MARKETING",
      "language": "pt_BR",
      "processed_params": { "body": { "1": "", "2": "", "3": "Equipe Hub2You" } }
    },
    "variable_bindings": {
      "1": { "source": "contact", "value": "first_name" },
      "2": { "source": "column",  "value": "Vencimento" },
      "3": { "source": "fixed",   "value": "Equipe Hub2You" }
    },
    "variable_defaults": { "2": "em breve" }
  }
}
```

- `scheduled_at`: ISO 8601 em UTC, ou `null` para "Agora". A tela converte a data e hora
  escolhidas no **fuso da conta** (`account.timezone`; sem fuso, o do navegador).
- `template_params`: mesmo formato que o `WhatsAppCampaignDialog` antigo manda em
  `POST /campaigns` (`name`, `namespace`, `category`, `language`, `processed_params`). Em
  `processed_params.body`, variável `fixed` já vem com o texto; `contact`/`column` vêm vazias e
  o backend resolve por pessoa com `variable_bindings`. Cabeçalho de mídia vem como no
  diálogo antigo (`header.media_url`, `media_type`, `media_name`).
- `variable_bindings` — chave = variável do corpo (`"1"`, `"nome"`), do cabeçalho de texto
  (`"header.1"`) ou do botão de URL (`"button.<índice do botão>"`, uma variável por botão)
  (`CampaignJourney::TemplateVariableKeys`, #993). Todas as variáveis do modelo aprovado
  precisam de ligação ou texto padrão; no envio cada valor vai para o seu componente. Spec:
  `spec/services/campaign_journey/template_variable_keys_spec.rb`.
  - `contact` → `value` ∈ `name`, `first_name`, `company` (nome, primeiro nome, empresa ligada
    ao contato);
  - `column` → `value` = cabeçalho exato de `extra_columns` do público;
  - `fixed` → `value` = texto igual para todos.
- `variable_defaults`: texto usado quando a pessoa não tem o valor (B1b). Sem padrão, a pessoa
  fica de fora com "falta {{N}}".
- Sem lote: a campanha manda para todo o público de uma vez (D3).

Respostas:

- `200 { "id", "display_id", "title", "channel", "scheduled_at", "recipients_count" }` — a
  tela volta para a lista Campanha e avisa "Campanha criada".
- `422 { "error": "<mensagem>", "code": "..." }`, `code` ∈ `whatsapp_cloud_required`,
  `channel_not_in_audience`, `audience_not_ready`, `invalid_variable_bindings`,
  `invalid_campaign`; `404 campaign_journey_disabled` (flag desligada); `401` sem
  `campaign_manage`. Cada um tem texto próprio (`journeyErrors.js` →
  `CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.ERRORS.*`); qualquer outro vira "Não foi possível criar
  a campanha agora. O rascunho continua salvo." A tela fica no passo 3.

## 6. Rascunho da campanha (só no navegador)

- Chave `localStorage`: `campaignJourney:draft:<account_id>` (um rascunho por conta e
  navegador). Conteúdo: `{ version: 1, title, audienceId, channel, inboxId, templateId,
  bindings, defaults, when, scheduledAt, step, updatedAt }` — nunca dado de contato.
- Gravado a cada mudança na Nova campanha e ao clicar "Criar público"; apagado quando a
  campanha é criada ou em "Cancelar".
- Volta da criação de público: `Novo público?from=campaign` mostra o aviso da campanha; ao
  salvar, abre `Nova campanha?audience=<id>` e o passo 1 já vem com o público escolhido (J3).
- "Usar em nova campanha" (lista de Públicos) abre `Nova campanha?audience=<id>` (F3).
