# Anúncios da Meta — F3a: o painel do dia a dia (#1088)

Mockup aprovado: jornada "O painel do dia a dia" (https://claude.ai/artifact/2ngVVCs7CVYJhPfE83Ty85#j2-1).
Base de dados: F2a (gasto por anúncio e dia) e F2b (ligação conversa → anúncio), em `docs/crm/anuncios-meta-f2.md`.

Depois de conectada, Campanhas › Anúncios da Meta abre em **Resultado** (o painel); **Conexão** mostra o resumo da
conexão. A aba fica no endereço (`?aba=resultado|conexao`). Conexão que precisa de atenção abre na conexão.

## De onde sai cada número

`GET crm/meta_ads_connection/panel?days=7|30` (admin) → `Crm::MetaAds::Panel::Report`. Também pede a leitura de
hoje, como o resumo (atualiza a cada 2 min com a aba visível; tempo real por `crm.meta_ads.insights_updated`).

| Número | Fonte |
|---|---|
| Investido | soma de `crm_meta_ad_insights_daily` da conta de anúncios, últimos N dias no fuso dela |
| Conversas | conversas com ligação em `crm_meta_ad_links` tocadas no período |
| Propostas | cards dessas conversas abertos numa etapa `opportunity`/`negotiation` (passo 4) ou ganhos |
| Vendas | cards ganhos dessas conversas (coorte: o que virou, não o que fechou no período) |
| Por anúncio | cada conversa conta para o anúncio do primeiro toque identificado do período |

## Veredito (CA-3.2)

`Crm::MetaAds::Panel::Verdict`: menos de 20 conversas → "Ainda é cedo"; nenhuma venda → "Revisar o anúncio";
1–2 vendas → "Sinal inicial"; 3+ vendas → custo por venda até a média da conta "Aumentar", 30% acima "Revisar",
entre os dois "Manter". Sempre em palavras.

## Ação do dia (CA-3.3)

`Crm::MetaAds::Panel::Action`, por ordem: propostas paradas há mais de 3 dias (abre a lista com "Abrir
conversa") → menos de 70% das conversas com anúncio identificado (leva ao passo 3) → aguardar (quantas conversas
faltam para o veredito) / tudo com veredito / sem dado. Cada uma traz o porquê com os números. A versão escrita
pela IA é da F4.

## Imagem do anúncio

O cartão mostra o anúncio inteiro, no formato dele (quadrado, vertical ou horizontal), sem corte; sem imagem,
um quadrado neutro. A imagem fica em `crm_meta_ad_objects.thumbnail_url`.

- **De onde vem:** `Crm::MetaAds::AdImages` lê `act_X/ads` com `creative{id,image_url,thumbnail_url}` (até 10
  páginas de 100). `image_url` é a imagem original. Anúncio em vídeo não tem: pede a miniatura do criativo em
  1080 px, no máximo 30 vídeos por rodada. Só https. O `NameResolver` também prefere `image_url` à miniatura de
  64 px quando busca o nome de um anúncio; quando só vem a miniatura (vídeo), ela preenche linha sem imagem e
  nunca passa por cima da de 1080 px que o `AdImages` gravou (`COALESCE` do lado do `NameResolver` também).
- **O que não apaga:** nome ou imagem que a Meta não mandou mantêm o que a linha já tinha (`COALESCE`). A carga
  não mexe em `fetched_at` nem na prévia: anúncio novo continua indo ao `NameResolver`, que traz a prévia.
- **Quando renova:** `Crm::MetaAds::AdImagesJob`, uma vez por dia por conexão (chave no Redis de 24 h): na rodada
  das 4h (`recent`) e na primeira abertura da tela no dia. Se a Meta recusa ou o job quebra, tenta de novo depois de
  30 min. Conta pausada por limite de uso não enfileira; token recusado ou acesso perdido seguem a regra da coleta
  (`Insights::Failure`).

## F3b: o anúncio por dentro

`GET crm/meta_ads_connection/panel_ad?ad_id=<id>&days=7|30` (admin; agente recebe 403) →
`Crm::MetaAds::Panel::AdDetail`. Só banco: abrir o anúncio **não** chama a Meta nem pede leitura de hoje — o
painel por trás dele já pediu. Sem conexão, sem conta de anúncios ou anúncio sem gasto nem conversa no período
(inclusive anúncio de outra conta): `{ ad: null }`.

| Campo | Regra e porquê |
|---|---|
| `spend`, `conversations`, `quotes`, `sales`, `sales_value`, `cost_per_sale`, `verdict` | a mesma linha do anúncio em `Panel::Report#ads`. O detalhe lê do Report em vez de recalcular: o número da tela do anúncio nunca diverge do cartão em que a pessoa clicou |
| `account_average_cost_per_sale` | `Report#average_cost_per_sale`: custo por venda da conta só com os anúncios que venderam; `null` enquanto nenhum vendeu |
| `reason` | `Panel::Verdict.reason`, da mesma regra do veredito: `early` (com `missing_conversations` para 20), `no_sales` (20+ conversas, nenhuma venda), `signal` (1–2 vendas), e com 3+ vendas `below_average` / `near_average` / `above_average` (aumentar / manter / revisar), com `difference` = distância do custo por venda até a média, em dinheiro |
| `daily` | todos os dias do período, zeros incluídos (dia sem gasto é informação: "o anúncio parou"). Gasto de `crm_meta_ad_insights_daily`; a conversa cai no dia do toque que a deu ao anúncio (`Cohort#touches`), no fuso da conta de anúncios — o mesmo fuso em que a Meta conta o gasto |
| `quotes_list` | cards de proposta/venda das conversas do anúncio no período (mesma coorte do painel), abertos primeiro pela espera mais antiga (é quem pede retomada), depois os ganhos; no máximo 20 |
| `campaign_name`, `adset_name` | pelo cache de nomes (`crm_meta_ad_objects`); o id vem do anúncio no cache ou, se ele ainda não foi resolvido, do gasto do período |
| `preview_url`, `thumbnail_url` | `crm_meta_ad_objects` do anúncio |

## Fora (F4)

IA na ação do dia, mensagem sugerida, resumo das 8h e alertas no WhatsApp (F4).

## Validação depois do deploy (só leitura)

```sql
select sum(spend) from crm_meta_ad_insights_daily where account_id = 18 and date >= current_date - 29;
select count(distinct conversation_id) from crm_meta_ad_links where account_id = 18 and touched_at >= current_date - 29;
```

Os dois têm de bater com "Investido" e "Conversas" do painel de 30 dias.
