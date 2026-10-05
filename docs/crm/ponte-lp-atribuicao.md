# Ponte anúncio → landing page → WhatsApp → venda (#1011)

Contrato técnico entre a landing page (repositório `autonom-ia/site-placement`, issue #19) e o Chat2You.
PRD de produto: https://claude.ai/artifact/XSPxZqT8Wr7ZUXt3eTJhFd

## Por que existe

Anúncio da Meta que leva a uma página (não ao WhatsApp) não manda `referral` no webhook. A conversa chegava sem
origem (caso conversa #265, conta 18). A página passa a gerar um código de clique, coloca `#CODIGO` na mensagem do
WhatsApp e avisa o Chat2You em paralelo com os dados do anúncio. O atribuidor que já existe
(`Ctwa::TrackedLinkAttributor`) liga a conversa ao clique.

Regra de construção: aditiva. Só tabelas do fork (`ctwa_*`, `crm_*`), sem coluna em tabela do Chatwoot.

## 1. Banco (tabelas do fork)

`ctwa_tracked_links`

| coluna | tipo | uso |
|---|---|---|
| `usage` | string, not null, default `'direct'` | `direct` (QR/link) ou `website` (botão de página) |
| `allowed_origins` | jsonb, not null, default `[]` | origens autorizadas a avisar cliques, ex. `["https://placement.com.br"]` |
| `last_signal_at` | datetime | último aviso aceito da página |

`ctwa_tracked_link_clicks`

| coluna | tipo | uso |
|---|---|---|
| `campaign_key` | string | chave estável da campanha: `utm_id` quando for só dígitos e até 32 caracteres (id da Meta); outro `utm_id` vira `i:` + 10 primeiros hex do SHA1 dele; sem `utm_id`, `c:` + 10 primeiros hex do SHA1 de `utm_campaign`; `none` sem campanha |
| `page_url` | string(512) | URL da página sem query string |
| `lead_data` | jsonb, not null, default `{}` | `{ "fields": [{ "key", "label", "value" }] }` |
| `meta_signals` | jsonb, not null, default `{}` | `fbc`, `fbp`, `client_ip_address`, `client_user_agent` — só com consentimento |

Índice `(tracked_link_id, campaign_key)`.

`crm_meta_conversion_events`: coluna `attribution_mode` string (`ctwa` | `website`), nula em linhas antigas.

## 2. Endpoint público de aviso

`POST /l/:code/clicks` — `Public::TrackedLinkSignalsController` (ActionController::Base, sem CSRF, sem sessão).
`OPTIONS /l/:code/clicks` responde ao preflight.

A página usa `navigator.sendBeacon` com corpo `text/plain` (sem preflight). O servidor lê o corpo cru e faz parse de
JSON independentemente do content-type. Limite: 4096 bytes (maior → 413).

Antes do Rails, `Middleware::TrackedLinkSignalGuard` (lib/middleware) recusa com 413 o corpo declarado acima do
limite e troca o content-type do POST para `text/plain`: o Rails nunca interpreta nem loga o corpo (formulário e
sinais da Meta são dado pessoal), mesmo quando a página manda `application/json`. Por garantia, `lead`, `fbc`,
`fbp` e `page_url` também estão em `filter_parameters`.

Corpo:

```json
{
  "token": "K7P2M9QX",
  "page_url": "https://placement.com.br/seguro-viagem",
  "consent": true,
  "params": { "utm_source": "meta", "utm_medium": "paid", "utm_campaign": "Viagem EUA",
              "utm_term": "Conjunto 60+", "utm_content": "Video 2", "utm_id": "120211", "fbclid": "IwAR..." },
  "fbc": "fb.1.1759650000000.IwAR...",
  "fbp": "fb.1.1759650000000.123456789",
  "lead": { "fields": [
    { "key": "destination", "label": "Destino", "value": "América do Norte - EUA" },
    { "key": "ages", "label": "Idades", "value": "72" }
  ] }
}
```

Regras, na ordem:

1. Link inexistente → 404. Link com `usage != website` → 404.
2. Header `Origin` ausente ou fora de `allowed_origins` (comparação exata de `scheme://host[:port]`, normalizada em
   minúsculas, sem barra final) → 403. Nada é gravado.
3. `token`: exatamente 8 caracteres do alfabeto `Ctwa::TrackedLink::CODE_ALPHABET` (sem regex: `size == 8` e cada
   caractere em `CODE_ALPHABET`). Inválido → 422.
4. Token já existente: no mesmo link → 204 (idempotente, nada muda); em outro link → 409.
5. `params`: só as chaves de `Ctwa::TrackedLinkClick::TRACKING_PARAM_KEYS` (passa a incluir `utm_id`), strings,
   512 caracteres no máximo cada.
6. `fbc`/`fbp`/IP/user agent: gravados só com `consent == true`. `fbc` e `fbp` validados por formato com
   `split('.')`: 4 partes, a primeira `fb`, a terceira só dígitos, até 300 caracteres. Inválidos são descartados
   em silêncio (o clique é gravado). IP = `request.remote_ip`; user agent cortado em 255.
7. `lead.fields`: no máximo 12; `key` até 40, `label` até 60, `value` até 200 caracteres; strings; itens inválidos
   são descartados.
8. `page_url`: só `scheme://host/path`, sem query/fragment, até 512 caracteres; precisa ter a mesma origem do
   header `Origin`, senão é descartado.
9. Teto diário por link: com `TRACKED_LINK_SIGNALS_DAILY_LIMIT_PER_LINK` (padrão 5000) cliques nas últimas 24h → 429.
10. Grava `Ctwa::TrackedLinkClick` (expira em 72h, como hoje), incrementa `clicks_count` do link e atualiza
   `last_signal_at`. Resposta 204. Em seguida enfileira `Ctwa::LateClickReconcileJob` (ver seção 3).

Campo longo não derruba o clique: `page_url` aceita até 512 (validador próprio), `utm_id` fora do formato vira resumo.

CORS: quando a origem é autorizada, responder `Access-Control-Allow-Origin: <origin>`, `Vary: Origin`,
`Access-Control-Allow-Methods: POST, OPTIONS`, `Access-Control-Allow-Headers: Content-Type`, max-age 600.

Rack::Attack: `public_tracked_link_signals/ip`, 30 por minuto, POST em `/l/`; e `public_tracked_link_signals/code`,
`TRACKED_LINK_SIGNALS_PER_LINK_LIMIT` (padrão 120) por minuto por link.

**O header `Origin` não autentica.** O navegador não deixa a página mentir, mas fora dele (curl, script) qualquer
um manda o header que quiser. A defesa real contra volume anormal (CA-1.11) é o limite por link, por minuto e por dia.

## 3. Atribuição

`Ctwa::TrackedLinkAttributor#attribute_click!` segue igual para links `direct`. Para links `website`:

- `source_id` = `"site:#{link.code}:#{click.campaign_key}"`. Estável por campanha: o filtro de campanha do CRM
  agrupa cliques da mesma campanha, e dois cliques da mesma campanha na mesma conversa não duplicam toque.
- `headline` = `link.name`, mais ` · utm_campaign` quando houver.
- `source_url` = `click.page_url`.
- Depois de atribuir, grava `conversation.additional_attributes['lead_form']` =
  `{ 'link_code', 'fields', 'captured_at' }` quando `lead_data['fields']` existir. É escrito com lock e merge,
  sem apagar as outras chaves.
- **Clique inferido** (CA-1.5: sem `#TOKEN`, exatamente um clique da caixa em 10 minutos): liga a conversa e marca o
  toque com `inferred: true`, mas **não** grava `lead_form` e apaga do clique `lead_data`, `meta_signals` e
  `user_agent`. Quem clicou pode não ser quem escreveu: o card não mostra dado de outra pessoa e o CAPI não manda
  sinal dela. Só o `#TOKEN` explícito leva formulário e sinais.
- **Aviso atrasado:** se a mensagem com `#TOKEN` chegou antes do aviso, o `Ctwa::LateClickReconcileJob` procura,
  na caixa do link, uma mensagem recebida com `#TOKEN` a partir de 10 minutos antes do clique e liga a conversa
  como se o token tivesse sido achado na hora (com formulário).

`Ctwa::CampaignBuilder.source_for` ganha uma regra depois de `fbclid`: `utm_source` em
`%w[meta facebook fb instagram ig]` **e** `utm_medium` em `%w[paid cpc ppc paid_social]` (comparação de string,
minúsculas) → `meta_paid`. Cobre o iPhone, que pode remover o `fbclid`.

`utm_id` entra em `tracking_attributes` e em `TOUCH_KEYS`.

## 4. Card

`Crm::Cards::PayloadBuilder.campaign_touches_for` passa a expor `utm_campaign`, `utm_term`, `utm_content`, `utm_id`.
O payload do card ganha `lead_form` (da conversa principal, só quando visível ao usuário).

## 5. API da tela Links e QR codes

`GET/POST/PATCH/DELETE /api/v1/accounts/:id/ctwa_tracked_links`. POST e PATCH aceitam `name`, `usage` (só na
criação), `allowed_origins` (array, até 5 origens válidas `https://...`; `http://localhost` permitido só fora de
produção), `prefilled_text` (só `direct`). Payload ganha:

```json
{ "usage": "website", "allowed_origins": ["https://placement.com.br"], "last_signal_at": "...",
  "signal_url": "https://chat.hub2you.ai/l/AB3CDE/clicks",
  "ad_url_params": "utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}&utm_id={{campaign.id}}",
  "campaigns": [ { "campaign_key": "120211", "name": "Viagem EUA", "clicks": 40, "conversations": 31,
                   "won_cards": 4, "won_value_by_currency": { "BRL": 151120 } } ] }
```

`campaigns` só para `website`; nome = `utm_campaign` mais recente da chave; `won_cards` conta cards `won` cuja
conversa principal está entre as conversas atribuídas aos cliques daquela campanha. `won_cards` e
`won_value_by_currency` são financeiros: só saem para administrador (a listagem pede só `campaign_view`, que pode
vir de função personalizada, e financeiro nunca se delega por função). Os outros recebem só `clicks` e `conversations`.

## 6. Funil de volta à Meta (modo site)

- `metadata['meta_sync']['pixel_id']` por funil (só dígitos, até 20). Editado no painel do funil.
- `Crm::MetaCapi::DispatchJob#deliver`: com `ctwa_clid` → caminho atual, **inalterado**. Sem `ctwa_clid`, busca
  sinais do site (`Crm::MetaCapi::WebsiteSignalResolver`: clique mais recente com `meta_signals` presos às
  conversas do card). Sem sinais: card com clique de link `website` → `skip 'missing_signals'` (veio do site sem
  consentimento de marketing, ou clique inferido; motivo visível no card, CA-3.4); qualquer outro card →
  `skip 'missing_ctwa_clid'` (como hoje).
- Com sinais: `pixel_id` vazio → `skip 'missing_pixel'`; token da conexão WhatsApp ausente →
  `skip 'missing_credentials'`; evento sem equivalente → `skip 'no_meta_event'`; `event_time` com mais de 7 dias
  na hora do envio → `skip 'event_too_old'` (regra da Meta: o limite é contado do envio, não do clique).
- Evento: `action_source: 'system_generated'` (orientação da Meta para mudança de etapa de CRM), `event_id` do
  registro, `user_data` `{ fbc, fbp, client_ip_address, client_user_agent }`, `custom_data` igual ao modo CTWA.
  Destino `POST /{pixel_id}/events`.
- Mapa do modo site: `won → Purchase`; `lost` → não envia; etapa `lead` → não envia (a página já envia `Lead`
  na hora do formulário); `qualified → QualifiedLead` (evento personalizado no Pixel); `opportunity → AddToCart`;
  `negotiation → InitiateCheckout`.
- Linha do registro: `attribution_mode = 'website'`, `dataset_id = pixel_id`.

Permissão: a conexão do WhatsApp da conta 18 hoje **não** lê o Pixel `2164882667623689`
(`(#100) Missing Permission`, verificado em 05/10/2026). Antes de ligar, o marketing precisa dar ao usuário de sistema
da conexão acesso ao Pixel no Gerenciador de Negócios. Sem isso o envio cai em erro com a mensagem da Meta visível no
card.

## 7. Retenção do dado pessoal (LGPD)

`Ctwa::TrackedLinkClicksRetentionJob`, de hora em hora (`config/schedule.yml`). A linha do clique fica (conta na
tabela de campanhas); somem `lead_data`, `meta_signals` e `user_agent`:

- clique expirado (72h) sem conversa: na primeira execução depois de expirar;
- clique atribuído: 28 dias depois do clique. O formulário já está na conversa; os sinais servem ao envio à Meta, e a
  venda pode fechar semanas depois do clique (o limite de 7 dias da Meta conta do evento, não do clique).

## 8. Rollout

1. Deploy do Chat2You (aditivo; endpoint novo sem uso).
2. Criar a origem "LP Seguro Viagem" (modo site, `https://placement.com.br`) na caixa 38.
3. Deploy da página com `CHAT2YOU_ATTRIBUTION_ENABLED=false`, depois ligar com o código da origem.
4. Marketing cola `ad_url_params` nos anúncios.
5. Fase 3: preencher `pixel_id` no funil Viagem depois da permissão concedida.

Rollback: desligar `CHAT2YOU_ATTRIBUTION_ENABLED` na página (troca de variável + reinício do serviço, sem build).
No Chat2You, colunas novas são aditivas; voltar a imagem anterior não quebra nada.
