# Anúncios da Meta — F4: a IA no painel e o resumo no WhatsApp (#1100)

Base: F3 (`docs/crm/anuncios-meta-f3.md`). O painel e a ação do dia por regra (`Crm::MetaAds::Panel::Action`)
continuam sendo a fonte dos números. A F4 acrescenta duas coisas, e nenhuma delas manda mensagem sozinha para
cliente:

- **F4a.** "O que fazer hoje" escrito pela IA a partir dos números do painel, e uma mensagem sugerida para
  retomar cada proposta parada. A pessoa lê, edita e clica para enviar.
- **F4b.** Resumo diário no WhatsApp às 8h (Brasília) e alerta quando um anúncio gasta no dia sem trazer
  conversa (no máximo 1 por dia). A pessoa escolhe o número de origem entre os conectados da conta e informa o
  número que recebe. **Vem desligado.**

Regras que valem para os dois: só administrador (a mesma policy do painel, `Crm::MetaAdsConnection`); nenhuma
regex para entender texto de pessoa; telefone pela gem do projeto (`Autonomia::Prospecting::PhoneContract`);
IA sem troca de modelo; nenhum `<select>` nativo; Tailwind só; i18n en + pt_BR.

---

## 1. F4a — "O que fazer hoje" pela IA

### Quando roda

Ao abrir o painel (aba Resultado), a tela mostra **na hora** a ação por regra que já vem em `panel.action`, e
pede a versão da IA em paralelo (`POST daily_action`). Quando a resposta chega, o texto da IA entra no lugar do
texto da regra; os números exibidos continuam os da regra. O porquê da IA leva o rótulo fixo "Por quê:" da tela
(i18n `AI.DAILY.WHY_LABEL`), como o da regra; o modelo não escreve o rótulo.

Quando a regra achou propostas paradas (`panel.action.kind == 'stalled_quotes'`) e a IA escolheu outra ação
(`wait`, `review_ad`…), a tela mostra também o botão secundário "Ver as N propostas" (`data-panel-stalled-button`):
a lista e a mensagem sugerida nunca ficam sem caminho.

O servidor decide entre três caminhos, nesta ordem:

1. **Sem IA** (`Crm::Ai::Config.enabled?` falso, ou `Crm::Ai::CredentialResolver#configured?` falso):
   responde **200** na hora com `source: 'rule'` e o motivo. Não enfileira nada.
2. **Já existe resultado guardado** para a mesma conta, período, dia e assinatura dos números: responde
   **200** com ele. Não chama a IA.
3. **Não existe:** `defer_interactive_ai('meta_ads_daily_action', ...)` → **202** com `poll_url`. A tela usa
   `pollAiRequest`, que já aceita tanto 200 quanto 202.

### Onde fica guardado (Redis, sem tabela)

- Chave: `crm:meta_ads:daily_action:v1:<account_id>:<days>:<data no fuso da conta de anúncios>:<locale>:<assinatura>`.
- TTL: até o fim do dia no fuso da conta de anúncios, no mínimo 1 h.
- **Assinatura** = SHA256 do JSON canônico de: `action` da regra (sem `cards[].title`, com os `id`s), lista
  `[ad_id, verdict]` de cada anúncio, `totals.quotes`, `totals.open_quotes`, `totals.sales` e
  `confidence.conversations`/`confidence.ad`/`confidence.ad_name`. O gasto **não** entra: ele muda a cada 30 min
  e faria a IA rodar de novo a cada leitura. Proposta nova, venda nova, mudança de veredito ou de ação mudam a
  assinatura e geram texto novo.
- **Teto:** no máximo `DAILY_LIMIT = 6` gerações por conta por dia (contador Redis `INCR` com TTL de 36 h).
  Passou do teto: devolve o último resultado guardado do dia, se houver; senão a regra com `reason: 'daily_limit'`.
- Falha do provedor fica guardada 15 min com `source: 'rule', reason: 'ai_error'`, para não martelar o provedor.

### Entrada do modelo (só números)

`Crm::MetaAds::Panel::AiAction.new(connection:, report:, language:).perform`, onde `report` é
`Panel::Report.new(connection, days:).payload` **recalculado no servidor** (nunca vindo da tela):

```json
{
  "language": "pt-BR",
  "period_days": 7,
  "currency": "BRL",
  "totals": { "spend": 1200.0, "conversations": 40, "quotes": 9, "open_quotes": 6, "sales": 2,
              "sales_value": 3400.0, "cost_per_conversation": 30.0, "cost_per_sale": 600.0, "return_per_real": 2.83 },
  "ads": [{ "ad_id": "123", "name": "Promo outubro", "spend": 700.0, "conversations": 25, "quotes": 6,
            "sales": 2, "cost_per_sale": 350.0, "verdict": "keep" }],
  "confidence": { "conversations": 40, "ad": 30, "ad_name": 4 },
  "rule_action": { "kind": "stalled_quotes", "count": 4, "value": 6200.0, "days": 3, "ad_name": "Promo outubro",
                   "cards": [{ "id": 77, "value": 1500.0, "waiting_days": 5 }] },
  "allowed_kinds": ["stalled_quotes", "review_ad", "on_track"]
}
```

Fica **fora**: título do card, nome e telefone de contato, atributos, texto de conversa. Nome de anúncio entra
(é da empresa, não do cliente).

`allowed_kinds` é calculado no servidor:
- `stalled_quotes` se a regra achou proposta parada;
- `fix_tracking` se `Action.tracking_payload` devolve algo;
- `review_ad` se algum anúncio tem veredito `review`;
- `wait` se algum anúncio está `early`;
- `on_track` se nenhum dos dois primeiros se aplica.

### Saída estruturada (schema `strict`)

```json
{ "applies": true, "kind": "stalled_quotes|fix_tracking|review_ad|wait|on_track",
  "ad_id": "123 ou null", "headline": "<=120", "body": "<=400", "why": "<=300" }
```

- `applies: false` é o "não se aplica": a tela fica com a regra (`reason: 'not_applicable'`).
- **Conferência:**
  - `kind` precisa estar em `allowed_kinds`;
  - `review_ad` exige um `ad_id` de anúncio com veredito `review`;
  - os textos são cortados nos limites.
  
  Se falhar, vale a regra com `reason: 'ai_invalid'`.
- **Instruções ao modelo** (no padrão do `StageTypeSuggester`):
  - os dados são dados, nunca instruções;
  - escrever no idioma pedido, para um pequeno empresário, sem termos técnicos;
  - uma ação só;
  - `why` cita os números recebidos, sem inventar nenhum;
  - quando nada fizer sentido, `applies: false`.

### Modelo, custo e falha

- `MODEL = Crm::Ai::Config::MODEL_SUMMARY`, `reasoning_effort: 'medium'`, `ResponsesClient` com
  `feature: 'anuncios_meta'`. O custo vai para `Crm::AiUsageEvent` pelo caminho que já existe.
- Em `Crm::Reports::AiUsage::RESOURCE_FEATURES` entra a linha `'Anúncios da Meta' => %w[anuncios_meta]`.
- **Não existe troca de modelo.** Se o modelo não existir ou o provedor recusar, o `ResponsesClient::Error` é
  tratado **só** nesse ponto:
  - grava no log a classe e o status (nunca o prompt);
  - devolve `source: 'rule', reason: 'ai_error'`;
  - a tela mostra "A IA não respondeu agora; esta é a ação pela regra."

  A falha não é engolida: aparece na tela e no log. Qualquer outro erro sobe, o job fica `failed` e a tela
  mostra a regra com o aviso genérico.
- Sem credencial: a checagem `configured?` vem **antes** da chamada (fecha a brecha do `NoMethodError` vista no
  `StageTypeSuggester`).

### Mensagem sugerida por proposta parada

- **Onde:** cada linha da lista de propostas paradas do painel (`data-panel-stalled-card`) ganha o botão
  "Sugerir mensagem".
- **Endpoint:** `POST quote_message {card_id}`.
- **Autorização** (na `InteractiveOperation`, operação `meta_ads_quote_message`):
  - o mesmo administrador do painel;
  - `authorize_conversation!` na conversa principal do card;
  - o card precisa estar em `Panel::Action.stalled` **recalculado** sobre a coorte de 30 dias da conexão.
    Não se confia no `card_id` da tela; fora da lista → 422 `card_not_stalled`.
- **Antes da IA:**
  - IA desligada ou sem credencial → 200 `applies: false, reason: 'ai_unavailable' | 'credentials_missing'`;
  - `Crm::FollowUps::MessagingWindow#requires_template?` → 200 `applies: false, reason: 'window_closed'`,
    **sem chamar a IA** (no Oficial, texto livre fora das 24 h falha).
- **Entrada:** de `Crm::Ai::ContextBuilder.new(card:).perform`, só `recent_messages`, `conversation_state` e
  `temporal`, mais o nome da etapa, o valor, os dias esperando e o idioma. Ficam fora `known_attributes`, o
  título do card, o telefone e o e-mail.
- **Serviço:** `Crm::MetaAds::QuoteMessageSuggester.new(card:, language:).perform`. Mesmo modelo, mesma feature
  `anuncios_meta`.
- **Schema `strict`:**

  ```json
  { "applies": true, "reason": "closed|declined|nothing_open|none", "message": "<=700", "source_quote": "trecho literal",
    "includes_outside_contact": false }
  ```

- **Conferência:** `source_quote` precisa aparecer literalmente (`String#include?`, sem regex) no `content` de
  alguma mensagem enviada ao modelo. Se não aparecer, `applies: false, reason: 'ai_invalid'`. Mensagem vazia com
  `applies: true` também vira `ai_invalid`.
- **Link, chave ou contato plantado:** a mensagem do cliente é texto não confiável e poderia levar a IA a repetir
  um link, chave PIX, conta, telefone ou e-mail de terceiro. As instruções proíbem isso, e quem confere é o
  próprio modelo: ele declara `includes_outside_contact`. `true` (ou ausente) → `applies: false,
  reason: 'unsafe_content'`, e a tela pede que a pessoa escreva a mensagem dela. Nenhuma regex.
- **Sem cache:** é sob demanda, um clique por card.
- **Na tela:**
  1. "Sugerir mensagem" mostra "Escrevendo…".
  2. Aparece a caixa de texto editável com a sugestão e a frase de origem ("Porque o cliente disse: …").
  3. Botões "Enviar na conversa" (clique explícito; `MessageApi.create({ conversationId, message })`, a API
     padrão), "Copiar" e "Abrir conversa".
  4. `applies: false` mostra o motivo em palavras e só "Abrir conversa".
  5. O envio confirma com alerta. A tela não reenvia sozinha.
  6. A caixa de texto tem altura de revisão (`!h-auto min-h-40 sm:min-h-32`, 6 linhas): a regra global
     `textarea { h-16 }` cortava a mensagem em 2 linhas.
  7. Fechar e reabrir a lista de paradas não apaga o estado de cada card (rascunho, "Enviada"): a lista fica
     montada e só some com `v-show`.
  8. "Copiar" negado pelo navegador avisa "Não deu para copiar…" (`AI.QUOTE.COPY_FAILED`).

---

## 2. F4b — resumo e alerta no WhatsApp

### Configuração: **exige migration** (só tabela do fork)

`crm_meta_ads_connections` ganha duas colunas:

| Coluna | Tipo | Por quê |
|---|---|---|
| `whatsapp_report` | `jsonb`, `default: {}`, `null: false` | `{ enabled, alert_enabled, inbox_id, last_summary_at, last_alert_at, last_error, last_error_at }` |
| `whatsapp_report_phone` | `string` | número de destino em E.164. `encrypts :whatsapp_report_phone if Chatwoot.encryption_configured?`, como em `Channel::Whatsapp`. Fica fora do jsonb porque `encrypts` não cifra chave de jsonb |

`enabled` e `alert_enabled` valem `false` por padrão. Nenhuma coluna em tabela do Chatwoot.

### Número de destino

- Validação: `Autonomia::Prospecting::PhoneContract.parse(raw, region: <país da conta ou 'BR'>)`. `nil` → 422
  `invalid_phone`.
- Grava `e164`. No log aparece só com `CampaignImports::PhoneMask.mask`.
- Um número por conta.

### Número de origem: só os conectados da conta

O serviço `Crm::MetaAds::WhatsappReport::Origins.new(account).list` monta a lista:

| Tipo | Entra quando | Envio |
|---|---|---|
| `waha` | `Channel::Api` com `waha_provider?` e sessão `WORKING` (pelo mesmo `Waha::Client#get_session`/`STATUS_MAP` da tela de caixas) | texto livre |
| `whatsapp_cloud` (inclui o Híbrido) | `Channel::Whatsapp`, `provider == 'whatsapp_cloud'`, sem `reauthorization_required?` | **só modelo aprovado** |

360dialog e Twilio ficam fora. No `PATCH`, `inbox_id` fora da lista → 422 `inbox_not_connected`. Na hora do
envio, a conexão é conferida de novo.

### Envio: sem criar contato nem conversa

- **WAHA:**
  - `check_contact_exists(phone:, session:)`, que resolve o nono dígito; `numberExists` falso → `whatsapp_number_not_found`;
  - `new_message_id(session)`;
  - `send_text(session:, chat_id:, text:, id:)`.
  - `Waha::Client::Timeout` → `send_uncertain`, **nunca reenvia**. `Waha::Client::Error` → `send_failed`.
  - No log vai só a classe do erro, porque a URL leva o número.
- **Oficial:**
  - `channel.send_template(digits, { name:, namespace:, lang_code: 'pt_BR', parameters: }, nil)`;
  - **antes**, confere em `channel.message_templates` que existe o modelo com o nome exato, idioma `pt_BR` e
    `status == 'APPROVED'`; sem isso → `template_not_approved` e não envia;
  - retorno `nil` → `send_failed` (o detalhe fica no log do provedor).
- **Sem contato nem conversa** (recomendação da descoberta): o destinatário é o dono, não um cliente, e criar
  conversa dispararia agente, automação e follow-up.
- A tela avisa: "Se você responder a mensagem, ela aparece como conversa nessa caixa."
- **A verificar em homologação:** se o conector do WAHA espelha no Chatwoot a mensagem enviada pelo próprio
  número. Até essa verificação, a doc não promete "sem conversa" no WAHA.

### Modelos do Oficial (o fork **não** submete à Meta)

A tela mostra o texto exato para a pessoa criar no Gerenciador do WhatsApp (categoria UTILITY, idioma pt_BR) e o
status lido de `message_templates`: `approved`, `pending`, `rejected` ou `missing`.

A Meta recusa (ou não aprova) modelo que começa ou termina com variável, ou que tem variável demais para o tamanho
do texto. Por isso o resumo tem texto fixo antes e depois e só 4 variáveis: `{{3}}` junta conversas, propostas e
vendas numa frase ("8 conversas, 3 propostas e 1 venda", plural pelo i18n `meta_ads_whatsapp_report.template.*`).
A Meta também recusa variável com quebra de linha, tab ou mais de 4 espaços seguidos (erro 132018): o
`MessageBuilder#body` junta os espaços de toda variável (`split.join(' ')`, sem regex), inclusive o nome do
anúncio, que é texto livre vindo da Meta.

**`chat2you_resumo_anuncios`**
> Olá! Este é o resumo diário dos seus anúncios na Meta, referente a {{1}}. Investimento: {{2}}. Resultado: {{3}}. O que fazer hoje: {{4}} Os detalhes de cada anúncio estão no painel de Anúncios da Meta.

Exemplo das variáveis: `{{1}}` = `06/10` (no teste, `06/10 [Teste]`), `{{2}}` = `R$ 120,00`,
`{{3}}` = `8 conversas, 3 propostas e 1 venda`, `{{4}}` = `Retome as 4 propostas paradas há mais de 3 dias (R$ 6.200,00).`

**`chat2you_alerta_anuncio`**
> Atenção: o anúncio {{1}} gastou {{2}} hoje e ainda não trouxe nenhuma conversa. Vale conferir no painel de Anúncios da Meta.

`PATCH` com `enabled: true` numa origem Oficial sem o modelo de resumo aprovado → 422 `template_not_approved`.
O mesmo vale para `alert_enabled: true` sem o modelo de alerta.

### Quando sai (cron em UTC; o Brasil não tem horário de verão)

| Job (`config/schedule.yml`) | cron | O quê |
|---|---|---|
| `crm_meta_ads_whatsapp_summary_job` | `0 11 * * *` (8h Brasília) | `Crm::MetaAds::WhatsappReport::ScheduleJob` com args `['summary']` |
| `crm_meta_ads_whatsapp_alert_job` | `30 19 * * *` (16h30 Brasília) | o mesmo job, args `['alert']` |

- O `ScheduleJob` (fila `scheduled_jobs`) passa por cada conexão ativa com conta de anúncios, `meta_ads_hub`
  ligado e o tipo ligado no jsonb, e enfileira `Crm::MetaAds::WhatsappReport::DeliverJob.perform_later(connection_id, kind)`
  na fila `low`.
- Nenhum método do job leva nome da API do ActiveJob. Os dois jobs passam no `spec/configs/schedule_spec.rb`.
- **No máximo 1 de cada por dia:** antes de enviar, `Redis SET NX EX 36h` na chave
  `crm:meta_ads:whatsapp_report:<account_id>:<kind>:<data no fuso da conta de anúncios>`.
  - Não conseguiu a chave → não envia.
  - Falha clara (`send_failed`, `template_not_approved`, `inbox_not_connected`) apaga a chave e grava `last_error`;
    a rodada seguinte é só no outro dia, porque o cron é diário.
  - `send_uncertain` **mantém** a chave.
  - Sucesso grava `last_summary_at` ou `last_alert_at`.

### Conteúdo (pt_BR; en no `config/locales`)

Os números do resumo saem de `Crm::MetaAds::WhatsappReport::Digest`:
- de **ontem**, no fuso da conta de anúncios: gasto de `crm_meta_ad_insights_daily` (`date = ontem`) e conversas,
  propostas e vendas da `Panel::Cohort` com o intervalo de ontem;
- o melhor anúncio de ontem, por conversas;
- "o que fazer hoje": **sempre** a frase da regra (`Report.new(days: 7).payload[:action]`) em i18n de servidor.
  O resumo não usa o texto da IA (F4a): ele só existe depois que alguém abre o painel no dia, no período e no
  idioma de quem abriu, e às 8h quase nunca haveria um; o resumo também não chama a IA sozinho (custo diário por
  conta). Se o dono quiser o texto da IA no WhatsApp, é decisão nova: gerar no job às 8h, com custo.

Valores com `number_to_currency` na moeda da conta.

**Resumo (WAHA, texto livre):**
```
Anúncios da Meta — ontem, 06/10
Investido: R$ 120,00
Conversas: 8 (R$ 15,00 por conversa)
Propostas: 3 · Vendas: 1 (R$ 900,00)
Melhor anúncio: Promo outubro, com 5 conversas
O que fazer hoje: Retome as 4 propostas paradas há mais de 3 dias (R$ 6.200,00).
Ver o painel: <FRONTEND_URL>/app/accounts/<id>/campaigns/meta-ads?aba=resultado
```
- Ontem sem gasto e sem conversa: **não envia** e grava `last_error: 'nothing_to_report'` (informativo).
- Sem venda: a linha das vendas mostra "Vendas: 0".
- Sem melhor anúncio: a linha sai.

**Alerta (WAHA):**
```
Atenção: o anúncio Promo outubro gastou R$ 45,00 hoje e ainda não trouxe nenhuma conversa.
Vale conferir se ele leva para o WhatsApp certo. Ver o painel: <link>
```

**Regra do alerta** (`Crm::MetaAds::WhatsappReport::SpendAlert`):
- entra o anúncio com gasto **hoje** maior ou igual a `ALERT_SPEND_FACTOR = 2` vezes o custo por conversa da conta
  nos últimos 30 dias (`Report.new(days: 30)` → `totals.cost_per_conversation`) e zero conversas hoje;
- se a conta não tem custo por conversa, o piso é `ALERT_MIN_SPEND = 30` na moeda da conta;
- havendo mais de um, vai o de maior gasto. Uma mensagem só.

No Oficial, os mesmos números vão nas variáveis do modelo, em uma linha.

### "Enviar teste"

`POST whatsapp_report/test`:
- monta o resumo de ontem e envia **agora**, com o prefixo "[Teste]" (no Oficial, pelo modelo de resumo);
- não usa nem grava a trava diária;
- teto de 3 por hora por conta (Redis) → 429 `rate_limited`;
- envio síncrono, porque a pessoa espera a confirmação;
- só envia com origem e destino salvos (não testa rascunho).
- com o botão bloqueado, a tela diz o motivo certo: falta salvar os números (`TEST_NEEDS_SAVE`), o número que envia
  desconectou (`TEST_NEEDS_ORIGIN`) ou há mudança não salva (`TEST_NEEDS_SAVE_CHANGES`); "Descartar mudanças"
  volta a tela para o que está salvo (por exemplo, depois de um Salvar recusado com `template_not_approved`).

---

## 3. Contratos de API (seguir à risca)

Base: `/api/v1/accounts/:account_id/crm/meta_ads_connection`.
- Administrador: a policy `Crm::MetaAdsConnection`; leitura com `show?` e escrita com `update?`.
- Agente recebe **403** `{ "error": "forbidden" }`.
- Erros de regra: **422** `{ "error": "<code>" }`, no formato do `render_unprocessable` atual.
- Conta sempre pela `Current.account`.

### F4a — controller `Api::V1::Accounts::Crm::MetaAdsAiController` (novo, do construtor A)

**`POST /daily_action`** · body `{ "days": 7|30 }`. Policy `show?`.
- Sem conexão ou sem `ad_account_id` → 200 `{ "daily_action": null }`.
- Sem IA ou resultado guardado → 200 `{ "daily_action": DailyAction }`.
- Senão → 202 `{ "id", "status": "pending", "poll_url" }`. O resultado `done` é `{ "daily_action": DailyAction }`.

```
DailyAction = {
  "source": "ai" | "rule",
  "reason": null | "ai_unavailable" | "credentials_missing" | "not_applicable" | "ai_invalid" | "ai_error" | "daily_limit",
  "kind": "stalled_quotes" | "fix_tracking" | "review_ad" | "wait" | "on_track" | "no_data",
  "ad_id": string | null,
  "headline": string | null, "body": string | null, "why": string | null,   // só com source "ai"
  "days": 7 | 30,
  "generated_at": ISO8601
}
```
`source: 'rule'` vem com `kind` igual ao `panel.action.kind`, e a tela usa o texto i18n que já existe.

**`POST /quote_message`** · body `{ "card_id": 77 }`. Policy `show?` + conversa.
- 422: `card_not_found`, `card_not_stalled`.
- 200 imediato `{ "quote_message": QuoteMessage }` com `applies: false` quando `window_closed`, `ai_unavailable`
  ou `credentials_missing`.
- Senão → 202 com `poll_url`. O `done` é `{ "quote_message": QuoteMessage }`.

```
QuoteMessage = {
  "card_id": 77, "conversation_id": 901,
  "applies": boolean,
  "reason": null | "closed" | "declined" | "nothing_open" | "window_closed" | "ai_unavailable" | "credentials_missing" | "ai_invalid" | "ai_error",
  "message": string | null,        // <= 700
  "source_quote": string | null
}
```

Operações novas na `Crm::Ai::InteractiveOperation`: `meta_ads_daily_action`, com inputs `{days, language}` e
autorização `authorize_meta_ads_panel!` (flags de CRM e IA + `MetaAdsConnection :show?`); e
`meta_ads_quote_message`, com inputs `{card_id, language}`, autorização `authorize_meta_ads_panel!` +
`authorize_conversation!` e o card na lista de paradas.

### F4b — controller `Api::V1::Accounts::Crm::MetaAdsWhatsappReportsController` (novo, do construtor B)

**`GET /whatsapp_report`** (policy `show?`) → 200:
```json
{ "whatsapp_report": {
    "enabled": false, "alert_enabled": false,
    "inbox_id": null, "phone": null,
    "last_summary_at": null, "last_alert_at": null, "last_error": null, "last_error_at": null,
    "origins": [
      { "inbox_id": 5, "name": "Vendas", "phone_number": "+5511999990000", "kind": "waha",
        "templates": null },
      { "inbox_id": 9, "name": "Oficial", "phone_number": "+5511888880000", "kind": "whatsapp_cloud",
        "templates": { "summary": "approved|pending|rejected|missing", "alert": "approved|pending|rejected|missing" } }
    ],
    "template_texts": { "summary": { "name": "chat2you_resumo_anuncios", "body": "..." },
                        "alert":   { "name": "chat2you_alerta_anuncio",  "body": "..." } },
    "schedule": { "summary_local_time": "08:00", "alert_local_time": "16:30", "time_zone": "America/Sao_Paulo" }
} }
```
- Sem conexão: `{ "whatsapp_report": null }`.
- `origins` traz só os conectados.
- `phone` em E.164; a tela é do administrador.
- `template_texts.*.body` sai do i18n de servidor no locale da requisição.

**`PATCH /whatsapp_report`** (policy `update?`) · body
`{ "whatsapp_report": { "enabled": bool, "alert_enabled": bool, "inbox_id": int|null, "phone": "texto livre" } }`
(chaves ausentes ficam como estão) → 200, no mesmo formato do GET.
- 422:
  - `not_connected`;
  - `invalid_phone`;
  - `inbox_not_connected` (inclui inbox de outra conta);
  - `template_not_approved`;
  - `origin_required` e `phone_required` (só ao ligar `enabled` ou `alert_enabled` sem os dois).

Desligar sempre funciona, mesmo sem origem: só se confere o que o pedido liga ou troca enquanto algum tipo fica
ligado — o tipo que acende (origem conectada + modelo dele no Oficial), a troca de origem (todos os tipos ligados)
ou a troca de destino (número válido). Desligar só o resumo com a sessão WAHA caída passa.

Gravação sem perder mudança: a tela e o envio gravam só as chaves que mudaram, sobre a linha relida sob lock
(`with_lock`). O envio (que grava `last_*_at`/`last_error`) não desfaz um "desligar" ou uma troca de origem feitos
enquanto ele rodava, e vice-versa.

**`POST /whatsapp_report/test`** (policy `update?`) → 200 `{ "sent": true, "sent_at": ISO8601 }`.
- 422:
  - `not_connected`, `origin_required`, `phone_required`, `inbox_not_connected`;
  - `template_not_approved`, `whatsapp_number_not_found`;
  - `send_failed`, `send_uncertain`.
- 429 `{ "error": "rate_limited" }`.

### Rotas (`config/routes.rb`, só o construtor B mexe)

Dentro do `namespace :crm`, logo depois do bloco `resource :meta_ads_connection`, um escopo com caminho
explícito:

- `/crm/meta_ads_connection/daily_action` → `crm/meta_ads_ai#daily_action`
- `/crm/meta_ads_connection/quote_message` → `crm/meta_ads_ai#quote_message`
- `GET` e `PATCH /crm/meta_ads_connection/whatsapp_report` → `crm/meta_ads_whatsapp_reports#show` e `#update`
- `POST /crm/meta_ads_connection/whatsapp_report/test` → `crm/meta_ads_whatsapp_reports#test_send`

A ação se chama `test_send`, não `test`.

### API JS

- **A**, no fim de `app/javascript/dashboard/api/crmMetaAdsConnection.js`:
  - `dailyAction(days)` = `pollAiRequest(axios.post(\`${this.url}/daily_action\`, { days }))`;
  - `quoteMessage(cardId)` = `pollAiRequest(axios.post(\`${this.url}/quote_message\`, { card_id: cardId }))`.
- **C**, em arquivo novo `app/javascript/dashboard/api/crmMetaAdsWhatsappReport.js`, classe `ApiClient` com a
  base `crm/meta_ads_connection/whatsapp_report`, `accountScoped`:
  - `get()`;
  - `update(payload)`, que manda `PATCH { whatsapp_report: payload }`;
  - `sendTest()`, que manda `POST .../test`.

---

## 4. Divisão entre os 3 construtores (sem sobreposição)

| | A — F4a inteira | B — F4b backend | C — F4b tela |
|---|---|---|---|
| Cria | `app/controllers/api/v1/accounts/crm/meta_ads_ai_controller.rb`; `app/services/crm/meta_ads/panel/ai_action.rb`; `app/services/crm/meta_ads/panel/ai_action_cache.rb`; `app/services/crm/meta_ads/quote_message_suggester.rb`; `components/MetaAdsDailyAction.vue`; `components/MetaAdsQuoteMessage.vue`; specs: `spec/services/crm/meta_ads/panel/ai_action_spec.rb`, `spec/services/crm/meta_ads/quote_message_suggester_spec.rb`, `spec/requests/api/v1/accounts/crm/meta_ads_ai_spec.rb`, `metaAds/specs/MetaAdsDailyAction.spec.js`, `metaAds/specs/MetaAdsQuoteMessage.spec.js` | `db/migrate/<ts>_add_whatsapp_report_to_crm_meta_ads_connections.rb`; `app/controllers/api/v1/accounts/crm/meta_ads_whatsapp_reports_controller.rb`; `app/services/crm/meta_ads/whatsapp_report/{origins,settings,digest,spend_alert,message_builder,sender,template_status}.rb`; `app/jobs/crm/meta_ads/whatsapp_report/{schedule_job,deliver_job}.rb`; `config/locales/meta_ads_whatsapp_report.en.yml` e `.pt_BR.yml`; specs em `spec/services/crm/meta_ads/whatsapp_report/`, `spec/jobs/crm/meta_ads/whatsapp_report/` e `spec/requests/api/v1/accounts/crm/meta_ads_whatsapp_report_spec.rb` | `components/MetaAdsWhatsappReport.vue` (ChoiceSelect para a origem, campo de telefone, 2 interruptores, status do modelo, texto dos modelos com "Copiar", "Enviar teste", aviso de que responder vira conversa); `app/javascript/dashboard/api/crmMetaAdsWhatsappReport.js`; `metaAds/specs/MetaAdsWhatsappReport.spec.js` |
| Altera (exclusivo) | `app/services/crm/ai/interactive_operation.rb` (2 operações + `authorize_meta_ads_panel!`); `app/services/crm/reports/ai_usage.rb` (1 linha); `components/MetaAdsPanel.vue` (monta a ação da IA e o botão por card parado) | `config/routes.rb` (todas as rotas da F4, **inclusive as de A**, logo no primeiro passo); `config/schedule.yml`; `db/schema.rb` (só as 2 colunas); `app/models/crm/meta_ads_connection.rb` (`encrypts`, defaults, leitura do jsonb) | `components/MetaAdsSummary.vue` (monta a seção na aba Conexão, abaixo do resumo) |
| Compartilhado | `crm.json` en + pt_BR: só chaves sob `CRM_KANBAN.META_ADS_HUB.AI.*`; `crmMetaAdsConnection.js`: os 2 métodos no fim | nenhum arquivo do front | `crm.json` en + pt_BR: só `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.*` |

**Como evitar conflito:**
- Ninguém mexe em `meta_ads_connections_controller.rb`.
- **B** põe as rotas de A e as suas no `routes.rb` como primeira tarefa, para A testar os request specs.
- Em `crm.json`, cada um insere seu bloco como **última chave de `META_ADS_HUB`**, com `Edit` sobre uma âncora
  única, **relendo o arquivo imediatamente antes**. Nada de reescrever o arquivo inteiro. O segundo a escrever
  ajusta a vírgula do bloco do primeiro.
- `MetaAdsPanel.vue` é só de A e `MetaAdsSummary.vue` é só de C.
- **Integração** (orquestrador, no fim): `pnpm i18n:fork:check`, `pnpm guia:check` (sem tela nova; se a trava
  pedir explicação, um bloco em `lib/operator_guide/porques.md` para a seção da Conexão), `rails autonomia:guia:formatos`
  e `:check` (os controllers novos mudam o gerado), rubocop, rspec e vitest de tudo, prettier e o lint de
  e-mail/i18n.
- Todas as specs usam `travel_to` com data fixa e stub de IA (`instance_double` do `CredentialResolver` e do
  `ResponsesClient`), de WAHA (`Waha::Client`) e de `send_template`. Nenhuma chamada real.

**Estilo da tela (A e C):**
- números e títulos com `font-interDisplay font-520 tracking-[-0.02em]`;
- rótulos de seção com `text-xs font-520 uppercase tracking-[0.08em]`;
- seções com `rounded-xl border border-solid border-n-weak bg-n-solid-1`;
- alvos com `min-h-11`;
- pesos 420, 440 e 520;
- plural com `$t(key, named, count)`.

---

## 5. Fora de escopo e riscos

**Fora:**
- criar ou submeter modelo na Meta;
- escolher modelo de mensagem para propostas fora da janela (a F4a só oferece "Abrir conversa");
- envio pelo servidor da mensagem sugerida;
- mais de um número de destino;
- 360dialog e Twilio;
- "parar" respondendo no WhatsApp;
- resumo semanal;
- remapear o `classify` do `suggest_stages` na Gestão IA.

**Riscos:**
1. **Espelho do WAHA:** se o conector espelhar o envio, o resumo vira conversa na caixa. Verificar em homologação
   antes de ligar para clientes.
2. **Número de terceiro:** o número é digitado livre. Mitigações: só administrador, vem desligado, um número por
   conta, "Enviar teste" e no máximo 2 mensagens por dia.
3. **Bloqueio do número WAHA:** a sessão não é oficial. Mitigações: 2 mensagens por dia, sessão conferida antes
   de enviar e nunca reenviar depois de `Timeout`.
4. **Oficial:** sem o modelo aprovado, nada sai, e a tela diz isso; o envio nunca troca para texto livre. A Meta
   pode reclassificar o modelo como MARKETING e cada envio é cobrado.
5. **Custo da IA:** a assinatura sem o gasto e o teto de 6 por dia seguram. Se o custo crescer, baixar o teto.
6. **IA falha:** a tela fica com a regra e mostra o aviso. O modelo não é trocado.
7. **Dados pessoais:**
   - a ação do dia só vê números;
   - a mensagem sugerida vê as mensagens da conversa, tratadas como dados e sem atributos, telefone ou e-mail;
   - o telefone de destino é cifrado quando a cifra está configurada e mascarado no log.
8. **Migration** em tabela do fork: aditiva, com default, sem backfill. O rollback é `remove_column` das duas.
