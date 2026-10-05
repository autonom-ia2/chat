# Públicos e Nova campanha — o que a tela do #993 chama e ainda não existe

Refs #990. O que a tela do #993 (Novo público, Nova campanha em 3 passos para WhatsApp
Oficial) chama. Itens 2 e 3 **ainda não existem** no backend: respondem `404` e a tela se
comporta como descrito em **"Sem o endpoint"** — nada quebra, só some a parte que depende dele.
Tudo continua atrás de `CAMPAIGN_IMPORT_ENABLED` (Públicos) e `CAMPAIGN_JOURNEY_ENABLED`
(jornada). Permissões: leitura com `campaign_view`; escrita com `campaign_manage`.

Base dos itens 1–5 (exceto a criação de campanha): `/api/v1/accounts/:account_id/campaign_imports`. Cliente:
`app/javascript/dashboard/api/campaignJourney.js`.

## 1. Já existe no backend (#998, #1005) — a tela usa

- Canais: `PATCH /campaign_imports/:id/channels` `{ "email": false }` (api-1005.md §5).
  `422 channel_without_data` volta o interruptor; `422 audience_in_use` mostra as campanhas.
- Empresas: `PATCH /campaign_imports/:id/companies` `{ "create_companies": false }`; prévia em
  `validation_summary.companies` (`available`, `companies_created`, `companies_reused`,
  `contacts_linked`, `contacts_kept`), números finais em `companies` (api-992.md §9).
  `available: false` ou sem coluna de empresa → o bloco não aparece (C6).
- Excluir público: `DELETE /campaign_imports/:id`; `422 audience_in_use` com `campaigns[]`.
- Criar campanha: item 5 abaixo (api-1005.md §4).

## 2. Linhas com problema (B5)

`GET /campaign_imports/:id/problem_rows?page=1` → `200`

```json
{
  "payload": [
    { "row_number": 14, "name_masked": "Carlos S.", "contact_masked": "+55 41 3XXX-XX21",
      "errors": ["invalid_brazilian_mobile_number"] }
  ],
  "meta": { "count": 2, "page": 1, "per_page": 50 }
}
```

- Só linhas `invalid` da validação atual, ordem de `row_number`.
- `name_masked`: primeiro nome + inicial do último (nunca o nome inteiro).
- `contact_masked`: `raw_phone_masked` ou, sem celular, `email_masked`; `null` quando vazio.
- `errors`: os códigos já gravados em `error_messages` (`missing_contact`, `invalid_email`,
  `blank_email`, `duplicate_email_in_file`, `duplicate_phone_in_file`,
  `invalid_brazilian_mobile_number`, `blank_phone_number`, `formula_phone_number`,
  `formula_detected`). A tela traduz cada código; código desconhecido vira "Outro problema".

Sem o endpoint: a tela mostra os motivos agregados de `validation_summary.errors` (motivo ×
quantidade) e o botão "Baixar linhas com problema" (`download?file=error_csv`, já existe).

## 3. Primeiro contato para a prévia

`GET /campaign_imports/:id/sample_contact` → `200`

```json
{ "payload": { "name": "Mariana Costa", "company_name": "Alfa Corretora",
  "extra_values": { "Vencimento": "10/2026" } } }
```

Primeira linha válida (ou importada) do público. Usada só na prévia "Como o cliente vê" do
passo Mensagem (PRD §6.3). Dado da própria conta, para quem tem `campaign_manage`.

Sem o endpoint (ou `payload: null`): a prévia mostra o rótulo do dado no lugar do valor
(`[Nome]`, `[Vencimento]`).

## 4. Opcionais (a tela usa se vierem)

- `schema_resolution.columns[].example_masked`: exemplo mascarado da coluna (`Mariana C.`,
  `+55 11 9XXXX-XX12`, `m**@alfa.com.br`) para "Colunas encontradas" (PRD §6.6-1). Sem ele, a
  linha mostra só a contagem.
- `GET /campaign_imports?saved=true` (públicos concluídos) e `q=` (busca): hoje o passo
  Público lê a primeira página (25) e filtra na tela.

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
- `variable_bindings` (chave = variável do corpo do modelo):
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
