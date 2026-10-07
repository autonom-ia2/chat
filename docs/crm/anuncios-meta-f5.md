# Anúncios da Meta — F5: o consultor de tráfego completo (#1110)

Base: F3 (`docs/crm/anuncios-meta-f3.md`) e F4 (`docs/crm/anuncios-meta-f4.md`). PRD: seção 4 (CA-3.2, CA-3.5,
CA-4.1, CA-4.2, CA-4.5), seção 5 (regras de gestor) e seção 6 (runs e ações: "quem abriu, quem aceitou"). Branch
`feat/1110-anuncios-meta-f5`, empilhada sobre a F4 (#1109).

A F5 troca a ação única da F4 pelo consultor do PRD, em cinco camadas: **o código calcula, as regras decidem, o
LLM só escreve, a checagem confere**. Também fecha três pedaços que ficaram da F3: o número da Meta em "Quanto
confiar", o tempo de resposta e o caminho do dinheiro clicável.

Regras que valem para tudo:
- só administrador, pela policy `Crm::MetaAdsConnection`;
- construção aditiva: tabelas e arquivos do fork, nenhuma coluna em tabela do Chatwoot, nenhuma associação nova
  em model upstream (`Account` não ganha `has_many`);
- nenhuma regex para entender texto de pessoa (a checagem do CA-4.2 usa métodos de string, ver §1.5);
- sem troca de modelo de IA: `Crm::Ai::Config::MODEL_SUMMARY` com `SUMMARY_REASONING_EFFORT`, feature
  `anuncios_meta`;
- sem `<select>` nativo, Tailwind só, i18n en + pt_BR;
- produção só leitura (psql pela SSM).

Revisão 1 (07/10): incorpora a crítica de 32 pontos. O mapa ponto → seção está no fim, junto com a parte
rejeitada.

---

## 0. Decisões desta fase

| # | Decisão | Por quê |
|---|---|---|
| D5.1 | **Nenhum número sai do LLM.** O modelo escreve com marcadores `{{fato}}` e o servidor põe os valores. | É a D4 do PRD ao pé da letra. Com marcadores, não há tolerância de arredondamento: o número exibido é o do fato, formatado pelo servidor. A alternativa (`cited_numbers` declarado pelo modelo) não impede o texto de citar um número fora da lista. Prazos fixos do texto ("7 dias", "2 semanas", "3 dias") também são fatos da ação (§2). |
| D5.2 | **O consultor não depende do período da tela.** Analisa sempre 30 dias (coorte) e 7 dias contra a linha de base (sinais da Meta). | "O que fazer hoje" é sobre hoje. Assim o painel em 7 ou 30 dias e o resumo das 8h dizem a mesma coisa, e o aceite não se divide por período. |
| D5.3 | **Custo-alvo = custo por venda médio dos anúncios que venderam** (`Report#average_cost_per_sale`, 30 dias). Sem campo novo. | É a mesma base do veredito da F3; mudar só no consultor faria o veredito e a ação discordarem. Limite conhecido e mostrado na evidência: com um único anúncio vendendo, ele é a própria média, o veredito `up` sai sempre e o portão de dados equivale a "3 vendas ou mais". Alternativas na pergunta 5 (§9). |
| D5.4 | **Frequência de 7 dias por uma leitura nova da Meta** (sem `time_increment`), gravada em tabela do fork. A leitura é **opcional**: a falha dela nunca muda o estado da conexão. | Alcance não soma entre dias: a frequência diária não dá a de 7 dias. Sem isso, a fadiga por frequência e a escala ficam sempre `no_data`. Custa 1 chamada por conta por dia, às 4h. |
| D5.5 | **Aprendizado bloqueia só a escala**, e vira `no_data` quando o conjunto não tem conversa contada pela Meta. | A aproximação (menos de 50 conversas iniciadas, pela contagem da Meta, em 7 dias por conjunto) bloquearia para sempre toda conta pequena se valesse para a revisão. Conta só de site não tem essa contagem, por isso `no_data` e não `fail`. **Consequência:** na Placement (cerca de 46 conversas em 30 dias) nenhum conjunto chega a 50 em 7 dias, e a escala não aparece. Pergunta 4. |
| D5.6 | **Tempo de resposta = qualquer resposta** (pessoa ou agente da plataforma), **mediana**, só conversas de anúncio, a partir do **primeiro toque** da conversa. Calculado de `messages`. | O que muda a conversão é o cliente ser respondido. `first_reply_created_at` e `first_response` não servem no WAHA de conversa única; `reply_time` não vê os agentes Autonom.ia. A mediana não deixa uma conversa respondida no dia seguinte distorcer o número. Consequência: em conta com agente, a mediana fica em segundos e `slow_response` só dispara pela parte sem resposta. Pergunta 1. |
| D5.7 | **Caminho do dinheiro abre listas dentro do painel**, e cada linha leva à conversa e ao card no CRM (`crm_kanban_index?card_id=`). | O Kanban não filtra por coorte de anúncio, escopa por funil e só mostra ganho na Lista. A coorte cruza funis. `?card_id=` já abre a gaveta e alinha o funil (`CrmKanbanPage.vue` `openRouteCardIfNeeded`). **O CA-3.2 fica parcial** ("abre a lista filtrada no CRM"): o PR diz isso. Pergunta 9. |
| D5.8 | **"Quanto confiar" segue o período do painel** (7 ou 30). A linha Meta × nós compara **até ontem**. | Para comparar com a Meta é preciso o mesmo período, e o gasto de hoje é parcial (lido a cada 30 min) enquanto os links entram na hora. A aba Conexão (`MetaAdsSummary`) continua com 30. |
| D5.9 | **Abrir ≠ aceitar.** O botão principal leva ao trabalho e grava `opened_at`. Aceitar é gesto explícito ("Feito"). "Dispensar" dispensa. | O PRD §6 separa "quem abriu, quem aceitou". Contar a abertura como aceite deixaria a meta "aceita ≥ 4 de 5" falsa. "Feito" e "Dispensar" são links discretos: a ação principal continua uma só. Pergunta 2. |
| D5.10 | **Ação aceita fica na lista do dia, marcada "Feita".** Só a dispensada sai. | Se a aceita sumisse, a lista que a pessoa está usando (ex.: as propostas paradas) desapareceria no próximo refresh (2 min), e a vaga iria para outra ação, com nova chamada à IA. |
| D5.11 | **Aceite pelo Guia não entra na métrica.** O controller grava `opened_via`/`resolved_via` (`panel` ou `api`); a métrica conta só `panel`. | O catálogo do Guia (`Autonomia::Guide::Acoes#catalogo`) inclui todo POST do roteador, e não há lista de exclusão. O Guia chama pela porta da frente com `HTTP_API_ACCESS_TOKEN` (`Autonomia::Guide::ChamadaInterna`), o que distingue a origem sem mecanismo novo. Pergunta 3. |

Perguntas para o Rodrigo estão em §9. O desenho segue as recomendações; se ele mudar alguma, a mudança fica no
arquivo indicado lá.

---

## 1. Arquitetura do consultor

```
Facts (código, cache 5 min) → Rules (pass/fail/no_data/not_applicable + evidência) → Decision (até 3 ações)
      → Store (crm_meta_advisor_runs / _actions) → Writer (LLM, marcadores) → Check (CA-4.2) → Advice (API)
```

Tudo em `app/services/crm/meta_ads/advisor/`. Sem IA, o caminho para em `Decision` e a tela usa o texto i18n de
cada tipo. Constante `RULES_VERSION = 'f5.1'` em `Advisor::Rules`. Mudou limiar, prioridade ou gabarito? Sobe a
versão e explica no PR (§6).

### 1.1 Janelas (no fuso da conta de anúncios, `Report#zone`)

Hoje = `local_date`; ontem = `local_date − 1`. Exemplo com `local_date = 2026-10-07`.

| Nome | Dias | Exemplo | Uso |
|---|---|---|---|
| `cohort30` | hoje − 29 … agora | 08/09 … agora | `Panel::Report.new(connection, days: 30)`: conversas, propostas, vendas, veredito, média; `ResponseTime` |
| `recent7` | ontem − 6 … ontem | 30/09 … 06/10 | CTR, CPM, impressões, gasto recente, conversas da Meta por conjunto |
| `baseline` | ontem − 27 … ontem − 7 | 09/09 … 29/09 | linha de base da conta e do anúncio |
| `weekA` / `weekB` | ontem − 13 … ontem − 7 / ontem − 20 … ontem − 14 | 23/09 … 29/09 / 16/09 … 22/09 | custo por venda por semana **madura** (escala). A semana mais recente fica fora porque as vendas dela ainda estão chegando (CA-3.6) |
| `freq7` | a linha mais recente de `crm_meta_ad_frequency_windows` com `window_days = 7` e `date_end ≥ ontem − 1` | `date_end` 05/10 ou 06/10 | frequência real de 7 dias; o `date_end` vai na evidência |

### 1.2 Facts — `Crm::MetaAds::Advisor::Facts.new(connection, now: Time.current).payload`

Só números, ids, datas e nome de anúncio. Nunca título de card, contato ou texto de conversa. O payload é
JSON puro (datas em ISO 8601), para caber no cache.

```ruby
{
  local_date: '2026-10-07',
  currency: 'BRL',
  account: {
    spend_30d:, conversations_30d:, quotes_30d:, open_quotes:, sales_30d:, cost_per_conversation_30d:,
    target_cost_per_sale:,              # Report#average_cost_per_sale (D5.3); nil sem venda
    selling_ads:,                       # quantos anúncios entraram na média (evidência do D5.3)
    impressions_recent:, impressions_baseline:, link_clicks_recent:, link_clicks_baseline:,
    spend_recent:, spend_baseline:,
    ctr_recent:, ctr_baseline:,         # link_clicks / impressions; nil se impressões = 0
    cpm_recent:, cpm_baseline:,         # spend / impressions * 1000; nil se impressões = 0
    confidence: { conversations:, ad:, ad_name:, unknown: },   # Links::Stats, cohort30
    stalled: { count:, value:, days: 3,
               cards: [{ id:, value:, conversation_id:, waiting_since: }] },   # até 10; sem título
    response: { days: 30, median_seconds:, answered:, unanswered:, slow:, target_seconds: 300 }   # ResponseTime#payload
  },
  ads: [{
    ad_id:, ad_name:, adset_id:, verdict:, verdict_reason:,           # Report#ads + Verdict.reason
    spend_30d:, conversations:, quotes:, sales:, cost_per_sale:,
    spend_recent:, impressions_recent:, impressions_baseline:, link_clicks_recent:, link_clicks_baseline:,
    ctr_recent:, ctr_baseline:,
    frequency_7d:, frequency_date_end:, # freq7; nil sem linha
    adset_meta_results_7d:,             # soma de conversations_started do conjunto em recent7
    adset_spend_recent:,
    week_a: { spend:, sales:, cost_per_sale: }, week_b: { spend:, sales:, cost_per_sale: }
  }]
}
```

- CTR e CPM saem de `crm_meta_ad_insights_daily` (somas de `link_clicks`, `impressions`, `spend`). Nenhuma coluna nova.
- `week_a`/`week_b`: uma `Panel::Cohort` só, sobre ontem − 20 … ontem − 7. Cada conversa entra **uma vez**, pelo
  toque guardado em `Cohort#touches` (o primeiro com anúncio), e cai na semana desse toque. Vendas = cards ganhos
  dessas conversas, por anúncio. Gasto = soma dos insights do anúncio na semana. Assim não há conversa nem venda
  contada nas duas semanas.
- `stalled`: `Panel::Action.stalled(report.cohort.cards, now)`, só ids, valores e datas. O título dos cards entra
  só na resposta da API: `Analysis` carrega os títulos por id (uma consulta) ao serializar.
- `response`: `Panel::ResponseTime.new(account_id:, range: cohort30).payload` (§4.2).
- O histórico de aceites **não** está nos Facts (o cache ficaria velho depois de um aceite): vai à parte, em
  `History` (§1.3).

**Cache:** `Redis::Alfred`, chave `crm:meta_ads:advisor:facts:<RULES_VERSION>:<account_id>:<ad_account_id>:<local_date>`,
TTL 5 min, JSON. Num cache vazio, se o painel pedido for de 30 dias, `Facts` reaproveita o `Report` da própria
requisição (`Facts.new(connection, report: report)`), em vez de calcular outro.

### 1.3 Rules — `Crm::MetaAds::Advisor::Rules.evaluate(facts, history:)` → `[RuleResult]`

`history` = `{ scale_accepted_ad_ids: [...] }`: anúncios com `scale_ad` aceita nos últimos 3 dias
(`crm_meta_advisor_actions`, lido a cada chamada, sem cache).

```ruby
RuleResult = { key:, scope: 'account' | 'ad', ad_id: String | nil,
               status: 'pass' | 'fail' | 'no_data' | 'not_applicable',
               evidence: { <fato> => valor }, threshold: { <nome> => valor } }
```

Constantes em `Advisor::Rules`: `MIN_IMPRESSIONS = 1_000`, `MIN_BASELINE_CLICKS = 30`, `FATIGUE_CTR_DROP = 0.20`,
`FATIGUE_FREQUENCY = 4.0`, `AUCTION_CPM_RISE = 0.30`, `STABLE_CTR = 0.10`, `SCALE_FREQUENCY = 3.0`,
`SCALE_STEP = 0.20`, `SCALE_COOLDOWN_DAYS = 3`, `SCALE_WEEKS = 2`, `LEARNING_RESULTS = 50`, `DATA_GATE_FACTOR = 3`,
`SLOW_RESPONSE = 300` (segundos), `MIN_RESPONSES = 10`, `MAX_UNANSWERED_SHARE = 0.20`, `WINDOW_DAYS = 7`.

**Sinais (frações, não porcentagens):**
- `ctr_drop_pct = (ctr_baseline − ctr_recent) / ctr_baseline` — positivo quando o CTR **cai**;
- `ctr_change_pct = (ctr_recent − ctr_baseline) / ctr_baseline` — com sinal;
- `cpm_change_pct = (cpm_recent − cpm_baseline) / cpm_baseline` — positivo quando o CPM **sobe**.

**CTR mensurável** (vale para fadiga e leilão): impressões ≥ 1.000 nas duas janelas **e** `link_clicks_baseline ≥ 30`.
Com isso, `ctr_baseline` é sempre > 0 quando o CTR é usado, e não há divisão por zero. Mil impressões a 1,5% são
15 cliques: queda de 20% seria ruído.

**Combinação** de regra com várias partes (`fatigue`, `scale`): qualquer `fail` → `fail`; senão qualquer
`no_data` → `no_data`; senão `pass`. A evidência lista o status de cada parte.

| Regra (`key`) | Escopo | `not_applicable` | `no_data` | `fail` | `pass` | Dispara |
|---|---|---|---|---|---|---|
| `stalled_quotes` | conta | nenhuma proposta aberta na coorte | — | ≥ 1 proposta aberta parada há mais de 3 dias | há proposta aberta, nenhuma parada | `stalled_quotes` |
| `slow_response` | conta | nenhuma conversa de anúncio na coorte | `answered + unanswered` < 10 | mediana > 300 s **ou** `unanswered / (answered + unanswered)` ≥ 0,20 | o resto | `slow_response` |
| `tracking` | conta | — | amostra < 5 | menos de 70% com anúncio identificado (`Panel::Action.tracking_payload`) | ≥ 70% | `fix_tracking`; **bloqueia** `review_ad` e `scale_ad` |
| `auction` | conta | `spend_recent` da conta = 0 | CTR da conta não mensurável | `cpm_change_pct` ≥ 0,30 **e** `|ctr_change_pct|` < 0,10 | o resto (inclusive CPM alto com CTR caindo: é fadiga) | `auction_pressure` |
| `data_gate` | anúncio | `spend_30d` = 0 | conta sem custo-alvo | `spend_30d` < 3 × custo-alvo | `spend_30d` ≥ 3 × custo-alvo | portão de `review_ad` e `scale_ad` |
| `learning` | anúncio (pelo conjunto) | `adset_spend_recent` = 0 | sem `adset_id`, ou `adset_meta_results_7d` = 0 (a Meta não contou conversa: conta de site ou sem medição) | `adset_meta_results_7d` < 50 | ≥ 50 | **bloqueia** `scale_ad` (D5.5) |
| `fatigue` | anúncio | `spend_recent` = 0 | combinação (parte CTR não mensurável; parte frequência sem `freq7`) | parte CTR: `ctr_drop_pct` ≥ 0,20; parte frequência: `frequency_7d` > 4 | combinação | `refresh_creative` |
| `scale` | anúncio | veredito ≠ `up` | combinação | combinação | combinação | `scale_ad` (a única que dispara em `pass`) |

Partes de `scale` (cada uma pass/fail/no_data):
1. `data_gate` do anúncio (o status dele);
2. `learning` do anúncio (o status dele);
3. `week_a` e `week_b`: semana com gasto 0 → `no_data`; com gasto e 0 venda → `fail`; custo por venda >
   custo-alvo → `fail`; senão `pass`;
4. frequência: sem `freq7` → `no_data`; ≥ 3 → `fail`; < 3 → `pass`;
5. descanso: `ad_id` em `history.scale_accepted_ad_ids` → `fail`; senão `pass`.

Evidência obrigatória:
- `fatigue`: `trigger` (`ctr`, `frequency` ou `both`), `ctr_drop_pct`, `frequency_7d`, `frequency_date_end`;
- `data_gate` e `scale`: `target_cost_per_sale`, `selling_ads` e `target_includes_ad` (true quando o anúncio está
  entre os que formam a média; D5.3);
- `scale`: o status de cada parte.

Notas:
- "Público frio" (fadiga) não é coletado: o limite > 4 vale para todo público. Fica nos riscos.
- `slow_response` não exige "venda caindo": o tempo de resposta é olhado antes de mexer no anúncio, por isso vem
  antes de `review_ad` na prioridade.
- Sem venda na conta, `data_gate` é `no_data`, e `review_ad` cai no portão de 20 conversas que o veredito já
  aplica (CA-4.3).

### 1.4 Decision — `Crm::MetaAds::Advisor::Decision.for(facts, rules, today:)` → até 3 ações

`today` = `{ [kind, subject_key] => { status:, position:, facts: } }` das ações de hoje em
`crm_meta_advisor_actions`.

1. **Aceitas hoje ficam** (D5.10). Entram na lista mesmo que a regra não falhe mais, com os fatos guardados na
   linha, e contam no teto de 3.
2. **Dispensadas hoje saem** e não voltam no mesmo dia; a vaga vai para a próxima candidata.
3. As vagas que sobram são preenchidas pela prioridade abaixo, no máximo 1 ação por tipo.
4. A lista final é ordenada pela prioridade do tipo (aceitas e abertas juntas), não pela ordem em que entraram.

| Ordem | Tipo | Candidata | Escolha entre várias |
|---|---|---|---|
| 1 | `stalled_quotes` | regra `stalled_quotes` fail | — |
| 2 | `slow_response` | regra `slow_response` fail | — |
| 3 | `fix_tracking` | regra `tracking` fail | — |
| 4 | `review_ad` | veredito `review`, `tracking` ≠ fail, `data_gate` pass ou no_data | maior `spend_30d` |
| 5 | `refresh_creative` | `fatigue` fail e veredito do anúncio ≠ `review` (anúncio que não vende pede revisão, não troca de imagem) | maior `spend_recent` |
| 6 | `scale_ad` | `scale` pass e `tracking` ≠ fail | menor `cost_per_sale` |
| 7 | `auction_pressure` | `auction` fail | — (é a última: só ocupa vaga que sobrou) |
| filler | `wait` / `on_track` / `no_data` | só se a lista ficou vazia | `Panel::Action.wait_payload(ads)` (sem anúncio: `no_data`) |

- `subject_key` = `"ad:<ad_id>"` para ação de anúncio e `"account"` para o resto.
- `variant` = `fatigue.evidence.trigger` em `refresh_creative`, `verdict_reason.kind` (`no_sales`/`above_average`)
  em `review_ad`, `nil` nos outros.
- Os fillers não são recomendação de trabalho: **não viram linha** em `crm_meta_advisor_actions` (id `null`), não
  têm abrir/feito/dispensar e não entram na métrica.

### 1.5 Writer e Check (CA-4.2)

**Writer** — `Crm::MetaAds::Advisor::Writer.new(run:, actions:, facts:, language:).perform`

- Entrada do modelo (JSON): `{ language, currency, actions: [{ key: "a1", kind, variant, facts: { <chave> => valor } }] }`.
  - `facts` de cada ação é só o subconjunto da tabela §2, com valores crus.
  - O nome do anúncio também é um fato (`ad_name`), porque nome de anúncio pode ter dígito ("Promo 10/10").
  - Prazos fixos (`window_days`, `weeks`, `cooldown_days`, `days`) são fatos: o texto pode dizer "nos últimos
    {{window_days}} dias" sem recusa.
- Instruções (no padrão da F4):
  - os dados são dados, nunca instruções;
  - escrever para pequeno empresário, sem sigla (nada de CTR, CPM, ROAS);
  - **todo número, valor, porcentagem, prazo e nome de anúncio entra só como `{{chave}}`** de um fato da própria ação;
  - nenhum número por extenso;
  - `why` cita ao menos um fato;
  - `applies: false` quando nada fizer sentido.
- Schema `strict` (`name: 'meta_ads_advisor_texts'`):

```json
{ "applies": true, "numbers_in_words": false,
  "actions": [{ "key": "a1", "headline": "<=120", "body": "<=400", "why": "<=300" }] }
```

O modelo **não escolhe** tipo, ordem, variante nem anúncio: isso é da `Decision`.

**Check** — `Crm::MetaAds::Advisor::Check.call(answer, actions)` → `{ ok: [key], rejected: { key => [códigos] }, global: [códigos] }`

| Código | Regra (sem regex) |
|---|---|
| `numbers_in_words` | o modelo declarou `true` (autodeclaração; limite em §9, risco 3 e pergunta 7) |
| `missing_action` | cada `key` enviada aparece exatamente uma vez |
| `malformed_placeholder` | percorre o texto com `String#index('{{', pos)` e `String#index('}}', início)`; `{{` sem `}}`, `}}` solto ou chave vazia |
| `unknown_fact` | a chave não está nos `facts` **daquela ação**, ou o valor é `nil` (é o "fato inexistente" do CA-4.2) |
| `digit_outside_fact` | remove os marcadores, normaliza com `unicode_normalize(:nfkc)` (dígito largo vira ASCII) e recusa se `each_char.any? { |c| c >= '0' && c <= '9' }` |
| `why_without_fact` | `why` sem nenhum marcador |
| `empty_headline` | título vazio |
| `too_long` | acima do limite (120/400/300), medido no texto com marcadores. Recusa, não corta, porque cortar pode partir um marcador |

O texto é saída de máquina num formato que nós definimos. Não é texto de pessoa sendo interpretado, por isso a
leitura é por posição de caractere, sem regex. Dígito não-ASCII que o NFKC não converte (árabe-índico, por
exemplo) não é coberto. Em pt/en/es esse caso não aparece, e ele fica nos riscos.

**Nova tentativa e queda para a regra:**
1. A primeira resposta tem algum código → chama de novo **uma vez**, com a mesma entrada e
   `previous_rejection: [códigos]`, sem ecoar o texto.
2. Se a segunda passar, vale o texto da IA.
3. Se não passar:
   - cada ação aprovada fica com o texto da IA (`source: 'ai'`);
   - cada ação recusada fica com a regra (`source: 'rule'`);
   - o run grava `writer_reason: 'check_failed'`;
   - o log leva só os códigos (nunca o texto).
4. `applies: false` → todas pela regra (`not_applicable`), estado final.
5. `ResponsesClient::Error` → **não é estado final**: o run volta a `pending` com `retry_after = agora + 15 min` e
   `writer_reason: 'ai_error'` (é o `ERROR_TTL` da F4). Até lá a API mostra a regra; depois, a próxima leitura
   pede de novo.
6. As duas tentativas contam como **uma** geração no teto diário (`DAILY_LIMIT = 6`, contador Redis
   `crm:meta_ads:advisor:count:<account>:<dia>`, TTL 36 h, mesmo mecanismo da F4). Cada nova tentativa depois de
   `ai_error` reserva de novo. Pior caso por conta e dia: 6 reservas × 2 chamadas = 12 chamadas, mais a do resumo.

**Render:** `run.texts` guarda o texto **com marcadores**. A cada leitura, `Advisor::Format.render(template,
facts, locale:, currency:)` põe os valores **atuais**. O número exibido nunca fica velho, e o gasto, que muda a
cada 30 min, não força nova chamada à IA.
- Se algum marcador do texto não tiver valor atual (`nil` ou chave ausente), **aquela ação volta ao texto da
  regra** (`source: 'rule'`). Nunca sai texto com buraco.
- Ação aceita que já não está entre as candidatas renderiza com os fatos guardados na linha.

| Tipo do fato | Formato |
|---|---|
| `money` | `ActiveSupport::NumberHelper.number_to_currency` na moeda da conta e no locale (centavos só quando existem, como `metaAdsHelpers.amount`) |
| `count` | inteiro com separador |
| `percent` | inteiro + `%` (valor guardado em fração; `0.33` → `33%`) |
| `decimal1` | 1 casa (`4,6`) |
| `duration` | segundos para `"6 min"`, `"1 h 20 min"` ou `"2 dias"` (i18n de servidor) |
| `days` | inteiro |
| `text` | como veio (nome de anúncio) |

O tipo de cada chave fica em `Advisor::Format::TYPES` (tabela §2) e vale também para a tela (§5.1) e para o
WhatsApp (§4.6).

### 1.6 Analysis e Store — `Crm::MetaAds::Advisor::Analysis`

**`Analysis.current(connection, locale:, trigger: 'panel', report: nil)`**
1. Facts (cache) → `History` → Rules → `today` → Decision.
2. `signature` = SHA256 de `RULES_VERSION`, `Advisor::Prompt::VERSION` mais `[kind, subject_key, variant]` de cada ação, na ordem.
   - Ficam de fora os valores (o render usa o atual) e o **status** (aceitar não muda a assinatura nem gera IA).
   - Mudar tipo, anúncio, variante ou ordem gera run novo.
3. `MetaAdvisorRun.find_by(account_id:, local_date:, locale:, signature:)`. Achou → serializa (passo 5).
4. Não achou → `create_or_find_by!` (duas abas ao mesmo tempo resolvem pelo índice único). **Só quando este
   processo criou** (`previously_new_record?`):
   - marca `expired` as ações `open` de datas anteriores da conta;
   - faz upsert das ações não-filler por `(account_id, local_date, kind, subject_key)`, gravando `facts`,
     `variant`, `position` e `last_run_id` (o `status` fica como está).
5. Serializa o `Advice` (§4.2). Com `trigger: 'panel'`, marca `shown_at` nas ações mostradas que ainda não têm
   (`update_all ... where shown_at is null`: não escreve nada quando já estão marcadas).

O `GET panel` a cada 2 min por aba, com o run do dia já criado, faz: 1 leitura de cache, 2 consultas pequenas
(`History` e `today`), 1 `find_by` e 1 `update_all` que não muda linha. Nenhum upsert.

**`Analysis.write!(run)`** — sem transação aberta durante a IA:
1. **Reivindica** o run numa troca atômica:
   ```sql
   UPDATE crm_meta_advisor_runs SET writer_status = 'writing', writing_started_at = now(), retry_after = NULL
    WHERE id = :id AND (
          (writer_status = 'pending' AND (retry_after IS NULL OR retry_after <= now()))
       OR (writer_status = 'writing' AND writing_started_at < now() - interval '5 minutes'))
   ```
   (por `update_all`). Só segue se 1 linha mudou. `writing` com mais de 5 min conta como abandonado (job morto no
   deploy) e pode ser reivindicado de novo.
2. **Reserva o teto do dia** aqui, e só aqui (`INCR`). Sem vaga → grava `rule`/`daily_limit` e para.
3. Writer + Check, fora de transação.
4. Grava o resultado com `update_all ... WHERE id = :id AND writer_status = 'writing' AND writing_started_at = :o_meu`,
   para não sobrescrever quem reivindicou depois: `written`, `rule` (com o motivo) ou `pending` + `retry_after`
   (`ai_error`), mais `texts`, `writer_reason`, `writer_attempts` e `model`.

**`Analysis.daily(connection, language:)`** — resumo das 8h: `current(trigger: 'digest')`; `write!` síncrono se o
run estiver reivindicável e houver vaga. Devolve `Advice`. **`Analysis.mark_shown!(action_ids)`** é chamado pelo
envio real do resumo (não pelo de teste) só para a ação 1, a que o WhatsApp mostra.

**`Analysis.unavailable_reason(account)`**: move para cá o `AiAction.unavailable_reason` da F4.
**`Analysis.limit_reached?(account, local_date)`**: só lê o contador (para o controller não adiar à toa).

Some: `panel/ai_action.rb`, `panel/ai_action_cache.rb` e os specs deles. A chave Redis `daily_action:v1` deixa de
ser usada e expira sozinha (TTL de 1 dia).

---

## 2. Tipos de ação (fechados)

`KINDS = %w[stalled_quotes slow_response fix_tracking review_ad refresh_creative scale_ad auction_pressure wait on_track no_data]`

| Tipo | Fatos (chave: tipo) | Porquê pela regra (pt_BR, i18n `PANEL.ACTION.<KIND>`) | Botão principal → destino |
|---|---|---|---|
| `stalled_quotes` | `count`: count, `value`: money, `days`: days, `ad_name`: text | "São {count} propostas paradas há mais de {days} dias, somando {value}. Retomar custa menos que anunciar." | "Ver as N propostas": abre e fecha a lista de paradas no painel (`data-panel-stalled`, a da F4, com "Sugerir mensagem") |
| `slow_response` | `median_seconds`: duration, `answered`: count, `unanswered`: count, `target_seconds`: duration, `window_days`: days (30) | "Metade das conversas de anúncio dos últimos {window_days} dias esperou mais de {median}; {unanswered} ficaram sem resposta. Responder em até {target} muda a venda." | "Ver as conversas mais demoradas": `MetaAdsPathList` com `step = slow_replies` e **`days = 30`** |
| `fix_tracking` | `conversations`: count, `unknown`: count, `identified_pct`: percent | (texto atual da F3) | "Corrigir a origem": `emit('open', 3)`, a aba Conexão no passo 3 |
| `review_ad` | `ad_name`: text, `conversations`: count, `sales`: count, `spend`: money, `cost_per_sale`: money, `target_cost_per_sale`: money; variante `no_sales`/`above_average` | "{ad} trouxe {conversations} conversas e {sales} vendas com {spend}…" (texto e porquê por variante) | "Abrir o anúncio": `rememberAd(ad_id)` (`?anuncio=`) |
| `refresh_creative` | `ad_name`: text, `ctr_drop_pct`: percent, `frequency_7d`: decimal1, `window_days`: days (7); variante `ctr`/`frequency`/`both` | `ctr`: "As pessoas clicam {drop} menos em {ad} do que nas semanas anteriores: é hora de trocar a imagem ou o texto." `frequency`: "Cada pessoa já viu {ad} {frequency} vezes nos últimos {window_days} dias…" `both`: as duas frases | "Abrir o anúncio": `rememberAd(ad_id)` |
| `scale_ad` | `ad_name`: text, `cost_per_sale`: money, `target_cost_per_sale`: money, `frequency_7d`: decimal1, `max_increase_pct`: percent (0,20), `weeks`: count (2), `cooldown_days`: days (3) | "{ad} vende abaixo da média de {target} há {weeks} semanas. Aumente o orçamento em até {max}, e só de novo daqui a {cooldown} dias." | "Abrir no Gerenciador da Meta": link externo (nova aba) para o anúncio na conta (`button.url`, §4.2). O aumento é feito lá (D3: só leitura) |
| `auction_pressure` | `cpm_change_pct`: percent, `cpm_recent`: money, `cpm_baseline`: money, `window_days`: days (7) | "Aparecer para mil pessoas ficou {change} mais caro nos últimos {window_days} dias, e os cliques continuam iguais: é a concorrência, não o seu anúncio. Não troque o anúncio por isso." | "Entendi": não navega; **é o aceite** (o trabalho é não mexer) |
| `wait` | `ad_name`: text, `missing_conversations`: count | (texto atual) | sem botão |
| `on_track` | — | (texto atual) | sem botão |
| `no_data` | — | (texto atual) | sem botão |

Gestos, em todas as ações com `id`:
- **Botão principal** (menos `auction_pressure`): navega e chama `openAdvice(id)` (grava `opened_at` na primeira
  vez; não muda o status).
- **"Feito"** (link discreto): `acceptAdvice(id)`. Em `auction_pressure` o próprio "Entendi" é o aceite.
- **"Dispensar"** (link discreto): `dismissAdvice(id)`.
- Ação aceita: mostra "Feita" com ícone, mantém o botão principal (a pessoa pode voltar ao trabalho) e perde
  "Feito"/"Dispensar".

---

## 3. Dados — duas migrations

Só tabelas novas do fork.
- `db/migrate/20261009100000_create_crm_meta_advisor_runs_and_actions.rb` (rollback = `drop_table` das duas);
- `db/migrate/20261009100100_create_crm_meta_ad_frequency_windows.rb` (rollback = `drop_table`).

### `crm_meta_advisor_runs` — cada análise

| Coluna | Tipo | Nota |
|---|---|---|
| `account_id` | bigint, FK `accounts` `on_delete: :cascade`, null false | |
| `ad_account_id` | string, null false | a conta de anúncios analisada |
| `local_date` | date, null false | no fuso da conta de anúncios |
| `locale` | string(10), null false | idioma do texto |
| `signature` | string(64), null false | §1.6 |
| `rules_version` | string(16), null false | `'f5.1'` |
| `trigger` | string(16), null false | `panel` ou `digest` (quem criou) |
| `facts` | jsonb, default `{}`, null false | §1.2, sem título de card nem contato |
| `rules` | jsonb, default `[]`, null false | `[RuleResult]` |
| `decision` | jsonb, default `[]`, null false | `[{ kind, subject_key, variant, ad_id, position, status_at_creation, facts }]`, fillers inclusive |
| `writer_status` | string(16), default `'pending'`, null false | `pending`, `writing`, `written`, `rule` |
| `writer_reason` | string(32) | `ai_unavailable`, `credentials_missing`, `not_applicable`, `ai_invalid`, `ai_error`, `daily_limit`, `check_failed` |
| `writer_attempts` | smallint, default 0, null false | 0, 1 ou 2 (da última escrita) |
| `writing_started_at` | datetime | marca da reivindicação (§1.6) |
| `retry_after` | datetime | só com `pending` depois de `ai_error` |
| `texts` | jsonb, default `{}`, null false | `{ "<kind>|<subject_key>" => { headline, body, why } }`, com marcadores |
| `model` | string(64) | `MODEL_SUMMARY` quando escreveu |
| `prompt_version` | string(16) | `Advisor::Prompt::VERSION` usada (§11); entra na assinatura |
| timestamps | | |

Índices: único `(account_id, local_date, locale, signature)` `idx_crm_meta_advisor_runs_unique`;
`(account_id, created_at)` `idx_crm_meta_advisor_runs_account_created`.
Custo: o `ResponsesClient` já registra em `Crm::AiUsageEvent` (feature `anuncios_meta`, CA-4.6).

### `crm_meta_advisor_actions` — cada ação recomendada e o que a pessoa fez

| Coluna | Tipo | Nota |
|---|---|---|
| `account_id` | bigint, FK `accounts` `on_delete: :cascade`, null false | |
| `run_id` | bigint, FK `crm_meta_advisor_runs` `on_delete: :nullify` | o run que criou |
| `last_run_id` | bigint, FK `crm_meta_advisor_runs` `on_delete: :nullify` | o último run que a gravou |
| `local_date` | date, null false | |
| `kind` | string(32), null false | só os 7 tipos não-filler |
| `subject_key` | string(64), null false | `account` ou `ad:<ad_id>` |
| `variant` | string(32) | §1.4 |
| `ad_id` | string | |
| `position` | smallint, null false | 1..3 no último run |
| `facts` | jsonb, default `{}`, null false | fatos da ação no último run |
| `status` | integer, default 0, null false | enum `{ open: 0, accepted: 1, dismissed: 2, expired: 3 }` (padrão `Crm::AiStageSuggestion`) |
| `shown_at` | datetime | primeira vez no painel, ou no resumo real (só a ação 1) |
| `opened_at` | datetime | primeiro clique no botão principal |
| `opened_by_id` | bigint, FK `users` `on_delete: :nullify` | |
| `opened_via` | string(16) | `panel` ou `api` |
| `resolved_at` | datetime | |
| `resolved_by_id` | bigint, FK `users` `on_delete: :nullify` | |
| `resolved_via` | string(16) | `panel` ou `api` (D5.11) |
| timestamps | | |

Índices: único `(account_id, local_date, kind, subject_key)` `idx_crm_meta_advisor_actions_unique`;
`(account_id, status, local_date)` `idx_crm_meta_advisor_actions_status`.

### `crm_meta_ad_frequency_windows` — frequência de 7 dias (D5.4)

| Coluna | Tipo |
|---|---|
| `account_id` | bigint, FK `accounts` `on_delete: :cascade`, null false |
| `ad_account_id`, `ad_id` | string, null false |
| `adset_id` | string |
| `window_days` | smallint, null false (7) |
| `date_end` | date, null false — o `date_stop` devolvido pela Meta, nunca "ontem" calculado |
| `impressions`, `reach` | bigint, default 0, null false |
| `frequency` | decimal(10,4) |
| `fetched_at` | datetime, null false |
| timestamps | |

Índice único `(account_id, ad_account_id, ad_id, window_days, date_end)` `idx_crm_meta_ad_freq_windows_unique`.

**Coleta:**
- `Insights::Query.ads_window(7)`: `{ level: 'ad', date_preset: 'last_7d', fields: 'ad_id,adset_id,impressions,reach,frequency' }`,
  **sem** `time_increment` e sem `action_attribution_windows`.
- `Insights::Writer#frequency_windows!(rows, window_days: 7)`: upsert; `date_end` = `row['date_stop']`.
- `Insights::Sync#read_recent`: depois da leitura de anúncios dar certo, faz a de posicionamento e **depois, sempre**,
  a de frequência (mesmo se a de posicionamento falhou). Devolve o resultado da de posicionamento, como hoje.
- **A leitura de frequência é opcional:** pula se `Usage.paused?`; no erro, só `Usage.track!` e log com a classe e
  o código. **Nunca** passa por `Failure.handle!`, então nunca chama `mark_invalid!` nem `mark_access_lost!` (um
  código 100 por parâmetro errado na consulta nova não pode desligar a conta).
- Não entra no backfill: a primeira rodada das 4h preenche, e até lá as regras que dependem dela ficam `no_data`.

**Retenção** (`Crm::MetaAds::Advisor::PruneJob`, `config/schedule.yml` `crm_meta_ads_advisor_prune_job`,
cron `30 8 * * *` = 5h30 Brasília, depois da leitura `recent` das 4h; fila `low`; apaga em lotes de 1.000 com
`in_batches`):
- runs com mais de 90 dias;
- ações com mais de 400 dias (a métrica de aceite precisa de histórico);
- janelas de frequência com mais de 35 dias.

**Models (B):**
- `Crm::MetaAdvisorRun` (`self.table_name = 'crm_meta_advisor_runs'`, `belongs_to :account`, `has_many :actions`
  pela FK `run_id`).
- `Crm::MetaAdvisorAction` (enum `status`, `belongs_to :run, optional: true`, `belongs_to :resolved_by` e
  `:opened_by`, `class_name: 'User', optional: true`). Métodos:
  - `open!(user, via:)`: grava `opened_*` só se `opened_at` for nulo; vale em qualquer status.
  - `accept!(user, via:)` / `dismiss!(user, via:)`: só de `open`; senão levantam `Crm::MetaAdvisorAction::NotOpen`.
    Gravam `resolved_by`/`resolved_at`/`resolved_via`.
  - `self.acceptance(account_id, from:, to:)` → `{ shown:, opened:, accepted:, dismissed:, unanswered:, rate: }`,
    a mesma conta da SQL abaixo; `rate` = `nil` sem denominador.
- `Crm::MetaAdFrequencyWindow`.

**Métrica do PRD ("aceita ≥ 4 de 5"), por psql só leitura.** Denominador = ações **mostradas** cujo dia acabou ou
que foram respondidas no painel; as que venceram sem resposta contam contra. O Guia (`api`) fica fora.

```sql
select count(*) filter (where status = 1)                     as aceitas,
       count(*) filter (where status = 2)                     as dispensadas,
       count(*) filter (where status = 3 or status = 0)       as sem_resposta,
       count(*) filter (where opened_at is not null)          as abertas,
       count(*)                                               as mostradas
  from crm_meta_advisor_actions
 where account_id = 18
   and local_date between current_date - 14 and current_date - 1
   and shown_at is not null
   and (resolved_via is null or resolved_via = 'panel');
-- aceite = aceitas / (aceitas + dispensadas + sem_resposta)
```

---

## 4. API

Base: `/api/v1/accounts/:account_id/crm/meta_ads_connection`.
- Administrador; agente recebe **403** `{ "error": "forbidden" }`.
- Erro de regra: **422** `{ "error": "<code>" }`.
- Conta sempre por `Current.account`.

### 4.1 Rotas (`config/routes.rb`, só B)

- No bloco `resource :meta_ads_connection`: `get :panel_list`, em `meta_ads_connections#panel_list`, que entra
  em `READ_ACTIONS`.
- No `scope 'meta_ads_connection'` da F4:
  - `post 'advisor_actions/:id/open', to: 'meta_ads_advisor_actions#open'`;
  - `post 'advisor_actions/:id/accept', to: 'meta_ads_advisor_actions#accept'`;
  - `post 'advisor_actions/:id/dismiss', to: 'meta_ads_advisor_actions#dismiss'`.
- `daily_action` e `quote_message` continuam como estão.
- As três rotas novas entram no catálogo do Guia sozinhas (`Acoes#catalogo`). D5.11 trata a métrica; o gerado
  `lib/operator_guide/formatos-das-acoes.json` muda e é da integração (§7).

### 4.2 `GET /panel?days=7|30` (alterado, B)

Mantém tudo da F3 **menos `action`**, que sai do `Report#payload` (a tela passa a usar `advice`). Ganha:

```
panel.confidence      = { window_days: 7|30, conversations, ad, ad_name, campaign, unknown }   // no período (D5.8)
panel.meta_comparison = MetaComparison | null
panel.response_time   = ResponseTime | null       // do período; com days = 30 reaproveita facts.account.response
panel.advice          = Advice                    // Analysis.current(connection, locale: I18n.locale, report: report)
```

```
Advice = {
  "run_id": 812,
  "local_date": "2026-10-07",
  "rules_version": "f5.1",
  "writer": { "status": "pending" | "writing" | "written" | "rule",
              "reason": null | "ai_unavailable" | "credentials_missing" | "not_applicable" | "ai_invalid" | "ai_error" | "daily_limit" | "check_failed" },
  "actions": [AdviceAction]                           // 1 a 3, na ordem
}
```

`writer.status` na API:
- `pending` só quando o run é reivindicável agora;
- `pending` com `retry_after` no futuro sai como `rule` / `ai_error` (a tela mostra a regra e não pede IA);
- `writing` com mais de 5 min sai como `pending`.

```
AdviceAction = {
  "id": 4521 | null,                                  // null nos fillers
  "position": 1,
  "kind": "stalled_quotes" | "slow_response" | "fix_tracking" | "review_ad" | "refresh_creative" | "scale_ad" | "auction_pressure" | "wait" | "on_track" | "no_data",
  "variant": "ctr" | "frequency" | "both" | "no_sales" | "above_average" | null,
  "status": "open" | "accepted",                      // dispensada não vem
  "opened": true | false,
  "ad_id": "120..." | null,
  "ad_name": "Promo outubro" | null,
  "facts": { "<chave>": number | string | null },     // §2; valores crus, money em unidade (não centavos), percent em fração
  "button": { "target": "stalled_list" | "slow_replies" | "connection_step" | "ad_detail" | "ads_manager" | "acknowledge" | "none",
              "step": 3 | null,
              "url": "https://adsmanager.facebook.com/..." | null },   // só em ads_manager
  "source": "ai" | "rule",
  "headline": string | null, "body": string | null, "why": string | null,   // já renderizados; só com source "ai"
  "cards": [{ "id", "title", "value", "conversation_id", "waiting_since" }]  // só stalled_quotes; até 10, como na F4
}
```

- `button.url` de `ads_manager` é montado no servidor com a conta (`act`, sem o prefixo `act_`) e o id do
  anúncio. C confere o formato na tela antes do PR; se o filtro por anúncio não abrir o anúncio, o link abre só a
  conta, e isso vai escrito no PR.
- `cards` de ação aceita que saiu das candidatas: os ids guardados na linha, com os títulos atuais.

```
MetaComparison = {
  "days": 7 | 30,
  "until": "2026-10-06",     // sempre ontem (D5.8)
  "rows": [                  // uma por destino com dado no período; WhatsApp primeiro
    { "destination": "whatsapp",
      "meta": 52,            // soma de crm_meta_ad_insights_daily.conversations_started
      "ours": 46,            // conversas distintas cujo PRIMEIRO toque no período é origin 'whatsapp'
      "difference": -6, "explanation": "close" | "meta_higher" | "ours_higher" },
    { "destination": "site",
      "meta": 12,            // soma do action_type 'offsite_conversion.fb_pixel_lead' em insights.actions (leads do Pixel)
      "meta_visits": 31,     // soma de 'landing_page_view' (contexto, não entra na diferença)
      "ours": 9,             // conversas distintas cujo primeiro toque no período é origin 'site' (ponte do site)
      "difference": -3, "explanation": "close" | "meta_higher" | "ours_higher" }
  ],
  "explanation": "no_meta_data" | null   // só quando nenhuma linha tem dado da Meta e houve gasto
}
```

**Gate G1 (rodado em 07/10, conta 18, últimos 30 dias, só leitura):** 15.127 impressões, 413 cliques no link,
R$ 410,03 de gasto, **0** `conversations_started`. Os anúncios da Placement levam ao **site**: em `actions`
aparecem `offsite_conversion.fb_pixel_lead` 12, `landing_page_view` 31, `link_click` 413 e nenhum
`onsite_conversion.messaging_conversation_started_7d`. Por isso a comparação é **por destino**: sem isso, a
Placement nunca teria a linha da Meta. Consequências também em §1.3: `learning` fica `no_data` na Placement
(previsto: "conta de site"), e o histórico de insights na janela `baseline` está vazio (linhas só desde 01/10 nos
últimos 30 dias), então fadiga por CTR e leilão ficam `no_data` até haver 3 semanas de dado. É o comportamento
honesto ("Ainda é cedo"), não defeito.

- Linha `whatsapp` só com `destinations.whatsapp`; linha `site` só com `destinations.site`. Linha sem gasto no
  destino e sem conversa nossa não aparece. Sem nenhuma linha → `null`.
- A Meta não diz em qual destino cada anúncio está; a linha usa a soma da conta inteira para aquela métrica (cada
  métrica só existe em anúncio daquele destino, então não há dupla contagem).
- `explanation` de cada linha: `close` se `|difference| ≤ max(2, 10% de meta)`; senão `meta_higher`/`ours_higher`.
- Período: insights de `first_day..ontem`; links com `touched_at` em `[first_day 00:00, hoje 00:00)` no fuso da conta.
- Links filtrados por `ad_account_id = connection.ad_account_id OR ad_account_id IS NULL` (a mesma conta da Meta).
- Cada conversa conta uma vez, pela origem do primeiro toque dela no período.
- `explanation` é decidida no código, nunca pelo LLM.
- Serviço: `Crm::MetaAds::Panel::MetaComparison.new(connection, report).payload`.

```
ResponseTime = {
  "days": 7 | 30,
  "median_seconds": 360 | null,  // null com answered = 0
  "answered": 38, "unanswered": 3, "slow": 9,   // slow = respondidas acima de 300 s
  "target_seconds": 300
}
```

Serviço (A): `Crm::MetaAds::Panel::ResponseTime.new(account_id:, range:)`.
- `#payload` devolve o resumo; `#by_conversation` devolve `{ conversation_id => { seconds:, answered: } }`.
- Início de cada conversa: o **menor `touched_at`** dela em `crm_meta_ad_links` no `range`
  (`group(:conversation_id).minimum(:touched_at)`), e não `Cohort#touches`, que guarda o primeiro toque **com
  anúncio**.
- Cálculo, por conversa:
  1. a **primeira mensagem `incoming`** com `created_at ≥ início − 1 min` (tolerância entre o toque e a mensagem
     que o criou);
  2. a **primeira mensagem `outgoing`, `private = false`** depois dela, sem `content_attributes.automation_rule_id`,
     sem `additional_attributes.campaign_id` e sem `whatsapp_api_campaign_id`. `template` (boas-vindas e fora de
     horário) e `activity` ficam fora pelo tipo. Contam a pessoa, o agente da plataforma e o eco do celular (D5.6);
  3. sem resposta e entrada há mais de 300 s → `unanswered`. Entrada mais recente que isso não conta (ainda está
     no prazo).
- Uma consulta com `LATERAL` sobre os ids, usando o índice `(conversation_id, account_id, message_type,
  created_at)` de `messages`.

### 4.3 `GET /panel_list?step=conversations|quotes|sales|slow_replies&days=7|30` (novo, B)

Policy `show?`. Sem conexão ou sem conta de anúncios → `{ "list": null }`. `step` fora da lista → 422
`invalid_step`. Serviço `Crm::MetaAds::Panel::PathList.new(connection, step:, days:).payload` sobre a mesma
coorte do `Report` (o total bate com o número do caminho). `slow_replies` usa `ResponseTime#by_conversation` do
mesmo período; a tela sempre pede `slow_replies` com `days=30` (o número da ação).

```
{ "list": { "step": "quotes", "days": 30, "total": 21, "items": [PathItem] } }   // no máximo 50 (LIST_LIMIT)
PathItem = {
  "conversation_id": 901, "card_id": 77 | null,
  "title": "<título do card ou nome do contato>" | null,
  "ad_name": "Promo outubro" | null, "touched_at": ISO8601,
  "stage_name": "Proposta" | null, "status": "open" | "won" | "lost" | null, "value": 1500.0 | null,
  "waiting_since": ISO8601 | null,
  "stalled": true | false,                       // proposta aberta parada há mais de 3 dias (Panel::Action.stalled)
  "response_seconds": 360 | null, "answered": true | false | null
}
```

| `step` | Itens | Ordem |
|---|---|---|
| `conversations` | uma por conversa da coorte, com o card principal se houver | `touched_at` desc |
| `quotes` | cards `quote?` da coorte | abertos por `waiting_since` asc, depois ganhos |
| `sales` | cards `sale?` | `value` desc |
| `slow_replies` | conversas com `unanswered` ou `response_seconds > 300` | sem resposta primeiro (entrada mais antiga), depois as mais lentas |

### 4.4 `POST /daily_action` (alterado, A)

Body `{ "days": 7|30 }`. `days` é aceito e ignorado (D5.2). Policy `show?`. O controller **não reserva** o teto
(a reserva é só no `write!`, §1.6).
- Sem conexão ou sem conta de anúncios → 200 `{ "daily_action": null }`.
- `run = Analysis.current(...)` e, conforme o `writer.status` serializado:
  - `written` ou `rule` → 200 `{ "daily_action": Advice }`;
  - `writing` (outra aba escrevendo há menos de 5 min) → 200 com o `Advice` em `writing`. Não adia nada; a tela
    continua conferindo o painel em `CHECK_MS` (§5.1);
  - `pending` e IA indisponível → grava `rule` com o motivo → 200;
  - `pending` e só fillers → `rule` / `not_applicable` → 200 (não gasta IA);
  - `pending` e `Analysis.limit_reached?` → `rule` / `daily_limit` → 200;
  - senão → `defer_interactive_ai('meta_ads_daily_action', { run_id:, language: })` → 202 com `poll_url`. O
    `done` é `{ "daily_action": Advice }`.
- `InteractiveOperation#meta_ads_daily_action`:
  - autoriza com `authorize_meta_ads_panel!`;
  - confere que o run é da conta;
  - roda `Analysis.write!(run)` (que reivindica e reserva) e devolve `Analysis.serialize(run.reload, locale)`. Se
    outra operação reivindicou antes, só devolve o estado atual.

### 4.5 `POST /advisor_actions/:id/open`, `/accept` e `/dismiss` (novo, B)

Controller `Api::V1::Accounts::Crm::MetaAdsAdvisorActionsController`, policy `show?` (a mesma da ação do dia).
- A ação é buscada por `Crm::MetaAdvisorAction.where(account_id: Current.account.id).find_by(id:)`. Se não
  existir → 404 `{ "error": "not_found" }`.
- `via` = `'api'` quando o pedido se autenticou pelo cabeçalho `api_access_token` (é como o Guia chama, em
  `Autonomia::Guide::ChamadaInterna`), senão `'panel'`.
- `open` → 200 sempre (idempotente).
- `accept`/`dismiss`: `NotOpen` → 422 `not_open`.
- 200 `{ "advisor_action": { "id", "status", "opened_at", "resolved_at" } }`.

### 4.6 Resumo das 8h (B)

- `Digest#ai_action` / `#action` passam a usar `Advisor::Analysis.daily(connection, language:)`, com a
  **primeira** ação. O envio real chama `Analysis.mark_shown!([id])`; o de teste não.
- `MessageBuilder#action_text`:
  - `source: 'ai'` → `headline` + `body` (já renderizados);
  - senão, `rule_text` por `kind` e `facts`, com valores formatados por `Advisor::Format` (dinheiro e duração; é
    dependência de A, §7). Os **5** tipos que a F4 não tinha pela regra entram em
    `config/locales/meta_ads_whatsapp_report.{en,pt_BR}.yml`: `actions.slow_response`, `actions.review_ad`,
    `actions.refresh_creative`, `actions.scale_ad`, `actions.auction_pressure`. (`review_ad` antes só vinha da IA;
    agora vem da regra e sairia "translation missing".)
- No Oficial em idioma diferente de pt_BR vale a regra, como hoje. O envio de teste não chama a IA
  (`Analysis.current` sem `write!`).

---

## 5. Painel (C)

### 5.1 "O que fazer hoje": até 3 ações (`MetaAdsDailyAction.vue`, vira lista)

- **Props:** `advice` (de `panel.advice`) e `days`.
- **Pedido à IA:** `dailyAction(days)` só quando `advice.writer.status` é `pending`. A resposta (`Advice`)
  substitui `advice` se tiver o mesmo `run_id`. Com outro `run_id`, a tela fica com o painel e não troca o texto.
- **Espera:** `MetaAdsPanel.vue` passa a dizer `waiting()` também quando `advice.writer.status === 'writing'`, para
  o `useMetaAdsLive` conferir em `CHECK_MS` (20 s) em vez de 2 min.
- **Layout, dentro do herói** (a caixa `bg-white/[0.07]` atual):
  - Lista ordenada `<ol data-panel-actions>` com `<li data-panel-action :data-action-kind :data-action-source
    :data-action-id :data-action-status>`.
  - **Ação 1, aberta:** título grande, corpo, "Por quê:", botão principal (`bg-white text-[#0D2344]`) e, abaixo,
    "Feito" e "Dispensar" (links discretos `text-white/70`, `min-h-11`).
  - **Ações 2 e 3, compactas:** número, título, "Por quê:" e os mesmos controles, numa linha que quebra no
    celular. Separador `border-t border-white/10`.
  - **Ação aceita:** selo "Feita" (`data-action-done`), texto em `text-white/70`, botão principal mantido, sem
    "Feito"/"Dispensar".
  - O selo da IA (`data-daily-ai-badge`) aparece uma vez, no topo da lista, quando alguma ação tem
    `source: 'ai'` (texto do selo: pergunta 6).
- **Texto:**
  - `source: 'ai'` → `headline`/`body`/`why` do servidor;
  - senão, i18n `PANEL.ACTION.<KIND>.TEXT/WHY/BUTTON` (com a variante) e os `facts`, formatados pelo tipo da
    tabela §2 (`amount`, `duration`, percent etc.).
- **Botão principal:**
  - `stalled_list` → abre e fecha a lista de paradas (comportamento da F4);
  - `slow_replies` → abre `MetaAdsPathList` com `step = slow_replies` e `days = 30`;
  - `connection_step` → `emit('open', 3)`;
  - `ad_detail` → `rememberAd(ad_id)`;
  - `ads_manager` → `<a :href="button.url" target="_blank" rel="noopener noreferrer">`;
  - `acknowledge` ("Entendi") → `acceptAdvice(id)`.
  - Nos que navegam: `openAdvice(id)` depois de navegar, só se `opened` for falso. Falha vai para o console com a
    classe e não bloqueia a navegação.
- **Feito:** `acceptAdvice(id)`. Sucesso → a ação passa a "Feita" na hora (sem esperar o refresh). Falha → alerta
  `AI.DAILY.DONE_FAILED`, a ação fica aberta.
- **Dispensar:** `dismissAdvice(id)`. Sucesso → a ação some da lista. Falha → alerta `AI.DAILY.DISMISS_FAILED`, a
  ação fica.
- O botão secundário "Ver as N propostas" da F4 (`data-panel-stalled-button`) **sai**: enquanto houver propostas
  paradas, elas são a ação 1, aceita ou aberta. Se forem dispensadas, ficam na etapa Propostas do caminho, com o
  "Sugerir mensagem" (§5.4).
- `MetaAdsPanel.vue`: `onAction` vira `onAdvice(action)`. O texto da regra (`actionText`) passa a ser por ação. A
  lista de paradas usa `stalledAction.cards`.

### 5.2 "Quanto confiar": Meta × nós (`MetaAdsConfidence.vue`)

- Nova prop opcional `comparison` (`MetaComparison`). Sem ela, o componente fica como está. A aba Conexão
  (`MetaAdsSummary`) não passa a prop.
- Linha nova `data-confidence-meta`, abaixo do percentual, com `<i18n-t>` e slots para os números em negrito
  (**nunca `v-html`**):
  - Uma linha por destino (`rows`), cada uma com a explicação logo abaixo (i18n
    `SUMMARY.CONFIDENCE.META.<DESTINATION>.<EXPLANATION>`):
    - WhatsApp: "Até ontem, a Meta diz **{meta}** conversas iniciadas pelo WhatsApp; nós contamos **{ours}**."
      - `close`: "Os dois números batem."
      - `meta_higher`: "A Meta também conta quem já conversava com você; conversa encaminhada ou de contato salvo
        chega sem origem para nós."
      - `ours_higher`: "Contamos toda conversa que chegou pelo anúncio, inclusive de quem clicou antes e voltou; a
        Meta só conta até 7 dias depois do clique."
    - Site: "Até ontem, a Meta diz **{meta}** contatos pelo site ({visits} visitas à página); nós contamos **{ours}**
      conversas que vieram do site."
      - `close`: "Os dois números batem."
      - `meta_higher`: "A Meta conta quem deixou contato no site; nem todo mundo clica depois para conversar no
        WhatsApp."
      - `ours_higher`: "Contamos toda conversa que veio pelo botão do site, mesmo de quem não deixou contato lá."
  - `explanation: no_meta_data`: "A Meta ainda não mandou o número deste período."
- O título passa a dizer o período: "Quanto confiar — últimos {days} dias" (`window_days`).

### 5.3 Tempo de resposta

- **Onde:** nota na etapa **Conversas** do caminho (`data-panel-response-time`), no período da tela.
- **Texto:** "Tempo de resposta: {duration}" e a nota "metade respondida em até esse tempo · {unanswered} sem
  resposta". A parte "sem resposta" só aparece com `unanswered > 0`. O rótulo não diz "média" porque o número é a
  mediana (pergunta 1).
- Acima de 300 s, o valor fica `text-n-amber-11`. Sem resposta medida (`median_seconds = null`), a linha sai.
- **Formatador:** `duration(seconds, t)` novo em `metaAdsHelpers.js`, com i18n `PANEL.DURATION.SECONDS|MINUTES|HOURS|DAYS`
  e arredondamento para baixo: abaixo de 60 s → "menos de 1 min"; abaixo de 60 min → "N min"; abaixo de 48 h →
  "N h" ou "N h M min"; acima disso → "N dias".

### 5.4 Caminho do dinheiro clicável (CA-3.2, parcial — D5.7)

- **Etapas que viram botão:** Conversas, Propostas e Vendas. `<button data-panel-path-open="conversations|quotes|sales">`
  cobre a etapa inteira (`after:absolute after:inset-0`, como no cartão de anúncio), com `aria-expanded`.
- **Investido não abre lista:** já está detalhado nos cartões de anúncio, logo abaixo.
- **Componente novo `MetaAdsPathList.vue`:**
  - Props `step` e `days`. Carrega `panelList(step, days)`.
  - Aparece abaixo do caminho (`data-panel-path-list`), com título, total ("21 propostas"), estado carregando,
    erro com "Tentar de novo" e lista vazia. Em `slow_replies` o título diz "últimos 30 dias".
  - Cada linha (`data-panel-path-item`) mostra título, anúncio, etapa, valor e espera ou tempo de resposta.
  - Cada linha tem `router-link` "Abrir conversa" (`/app/accounts/:id/conversations/:cid`) e, com `card_id`,
    "Abrir no CRM" (`{ name: 'crm_kanban_index', params: { accountId }, query: { card_id } }`).
  - Em `quotes`, a linha com `stalled: true` mostra `MetaAdsQuoteMessage` ("Sugerir mensagem", o componente da
    F4), para não perder a sugestão quando as paradas forem dispensadas.
  - `total > 50` → "Mostrando 50 de N", sem link.
- Uma lista aberta por vez. Clicar na mesma etapa fecha. A etapa aberta não vai para o endereço.

### 5.5 API JS (`api/crmMetaAdsConnection.js`, C)

- `panelList(step, days)` = `axios.get(\`${this.url}/panel_list\`, { params: { step, days } })`.
- `openAdvice(id)` = `axios.post(\`${this.url}/advisor_actions/${id}/open\`)`.
- `acceptAdvice(id)` = `axios.post(\`${this.url}/advisor_actions/${id}/accept\`)`.
- `dismissAdvice(id)` = `axios.post(\`${this.url}/advisor_actions/${id}/dismiss\`)`.
- `dailyAction(days)` continua igual; o comentário do contrato passa a citar `Advice`.

---

## 6. Bateria de cenários-gabarito (CA-4.5)

**Arquivo:** `spec/services/crm/meta_ads/advisor/scenarios_spec.rb`. **Quem escreve: o orquestrador, antes de A
implementar**, a partir desta seção. A implementa `Facts`/`Rules`/`Decision` até a bateria passar e **não pode
mudar o gabarito** sem subir `RULES_VERSION`, com o motivo no PR e o OK do orquestrador. O cabeçalho do arquivo
diz isso.

**Sem IA e sem rede:** a bateria chama `Facts` (sem cache) → `History` → `Rules` → `today` → `Decision`.

Cada cenário confere **duas coisas, inteiras**:
1. o mapa **completo** `{ "<regra>" | "<regra>:<ad_id>" => status }`, com todas as regras de conta e as 4 por
   anúncio de cada anúncio do cenário;
2. a lista `actions.map { [kind, ad_id, status] }` (`ad_id` `nil` nas de conta; `status` `open`, `accepted` ou
   `nil` nos fillers).

Mudou um dos dois, o spec falha.

### 6.1 Ajudante — `spec/support/meta_ads_advisor_helpers.rb` (A, entregue primeiro: §7)

Assinaturas fixas (o orquestrador escreve a bateria contra elas):
- `advisor_setup(timezone: 'America/Sao_Paulo')` → `[account, connection]`; `ad_account_id 'act_9001'`,
  `destinations.whatsapp = true`, funil com etapas de proposta (`quote`) e venda (`sale`).
- `advisor_insights(ad_id:, adset_id:, from:, to:, spend:, impressions:, link_clicks:, conversations_started: 0)`:
  espalha por igual entre os dias (o resto no último dia).
- `advisor_frequency(ad_id:, adset_id:, frequency:, date_end: Date.new(2026, 10, 6))`.
- `advisor_conversations(ad_id:, count:, from:, to:, reply_after: 120)` → conversas criadas uma por dia em
  rodízio de `from` a `to`, às 12h locais: link `whatsapp` (com `ad_id`, ou sem anúncio quando `ad_id: nil`),
  mensagem de entrada no toque e de saída `reply_after` segundos depois (`nil` = sem resposta).
- `advisor_sale(conversation)` → card ganho na etapa de venda.
- `advisor_stalled_quote(conversation, waiting_days: 5)` → card aberto na etapa de proposta, `last_message_at`
  há `waiting_days` dias.
- `advisor_template_reply(conversation, after:)` e `advisor_automation_reply(conversation, after:)` → saídas que
  não contam (`template`; `content_attributes.automation_rule_id`).
- `advisor_resolved(account, kind:, subject_key:, status:, local_date:, ad_id: nil, facts: {})` → linha em
  `crm_meta_advisor_actions`.
- `advisor_evaluate(connection)` → `{ rules: { key => status }, actions: [[kind, ad_id, status]] }`.

### 6.2 Base comum

- `travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00'))`, salvo S20. Janelas: `recent7` 30/09–06/10,
  `baseline` 09/09–29/09, `weekA` 23/09–29/09, `weekB` 16/09–22/09, `cohort30` 08/09–agora.
- **Insights "neutros"** de um anúncio, quando a tabela diz *neutro*: baseline 12.000 impressões, 180 cliques,
  R$ 240 (CTR 1,5%, CPM 20); recent 5.000 impressões, 75 cliques, R$ 100 (CTR 1,5%, CPM 20).
- `meta7` = `conversations_started` do conjunto, posto no `recent7`. `freq` = `advisor_frequency` com
  `date_end` 06/10, salvo indicação.
- Conversas: `reply_after: 120`, espalhadas em 09/09–06/10, salvo indicação. Sem card, salvo indicação.

### 6.3 Entradas

| # | Cenário | Anúncio (conjunto) | baseline: imp / cliques / R$ | recent: imp / cliques / R$ | freq | meta7 | Conversas e vendas |
|---|---|---|---|---|---|---|---|
| S1 | Fadiga por CTR | A (SA) | 12.000 / 180 / 240 | 5.000 / 50 / 100 | 2,5 | 10 | 25; 2 vendas |
| S2 | Fadiga por frequência | A (SA) | 12.000 / 180 / 240 | 5.000 / 73 / 100 | 4,6 | 10 | 25; 2 vendas |
| S3 | Leilão | A (SA) | 12.000 / 180 / 240 | 5.000 / 73 / 140 | 2,0 | 10 | 25; 2 vendas |
| S4 | Poucos dados | A (SA) | 500 / 5 / 125 | 300 / 3 / 75 | — | 3 | 8; 0 venda |
| S5 | Conta pequena, aprendizado | A (SA) | 21.000 / 315 / 315 | 7.000 / 105 / 105 | 1,8 | 6 | 22: 1 com venda em weekB, 1 com venda em weekA, 1 com venda em recent, 19 sem venda |
| S6 | Conta pequena sem venda | A (SA) | 15.000 / 225 / 225 | 5.000 / 75 / 75 | 2,0 | 8 | 25; 0 venda |
| S7 | Atendimento lento | A (SA) | neutro | neutro | 2,0 | 6 | 12 com `reply_after: 1500` + 2 sem resposta (entrada 2 dias atrás); 0 venda |
| S8 | Lento + paradas | como S7 | | | | | S7 + `advisor_stalled_quote` em 2 das 12 respondidas (5 dias) |
| S9 | Rastreio ruim | B (SB) | neutro | neutro | 2,0 | 8 | B: 20, 0 venda; mais 9 sem anúncio (`ad_id: nil`) |
| S10 | Escala | C (SC) | 21.000 / 315; R$ 70 em 09–15/09, 140 em weekB, 140 em weekA | 7.000 / 105 / 130 | 2,1 | 60 | C: 24, 4 vendas (uma em 09–15/09, uma em weekB, uma em weekA, uma em recent) |
| | | D (SD) | 18.000 / 270 / 300 | 6.000 / 90 / 120 | 2,0 | 20 | D: 20, 2 vendas |
| S11 | Escala em descanso | como S10 | | | | | S10 + `advisor_resolved(kind: 'scale_ad', subject_key: 'ad:C', status: :accepted, local_date: 05/10)` |
| S12 | Teto de 3 | B (SB) | neutro | neutro | 2,0 | 8 | B: 20 com `reply_after: 1500`, 0 venda, 2 delas com `advisor_stalled_quote` |
| | | E (SE) | 12.000 / 180 / 240 | 5.000 / 50 / 100 | 2,5 | 4 | E: 5 com `reply_after: 1500`; mais 12 sem anúncio com `reply_after: 1500` |
| S13 | Dispensada hoje | como S8 | | | | | S8 + `advisor_resolved(kind: 'stalled_quotes', subject_key: 'account', status: :dismissed, local_date: 07/10)` |
| S14 | Sem dado | — | — | — | — | — | nada |
| S15 | Portão barra a revisão | F (SF) | 12.000 / 180 / 150 | 5.000 / 75 / 50 | 2,0 | 8 | F: 20, 0 venda |
| | | G (SG) | 12.000 / 180; R$ 30 em 09–15/09, 90 em weekB, 90 em weekA | 4.000 / 60 / 90 | 2,0 | 10 | G: 22, 3 vendas (weekB, weekA, recent) |
| S16 | Fadiga e leilão juntos | A (SA) | 12.000 / 180 / 240 | 5.000 / 50 / 140 | 2,5 | 10 | A: 25, 2 vendas |
| | | B (SB) | 12.000 / 180 / 240 | 5.000 / 100 / 140 | 2,0 | 10 | B: 25, 2 vendas |
| S17 | Anúncio novo sem linha de base | N (SN) | — | 5.000 / 50 / 100 | 2,0 | 5 | 8 (em 30/09–06/10); 0 venda |
| S18 | Lento só por falta de resposta | A (SA) | neutro | neutro | 2,0 | 6 | 11 com `reply_after: 60` + 4 sem resposta (entrada 1 dia atrás) |
| S19 | Modelo e automação não contam | A (SA) | neutro | neutro | 2,0 | 6 | 12, cada uma com `advisor_template_reply(after: 5)`, `advisor_automation_reply(after: 10)` e resposta humana `reply_after: 1800` |
| S20 | Fronteira de fuso | como S1 | | | | | S1 com `travel_to('2026-10-07T23:30:00-03:00')` (em UTC já é 08/10) |
| S21a | Frequência de anteontem | como S2 | | | 4,6 em `date_end` 05/10 | | S2 |
| S21b | Frequência velha | como S2 | | | 4,6 em `date_end` 04/10 | | S2 |
| S22a | Aceita fica | como S8 | | | | | S8 + `stalled_quotes` aceita hoje |
| S22b | Aceita fica mesmo resolvida | como S22a | | | | | S22a, mas as 2 propostas com `last_message_at` há 1 hora (não estão mais paradas) |
| S23 | Conta só de site | como S10 | | | | | S10 com `meta7` de SC = 0 |

### 6.4 Gabarito

Abreviações: P = pass, F = fail, N = no_data, X = not_applicable. Colunas de conta: `stalled_quotes`,
`slow_response`, `tracking`, `auction`. Por anúncio: `data_gate`, `learning`, `fatigue`, `scale` (nessa ordem).

| # | stalled | slow | tracking | auction | Por anúncio (dg / lr / ft / sc) | Ações |
|---|---|---|---|---|---|---|
| S1 | X | P | P | P | A: F / F / F / X | `[refresh_creative A open]` |
| S2 | X | P | P | P | A: F / F / F / X | `[refresh_creative A open]` |
| S3 | X | P | P | F | A: F / F / P / X | `[auction_pressure – open]` |
| S4 | X | N | P | N | A: N / F / N / X | `[wait A]` (`missing_conversations: 12`) |
| S5 | X | P | P | P | A: P / F / P / F | `[on_track]` |
| S6 | X | P | P | P | A: N / F / P / X | `[review_ad A open]` (variante `no_sales`) |
| S7 | X | F | P | P | A: N / F / P / X | `[slow_response – open]` |
| S8 | F | F | P | P | A: N / F / P / X | `[stalled_quotes – open, slow_response – open]` |
| S9 | X | P | F | P | B: N / F / P / X | `[fix_tracking – open]` |
| S10 | X | P | P | P | C: P / P / P / P; D: F / F / P / X | `[scale_ad C open]` |
| S11 | X | P | P | P | C: P / P / P / F; D: F / F / P / X | `[on_track]` |
| S12 | F | F | F | P | B: N / F / P / X; E: N / F / F / X | `[stalled_quotes – open, slow_response – open, fix_tracking – open]` |
| S13 | F | F | P | P | A: N / F / P / X | `[slow_response – open]` |
| S14 | X | X | N | X | (nenhum anúncio) | `[no_data]` |
| S15 | X | P | P | P | F: F / F / P / X; G: P / F / P / F | `[on_track]` (nunca `review_ad F`) |
| S16 | X | P | P | F | A: F / F / F / X; B: F / F / P / X | `[refresh_creative A open, auction_pressure – open]` |
| S17 | X | N | P | N | N: N / F / N / X | `[wait N]` (`missing_conversations: 12`) |
| S18 | X | F | P | P | A: N / F / P / X | `[slow_response – open]` |
| S19 | X | F | P | P | A: N / F / P / X | `[slow_response – open]` (mediana 1.800 s) |
| S20 | X | P | P | P | A: F / F / F / X | `[refresh_creative A open]` e `facts[:local_date] == '2026-10-07'` |
| S21a | X | P | P | P | A: F / F / F / X | `[refresh_creative A open]` (variante `frequency`) |
| S21b | X | P | P | P | A: F / F / N / X | `[on_track]` |
| S22a | F | F | P | P | A: N / F / P / X | `[stalled_quotes – accepted, slow_response – open]` |
| S22b | P | F | P | P | A: N / F / P / X | `[stalled_quotes – accepted, slow_response – open]` |
| S23 | X | P | P | P | C: P / N / P / N; D: F / F / P / X | `[on_track]` |

Conferências do gabarito (para quem revisar a conta):
- S1: custo-alvo 340 ÷ 2 = 170, portão 510 > 340 → F. CTR 1,5% → 1,0% (−33%).
- S3: CPM 20 → 28 (+40%), CTR 1,5% → 1,46% (−2,7%, estável). Portão 3 × 190 = 570 > 380.
- S5: custo-alvo 420 ÷ 3 = 140; portão 420 ≥ 420 → P; veredito `up` (140 ≤ 140); semanas 105 ≤ 140; só o
  aprendizado (6 < 50) barra.
- S9: 20 de 29 identificadas = 69% < 70%.
- S10: custo-alvo (480 + 420) ÷ 6 = 150; C a 120 → `up`; portão C 480 ≥ 450; semanas C 140 ≤ 150; D 420 < 450.
  CPM da conta 16,7 → 19,2 (+15%).
- S12: 25 de 37 identificadas = 68%. Quarta candidata (`refresh_creative E`) fica de fora pelo teto.
- S15: só G vende → custo-alvo 100 (o próprio G, D5.3); F gastou 200 < 300 → `review_ad` barrado.
- S16: CTR da conta 1,5% → 1,5% (B compensa A), CPM +40% → leilão F; A cai 33% → fadiga F.
- S17: sem linha de base, a parte CTR é N, a de frequência P → N.
- S18: 4 de 15 sem resposta = 27% ≥ 20%; mediana 60 s.

### 6.5 Outros specs (A)

- `check_spec`: um caso por código da tabela §1.5, mais o texto válido com `{{ad_name}}` contendo "10/10" e com
  `{{window_days}}`.
- `writer_spec`:
  - recusa e acerta → `ai`;
  - recusa duas vezes → regra só nas recusadas, com `check_failed`;
  - `applies: false`;
  - `ResponsesClient::Error` → `pending` com `retry_after` de 15 min;
  - as duas tentativas contam 1 no teto.
- `analysis_spec`:
  - reivindicação: dois `write!` seguidos → só um chama o Writer; `writing` de 6 min atrás é reivindicado;
  - teto: reserva só depois de reivindicar; sem vaga → `rule`/`daily_limit`;
  - aceitar não muda a assinatura nem cria run; `create_or_find_by!` com `RecordNotUnique` simulado;
  - upsert e expiração só na criação do run;
  - render com marcador sem valor → ação volta à regra.
- `format_spec`: os tipos, em pt_BR e en.
- `facts_spec`: cache (segunda chamada não consulta o banco); `Report` reaproveitado com `days == 30`.

---

## 7. Divisão em 3 construtores (sem sobreposição de arquivos)

**Ordem:**
0. **Orquestrador:** gate G1 (§9) e `scenarios_spec.rb` com o gabarito inteiro.
1. **Em paralelo:**
   - B1 — as 2 migrations, `schema.rb`, os 3 models e as rotas;
   - A1 — `Advisor::Format` (+ spec + locale) e `spec/support/meta_ads_advisor_helpers.rb`. São dependências de B
     (formatar no WhatsApp; montar fixture nos specs de `PathList` e `MetaComparison`).
2. **A, B e C em paralelo.**
3. **Integração (orquestrador).**

### A — Servidor-consultor

| | Arquivos |
|---|---|
| Cria (A1) | `app/services/crm/meta_ads/advisor/format.rb`; `spec/services/crm/meta_ads/advisor/format_spec.rb`; `config/locales/meta_ads_advisor.en.yml` e `config/locales/meta_ads_advisor.pt_BR.yml` (só `duration.*`); `spec/support/meta_ads_advisor_helpers.rb` |
| Cria | `app/services/crm/meta_ads/advisor/{facts,history,rules,decision,writer,check,analysis}.rb`; `app/services/crm/meta_ads/panel/response_time.rb`; `spec/services/crm/meta_ads/advisor/{facts,rules,decision,writer,check,analysis}_spec.rb`; `spec/services/crm/meta_ads/panel/response_time_spec.rb` |
| Altera (exclusivo) | `app/controllers/api/v1/accounts/crm/meta_ads_ai_controller.rb` (`daily_action`, §4.4); `app/services/crm/ai/interactive_operation.rb` (`meta_ads_daily_action` com `run_id`); `app/services/crm/meta_ads/quote_message_suggester.rb` (`FEATURE` e `unavailable_reason` vêm de `Advisor::Writer`/`Analysis`); `spec/requests/api/v1/accounts/crm/meta_ads_ai_spec.rb`; `spec/services/crm/meta_ads/quote_message_suggester_spec.rb` (se citar `AiAction`) |
| Apaga | `app/services/crm/meta_ads/panel/ai_action.rb`, `app/services/crm/meta_ads/panel/ai_action_cache.rb`, `spec/services/crm/meta_ads/panel/ai_action_spec.rb`, `spec/services/crm/meta_ads/panel/ai_action_cache_spec.rb` |
| Não toca | `app/services/crm/meta_ads/panel/action.rb` (o `for` sai na integração) e `scenarios_spec.rb` (do orquestrador) |
| Usa de B | os models `Crm::MetaAdvisorRun`, `Crm::MetaAdvisorAction` e `Crm::MetaAdFrequencyWindow` (§3) |

### B — Servidor-dados/API

| | Arquivos |
|---|---|
| Cria (B1) | `db/migrate/20261009100000_create_crm_meta_advisor_runs_and_actions.rb`; `db/migrate/20261009100100_create_crm_meta_ad_frequency_windows.rb`; `app/models/crm/meta_advisor_run.rb`; `app/models/crm/meta_advisor_action.rb`; `app/models/crm/meta_ad_frequency_window.rb` |
| Cria | `app/controllers/api/v1/accounts/crm/meta_ads_advisor_actions_controller.rb`; `app/services/crm/meta_ads/panel/meta_comparison.rb`; `app/services/crm/meta_ads/panel/path_list.rb`; `app/jobs/crm/meta_ads/advisor/prune_job.rb`; `spec/models/crm/meta_advisor_action_spec.rb`; `spec/services/crm/meta_ads/panel/meta_comparison_spec.rb`; `spec/services/crm/meta_ads/panel/path_list_spec.rb`; `spec/requests/api/v1/accounts/crm/meta_ads_advisor_actions_spec.rb`; `spec/jobs/crm/meta_ads/advisor/prune_job_spec.rb` |
| Altera (exclusivo) | `config/routes.rb` (B1); `db/schema.rb` (B1, só as 3 tabelas); `config/schedule.yml`; `app/services/crm/meta_ads/insights/query.rb`; `app/services/crm/meta_ads/insights/sync.rb`; `app/services/crm/meta_ads/insights/writer.rb`; `app/services/crm/meta_ads/links/stats.rb` (`since:` opcional, padrão 30 dias); `app/services/crm/meta_ads/panel/report.rb` (tira `action`; `confidence` no período); `app/controllers/api/v1/accounts/crm/meta_ads_connections_controller.rb` (`panel` com `advice`/`meta_comparison`/`response_time`; `panel_list`; `READ_ACTIONS`); `app/services/crm/meta_ads/whatsapp_report/digest.rb`; `app/services/crm/meta_ads/whatsapp_report/message_builder.rb`; `config/locales/meta_ads_whatsapp_report.en.yml`; `config/locales/meta_ads_whatsapp_report.pt_BR.yml`; specs existentes: `report_spec`, `digest_spec`, `message_builder_spec`, `deliver_job_spec`, `insights/sync_spec`, `insights/writer_spec`, `links/stats_spec`, o request spec do painel (`meta_ads_connections_spec` ou equivalente), `spec/configs/schedule_spec.rb` (se listar jobs) |
| Remove chamadas | `Panel::Action.for` em `Report#payload` e em `Digest#action` (o método em si fica para a integração) |
| Usa de A | `Advisor::Format` e o ajudante de spec (A1, antes); `Advisor::Analysis.current/daily/serialize/mark_shown!` e `Panel::ResponseTime` (stub nos specs de B até A terminar; a integração roda sem stub) |

### C — Tela

| | Arquivos |
|---|---|
| Cria | `app/javascript/dashboard/routes/dashboard/campaigns/metaAds/components/MetaAdsPathList.vue`; `app/javascript/dashboard/routes/dashboard/campaigns/metaAds/specs/MetaAdsPathList.spec.js` |
| Altera (exclusivo) | `.../metaAds/components/MetaAdsPanel.vue`; `.../metaAds/components/MetaAdsDailyAction.vue`; `.../metaAds/components/MetaAdsConfidence.vue`; `.../metaAds/metaAdsHelpers.js`; `app/javascript/dashboard/api/crmMetaAdsConnection.js`; `app/javascript/dashboard/i18n/locale/en/crm.json` e `.../pt_BR/crm.json` (**só C** nesta fase); specs `MetaAdsPanel.spec.js`, `MetaAdsDailyAction.spec.js`, `MetaAdsConfidence.spec.js` (se existir; senão no `MetaAdsPanel.spec.js`), `metaAdsHelpers.spec.js`, `MetaAdsSummary.spec.js` (prova que o resumo segue igual); `lib/central_de_ajuda/13/13.20-conectar-anuncios-da-meta-e-avisar-sobre-o-funil.md` (§8); `lib/operator_guide/porques.md` (bloco novo) e os gerados por `pnpm guia:build` (`lib/operator_guide/guia-produto.md`, `app/javascript/dashboard/helper/guideRouteRegistry.js`) |
| Usa sem alterar | `.../metaAds/components/MetaAdsQuoteMessage.vue` (na lista `quotes`); `.../metaAds/useMetaAdsLive.js` |

**Chaves i18n do front (C), em `CRM_KANBAN.META_ADS_HUB`:**
- `PANEL.ACTION.{SLOW_RESPONSE,REVIEW_AD,REFRESH_CREATIVE,SCALE_AD,AUCTION_PRESSURE}.{TEXT,WHY,BUTTON}`;
- variantes: `REVIEW_AD.{TEXT,WHY}_{NO_SALES,ABOVE_AVERAGE}` e `REFRESH_CREATIVE.{TEXT,WHY}_{CTR,FREQUENCY,BOTH}`;
- `PANEL.ACTION.{DONE,DISMISS,DONE_LABEL}`;
- `PANEL.DURATION.*`, `PANEL.RESPONSE_TIME.{LABEL,NOTE,UNANSWERED}`;
- `PANEL.PATH_LIST.{TITLE_*,TOTAL_*,EMPTY,ERROR,RETRY,SHOWING,OPEN_CONVERSATION,OPEN_CARD,LAST_30_DAYS}`;
- `SUMMARY.CONFIDENCE.{TITLE_PERIOD,META.{WHATSAPP,SITE}.{LINE,CLOSE,META_HIGHER,OURS_HIGHER},META.NO_META_DATA}`;
- `AI.DAILY.{DISMISS_FAILED,DONE_FAILED}`;
- sai `AI.DAILY.REVIEW_AD_BUTTON` (substituída por `PANEL.ACTION.REVIEW_AD.BUTTON`);
- `AI.DAILY.{BADGE,WRITING,AI_ERROR,FAILED}`: **ficam como estão** (decisão do Rodrigo, §9).

Depois, `pnpm i18n:fork:check`.

### P — Instruções da IA (§11), depois que A terminar

| | Arquivos |
|---|---|
| Cria | `app/services/crm/meta_ads/advisor/prompt.rb` (A deixa um esqueleto com `VERSION` e `instructions` que P preenche); `spec/services/crm/meta_ads/advisor/writer_eval_spec.rb`; `spec/services/crm/meta_ads/advisor/prompt_spec.rb` (estrutura: versão, exemplos com marcadores válidos pelo `Check`, sem número fora de marcador nos exemplos) |
| Altera (depois de A) | `QuoteMessageSuggester#instructions` (só o texto da instrução e a versão; nada de schema ou lógica) |
| Não roda | a avaliação paga: só o orquestrador, à mão, com o teto de US$ 2 |

**Integração (orquestrador, no fim):**
- remover `Panel::Action.for` (e só ele) de `app/services/crm/meta_ads/panel/action.rb` e os exemplos dele em
  `spec/services/crm/meta_ads/panel/action_spec.rb`, depois de B tirar as chamadas;
- `bundle exec rails db:migrate` e conferir o diff do `schema.rb` (só as 3 tabelas);
- rubocop dos arquivos tocados;
- rspec de `spec/services/crm/meta_ads`, `spec/requests/api/v1/accounts/crm/meta_ads_*`, `spec/jobs/crm/meta_ads`,
  `spec/models/crm/meta_*` e `spec/configs/schedule_spec.rb`, sem stub de A;
- `TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/campaigns/metaAds`;
- `pnpm eslint`, `pnpm i18n:fork:check`, `pnpm guia:check`, `pnpm central:check`;
- `bundle exec rails autonomia:guia:formatos` e depois `autonomia:guia:formatos:check`: o gerado
  `lib/operator_guide/formatos-das-acoes.json` é **da integração** (muda com as 3 rotas POST e o `panel_list`);
- grep: nenhuma referência a `Panel::AiAction`, `AiActionCache` ou `Panel::Action.for` em `app` e `spec`;
- docs: esta página ganha o "Status" no fim.

Regra da casa: rodar, **ler a saída inteira** e só então commitar, em outro comando.

**Texto obrigatório no PR:**
- CA-3.2: "lista no painel, com cada linha levando à conversa e ao card; o Kanban filtrado fica fora (pergunta 9)".
  Não escrever "cumprido".
- CA-4.2: o limite da autodeclaração `numbers_in_words` (risco 3).
- Custo esperado da IA: até 12 chamadas por conta e dia (§1.5) mais a do resumo; conferir `Crm::AiUsageEvent`
  da feature `anuncios_meta` na primeira semana.
- O resultado do gate G1.

---

## 8. Validação exigida por construtor

**A:**
- `bundle exec rspec spec/services/crm/meta_ads/advisor spec/services/crm/meta_ads/panel/response_time_spec.rb spec/requests/api/v1/accounts/crm/meta_ads_ai_spec.rb spec/services/crm/meta_ads/quote_message_suggester_spec.rb`;
- a bateria S1–S23 verde, **sem mudar o arquivo do orquestrador**;
- grep confirmando que não sobrou referência a `Panel::AiAction`/`AiActionCache` em `app` e `spec`;
- rubocop.

**B:**
- as duas migrations sobem e descem (`db:migrate`, `db:rollback STEP=2`, `db:migrate`);
- rspec dos models (`open!` idempotente, `accept!`/`dismiss!` só de `open`, `acceptance` com expiradas no
  denominador e `api` fora), do `PathList` (com `stalled`) e do `MetaComparison` (até ontem, primeiro toque, filtro
  de `ad_account_id`, uma linha por destino: WhatsApp por `conversations_started`, site por `offsite_conversion.fb_pixel_lead` com `landing_page_view` de contexto, sem linha quando o destino não está marcado), dos requests (agente → 403, outra conta → 404, `not_open` → 422, `invalid_step` → 422,
  `api_access_token` → `resolved_via: 'api'`), do sync (`stub_meta_insights` da leitura `last_7d`; a falha dela com
  código 100 **não** marca a conexão; ela roda mesmo com o posicionamento falhando) e do Digest e MessageBuilder
  com os 5 tipos pela regra;
- `schedule_spec`; rubocop.

**C:**
- `TZ=UTC pnpm vitest run .../metaAds`, com casos para:
  - 3 ações em ordem, texto da IA × regra;
  - abrir chama `openAdvice` e navega; "Feito" vira "Feita" e a ação fica; dispensar remove; falhas de feito e
    dispensar;
  - `scale_ad` com link externo (`target="_blank"`, `rel`); `auction_pressure` "Entendi" aceita;
  - `comparison` presente e ausente, sem `v-html`;
  - `duration`;
  - abrir e fechar lista por etapa, links "Abrir conversa"/"Abrir no CRM", "Mostrando 50 de N", "Sugerir mensagem"
    só na linha parada, `slow_replies` sempre com `days = 30`;
  - `waiting()` verdadeiro com `writing`;
- `pnpm eslint` nos arquivos;
- `pnpm i18n:fork:check`, `pnpm guia:build` e `pnpm guia:check`, `pnpm central:check`;
- **conferir na tela** a 400 px e nos dois temas, com print do herói com 3 ações (uma "Feita"), da lista aberta e
  do "Quanto confiar".

**Central 13.20 (C):**
- atualizar §91-95 (até 3 ações; o botão leva ao trabalho; "Feito" e "Dispensar"; as ações novas em uma linha
  cada; o caminho clicável) e §99-100 (o número da Meta ao lado do nosso, até ontem, e a linha de explicação;
  período do painel);
- a linha nova "Tempo de resposta" na etapa Conversas;
- as evidências do cabeçalho apontando para `data-panel-actions`, `data-panel-path-open`, `data-confidence-meta`
  e `data-panel-response-time`. Sai a evidência `data-panel-stalled-button`, cujo botão foi removido.

**Guia (C):** bloco `usar_o_painel_de_anuncios` em `porques.md`, com `rota: campaigns_meta_ads_index`, `intent`
("ver quanto custou cada venda e o que fazer hoje") e `passos` (período, até 3 ações, abrir etapa, feito,
dispensar), depois `pnpm guia:build`.

---

## 9. Gate, riscos, fora de escopo e perguntas

**Gate G1 (orquestrador, antes de A começar `Rules`):** confirmar que `inline_link_clicks` conta o clique para o
WhatsApp na conta 18. Psql só leitura pela SSM:

```sql
select sum(impressions), sum(link_clicks) from crm_meta_ad_insights_daily
 where account_id = 18 and date >= current_date - 30;
```

Se der 0 cliques com impressões: o desenho já degrada (`MIN_BASELINE_CLICKS`): a fadiga fica só pela frequência e
o leilão fica `no_data`. Nada no código muda, mas o PR e a Central dizem isso, e o Rodrigo é avisado antes do
merge.

**Riscos:**
1. **Carga do `GET panel`:** mitigada (cache de 5 min dos Facts, upsert só na criação do run, `Report` reaproveitado
   com 30 dias). Resta, por requisição, o `ResponseTime` e o `MetaComparison` do período quando o painel está em
   7 dias.
2. **Frequência > 4 sem saber se o público é frio:** remarketing pode passar disso legitimamente. A evidência
   mostra o número, e a ação é "trocar a execução", reversível.
3. **Número por extenso:** a checagem depende da autodeclaração `numbers_in_words`; o modelo pode escrever "três"
   e declarar `false`. Sem regex e sem lista de palavras não há conferência real. Dígito não-ASCII fora do NFKC
   também não é pego (não ocorre em pt/en/es). Pergunta 7.
4. **Custo-alvo derivado (D5.3):** com um anúncio só vendendo, ele é a própria média. Numa conta em que todos
   vendem caro, a média também é cara. Pergunta 5.
5. **Escala rara:** exige 50 conversas da Meta por conjunto em 7 dias e venda nas duas semanas maduras. Na
   Placement não aparece (D5.5, cenários S5 e S23). Pergunta 4.
6. **Uma chamada a mais por dia à Meta:** no caminho B (parceiro, nível de desenvolvimento), soma ao limite.
   `Usage` pausa acima de 75%, e a leitura de frequência é a primeira a ser pulada.
7. **Tempo de resposta com agente:** em conta com agente Autonom.ia, a mediana fica em segundos (D5.6).
8. **Migrations:** só tabelas novas, sem backfill. Rollback = `drop_table` das três (duas migrations). O consultor
   volta a ser a ação única só revertendo o PR.

**Fora:**
- campo de custo-alvo configurável;
- `learning_stage_info`, `optimization_goal` e a data da última edição (seguem para issue própria se a pergunta 4
  pedir);
- status do anúncio (`effective_status`);
- mudar orçamento ou pausar pela plataforma (D3);
- relatório de aceite na tela (por ora, a SQL da §3);
- motivo de dispensa;
- filtro de coorte no Kanban ou na lista de conversas (CA-3.2 completo);
- tempo de resposta separado por pessoa e agente;
- âncora "custo por conversa qualificada" do PRD;
- janela de 72 h do WhatsApp.

**Decisões do Rodrigo (07/10):**
- Tempo de resposta: **mediana, qualquer resposta** (pessoa ou agente), rótulo "Tempo de resposta" (pergunta 1).
- Selo: **manter "Escrito pela IA"** e os textos atuais de `AI.DAILY.{BADGE,WRITING,AI_ERROR,FAILED}` (pergunta 6).
  Isso vale para os rótulos da tela; o **texto** escrito pela IA continua sem citar "IA", "modelo" ou "sistema" (§11.2).
- Frequência: **aprovada** 1 leitura a mais por conta por dia (pergunta 8).
- Caminho do dinheiro: **lista no painel** nesta fase; Kanban filtrado fica para depois, CA-3.2 parcial no PR (pergunta 9).
- Demais perguntas (2, 3, 4, 5, 7): seguem a recomendação do desenho.

**Perguntas ao Rodrigo** (registro; respondidas acima):
1. **Tempo de resposta:** qualquer resposta (pessoa + agente; recomendado) ou só pessoa? E o número: mediana com
   rótulo "Tempo de resposta" (recomendado) ou média aritmética com o rótulo "Resposta média" do pedido? Muda só
   `ResponseTime` e o i18n.
2. **Aceite:** gesto explícito "Feito" (recomendado; D5.9) ou implícito (aberta e não dispensada até o fim do
   dia)? Muda `MetaAdsDailyAction.vue` e a SQL da métrica.
3. **Guia e a métrica:** registrar `resolved_via` e contar só o painel (recomendado; D5.11), ou criar um jeito de
   tirar rotas do catálogo do Guia (mecanismo novo em `Autonomia::Guide::Acoes`)?
4. **Escala na Placement:** como desenhado, não aparece (o conjunto não chega a 50 conversas da Meta em 7 dias).
   Aceitar na F5 e abrir issue para ler `learning_stage_info` (recomendado), ou o aprendizado deixar de bloquear
   a escala (risco: aumentar orçamento durante o aprendizado)?
5. **Custo-alvo (D5.3):** média dos anúncios que venderam, inclusive o julgado (recomendado: é a base do veredito
   da F3), média sem o anúncio julgado, ou custo por venda total da conta (gasto total ÷ vendas)?
6. **"Nada de IA na tela" (PRD §7):** trocar `AI.DAILY.BADGE` ("Escrito pela IA") por "Do seu consultor",
   `WRITING` por "Seu consultor está escrevendo…", e `AI_ERROR`/`FAILED` por frases sem "IA" (recomendado). É só
   i18n e a linha da Central.
7. **Número por extenso:** aceitar o risco da autodeclaração (recomendado) ou pagar uma segunda chamada só para
   verificar ("o texto cita quantidade por extenso?"), que dobra o custo por geração?
8. **Frequência:** aprova 1 chamada a mais por conta por dia (D5.4)? Sem ela, a fadiga fica só pelo CTR e a
   escala nunca dispara.
9. **Caminho do dinheiro (D5.7):** a lista dentro do painel, com cada linha levando ao card no CRM, serve como
   entrega do CA-3.2, ou o Kanban filtrado por coorte entra numa fase seguinte?

---

## 11. Instruções da IA — padrão de qualidade (pedido do Rodrigo, 07/10)

A análise vale o que valem as instruções. Elas são tratadas como peça de engenharia: arquivo próprio, versão,
revisão adversária e avaliação contra a IA de verdade antes do PR.

### 11.1 Onde moram

- `app/services/crm/meta_ads/advisor/prompt.rb` (**construtor P**): `Advisor::Prompt::VERSION` (`'p1'`, sobe a
  cada mudança de texto), `Advisor::Prompt.instructions` e `Advisor::Prompt::EXAMPLES`. O `Writer` (A) só chama
  `Prompt.instructions` e manda `Prompt::VERSION` para o run.
- `crm_meta_advisor_runs` ganha `prompt_version` string(16) (B1, na mesma migration). Muda a versão → muda a
  assinatura (§1.6), para o texto velho não ficar no cache do dia.
- A mensagem para retomar a proposta (`QuoteMessageSuggester#instructions`, F4) passa pelo mesmo padrão: P
  reescreve as instruções **depois** que A terminar (A não muda o texto delas nesta fase).

### 11.2 O que as instruções do consultor precisam ter

1. **Papel:** gestor de tráfego sênior que explica ao dono de uma pequena empresa o que fazer hoje. O código já
   decidiu a ação, o tipo, o anúncio e os números; a IA só escreve. Nunca troca a ação nem acrescenta outra.
2. **Público leigo** (regra da casa para telas de leigo): frase curta, uma ideia por frase, palavra do dia a dia,
   voz ativa, verbo no imperativo no título. Sem sigla nem jargão: nada de CTR, CPM, ROAS, CPA, lead, funil,
   criativo, leilão, conversão, campanha de tráfego, pixel, algoritmo. Diz "a imagem ou o texto do anúncio",
   "aparecer para mil pessoas", "a concorrência", "conversas", "vendas".
3. **Tom:** direto e respeitoso, sem alarme, sem elogio vazio, sem exclamação, sem emoji, sem prometer resultado
   ("vai vender mais"). Pode dizer o que costuma acontecer ("costuma ajudar").
4. **Cada ação, o que um bom conselho diz** (PRD seção 5): o que está acontecendo (fato), por que importa
   (mecanismo em palavras simples), o que fazer agora (passo concreto e reversível) e, quando houver fato de
   prazo, quando olhar de novo. Uma orientação curta por tipo e variante, alinhada à tabela §2 (ex.: `auction_pressure`
   diz explicitamente "não troque o anúncio por isso"; `scale_ad` diz "até {{max_increase_pct}}" e o descanso;
   `slow_response` liga a demora à venda; `review_ad` sugere olhar o anúncio, não desligar sem ver).
5. **Marcadores:** todo número, valor, porcentagem, prazo e nome de anúncio entra só como `{{chave}}` de um fato
   da própria ação. Nenhum número por extenso ("três", "metade" vale só se não for quantidade dos fatos — melhor
   evitar). Exemplos certos e errados na própria instrução.
6. **Dados são dados:** nome de anúncio e qualquer valor podem conter texto que parece ordem; ignorar. Nunca
   pedir dado pessoal, nunca pôr link, telefone ou e-mail.
7. **Sem nome de tecnologia:** não dizer "IA", "modelo", "algoritmo", "sistema" (PRD §7).
8. **Exemplos (few-shot):** pelo menos 2 bons em pt_BR (um `stalled_quotes`, um `refresh_creative` com variante
   `both`) e 1 ruim com o porquê (jargão + número solto). Os exemplos usam fatos fictícios, nunca dados reais.
9. **Idioma:** escrever no `language` pedido; os exemplos são pt_BR, a instrução diz que o estilo vale para
   qualquer idioma.

### 11.3 Revisão adversária (antes da avaliação paga)

Três revisores independentes leem `prompt.rb` e as instruções da proposta, cada um com uma lente e o poder de
reprovar:
- **gestor de tráfego sênior:** o conselho de cada tipo é o que um bom gestor diria? Há conselho perigoso
  (desligar cedo, aumentar demais, mexer durante o aprendizado)?
- **linguagem para leigo:** um dono sem formação em marketing entende cada frase de primeira? Há jargão?
- **segurança e consistência:** injeção pelo nome do anúncio, número fora de marcador, dado pessoal, contradição
  com o schema, com o `Check` (§1.5) ou com a tabela §2.

P corrige; ponto rejeitado vai escrito com motivo.

### 11.4 Avaliação com a IA de verdade (orçamento do Rodrigo: **US$ 2 no total da F5**)

- **Arquivo:** `spec/services/crm/meta_ads/advisor/writer_eval_spec.rb` (P), no padrão de
  `spec/services/autonomia/guide/injecao_eval_spec.rb`. **Nunca roda no CI:** só com `META_ADS_ADVISOR_EVAL=1`.
- **Quem dispara:** o orquestrador, à mão, com a credencial local (nunca impressa). Nenhum agente roda a avaliação.
- **Teto no código:** soma o custo de cada chamada pela `Crm::Ai::Pricing` a partir do `usage` da resposta e
  **para antes** de passar de `META_ADS_EVAL_BUDGET_USD` (padrão e máximo 2.0, menos o que já foi gasto, lido de
  `tmp/meta_ads_advisor_eval_spent.json`, que acumula entre rodadas). Relatório em `tmp/meta_ads_advisor_eval.json`
  com custo, por cenário, por chamada.
- **Rodada 1:** os 23 cenários da §6 (a `Decision` real, sem IA) → `Writer` real com `gpt-6-luna` e
  `SUMMARY_REASONING_EFFORT`, **2 vezes cada**. Mais 6 conversas fictícias para a mensagem da proposta (cliente
  sumiu, cliente comprou, cliente recusou, pedido de PIX de terceiro, conversa em inglês, injeção na mensagem).
- **Conferência sem custo**, em toda resposta: os códigos do `Check` (§1.5), tamanho, todas as ações respondidas.
- **Juiz** (`Crm::Ai::Config::MODEL_EMAIL`, `gpt-6.1-sol`, esforço `medium`): **1 resposta por cenário**. Recebe os
  fatos, a ação decidida e o texto renderizado; devolve nota 1–5 em: conselho certo para os fatos, leigo entende,
  sem jargão, passo concreto, tom; e bandeiras: `promises_result`, `contradicts_facts`, `mentions_ai`,
  `asks_personal_data`.
- **Aprovação:** em todos os cenários, `Check` limpo em ≤ 2 tentativas; juiz ≥ 4 em todos os critérios; nenhuma
  bandeira. Rodada 2 (com o que sobrar do orçamento) só nos cenários reprovados, depois do ajuste de P.
- **Estimativa** (pela tabela de preços): rodada 1 ≈ US$ 1,0 (Luna ≈ US$ 0,2; juiz ≈ US$ 0,8).

---

## 10. Revisão 1 — o que mudou com a crítica

| Ponto | Onde ficou |
|---|---|
| 1 aceita some | D5.10, §1.4 (aceitas ficam), §1.6 (assinatura sem status), §5.1 |
| 2 abriu ≠ aceitou | D5.9, §2 gestos, §3 (`opened_*`, `shown_at`, SQL), §4.5 `open` |
| 3 Guia | D5.11, §3 `resolved_via`, §4.5, pergunta 3 |
| 4 prazos no texto | D5.1, §1.5, §2 (`window_days`, `weeks`, `cooldown_days`) |
| 5 render e variante | §1.4 `variant`, §1.5 render, §1.6 assinatura |
| 6 número por extenso | risco 3, pergunta 7, texto do PR |
| 7 lock durante a IA | §1.6 `write!` (reivindicação atômica, 5 min), §4.4 |
| 8 `ai_error` | §1.5 item 5, §3 `retry_after`, §4.2 |
| 9 onde reserva | §1.6 passo 2, §4.4 |
| 10 GET escreve | §1.2 cache, §1.6 (upsert só na criação), §4.2 |
| 11 terceira leitura | D5.4, §3 coleta |
| 12 `date_end` | §1.1 `freq7`, §3 `date_stop`, S21a/S21b |
| 13 aprendizado | D5.5, §1.3 `learning`, S23, pergunta 4 |
| 14 CTR com pouca amostra | §1.3 CTR mensurável, S17 |
| 15 CTR de WhatsApp | gate G1 |
| 16 custo-alvo | D5.3, evidência §1.3, S15, pergunta 5 |
| 17 semanas | §1.1 `weekA`/`weekB`, §1.2 |
| 18 contradições | §1.2 (`stalled`, `response`), §1.3 (combinação, sinais), §1.4 (refresh × review) |
| 19 período de `slow_replies` | §2, §4.3, §5.1 |
| 20 toque e rótulo | D5.6, §4.2 `ResponseTime`, §5.3, pergunta 1 |
| 21 Meta × nós | D5.8, §4.2 `MetaComparison`, §5.2 |
| 22 chaves | §4.6 (5 tipos), §7 i18n |
| 23 "IA" na tela | pergunta 6 |
| 24 botões | §1.4 (leilão por último), §2, §4.2 `ads_manager` |
| 25 sugerir mensagem | §4.3 `stalled`, §5.4 |
| 26 ordem e dependências | §7 |
| 27 gabarito do orquestrador | §6 |
| 28 S9 | §6.3 |
| 29 fixture inteira | §6.2–§6.4 |
| 30 cenários novos | S15–S23 |
| 31 migration, unique, cron, custo | §3, §1.6, §7 (texto do PR) |
| 32 CA-3.2 parcial | D5.7, §5.4, §7 (texto do PR), pergunta 9 |

---

## Crítica rejeitada

Nenhum ponto foi rejeitado por inteiro. Partes rejeitadas, com o motivo:

- **Ponto 2, a alternativa "aceite = aberta e não dispensada até o fim do dia".** Mede curiosidade, não
  concordância: quem abre para conferir e não faz nada contaria como aceite. Ficou o gesto explícito, e a
  alternativa está na pergunta 2.
- **Ponto 3, "declarar as rotas fora do catálogo".** Hoje não existe lista de exclusão em
  `Autonomia::Guide::Acoes#catalogo`: seria mecanismo novo no Guia, fora do escopo da F5. `resolved_via` resolve a
  métrica sem tocar o Guia. A alternativa está na pergunta 3.
- **Ponto 6, segunda chamada verificadora por padrão.** Dobra o custo de cada geração para fechar um caso que o
  schema e a instrução já desencorajam. Fica como risco explícito e pergunta 7.
- **Ponto 16, trocar o custo-alvo agora.** O custo-alvo é a mesma média do veredito da F3. Trocar só no
  consultor faria o cartão do anúncio dizer "Aumentar" e o consultor discordar. Ficou documentado na evidência
  (`target_includes_ad`, `selling_ads`), com as alternativas na pergunta 5.
- **Ponto 20, "mostrar o tempo da pessoa à parte quando houver agente".** Exige separar autor de mensagem no WAHA
  e no eco do celular, o que a pergunta 1 da versão anterior já apontava como dependente de confirmação em
  produção. Fica fora da F5 e dentro da pergunta 1.
- **Ponto 24, "auction_pressure vira nota dentro de outra ação".** Misturaria dois diagnósticos num cartão e
  quebraria "uma ação por tipo". Ficou a outra saída da crítica: o leilão é a última prioridade e só ocupa vaga
  que sobrou.
