# Anúncios da Meta — F2a: coleta de gasto e resultado por anúncio (#1073)

Plano aprovado: https://claude.ai/artifact/KbprboEwQim7guhh64o6dU · épico #1047 · F1 em `docs/crm/anuncios-meta-f1.md`.

A F2a traz da Insights API da Meta o gasto, as impressões, os cliques e as conversas iniciadas de cada anúncio,
um dia por linha, e o mesmo por posicionamento. É a base do painel (F3) e do consultor (F4). A ligação conversa →
anúncio é a F2b.

## Tabelas (do fork, aditivas)

| Tabela | Uma linha por | Observação |
|---|---|---|
| `crm_meta_ad_insights_daily` | conta · conta de anúncios · anúncio · dia | gasto, impressões, alcance, frequência, cliques no link, conversas iniciadas, `actions` cru, `attribution_window` |
| `crm_meta_ad_placements_daily` | … · dia · plataforma · posição | lida só na carga diária e na de 90 dias |

`crm_meta_ads_connections` ganhou `insights_synced_at` (última leitura de hoje) e `insights_backfilled_at` (fim
da carga de 90 dias). Gravação sempre por upsert no índice único: reler um dia sobrescreve, nunca duplica.

Valores na moeda e no fuso da conta de anúncios, sem conversão. Janela de atribuição fixa em `7d_click`: as janelas
por visualização (7 e 28 dias) saíram da API em 12/01/2026 e voltariam vazias sem erro.

## Quando lê

| O quê | Quando | Escopo |
|---|---|---|
| Carga de 90 dias | ao escolher a conta de anúncios; se faltar, na rodada das 4h | relatório assíncrono (`POST act_<id>/insights`, `date_preset=last_90d`), por anúncio e depois por posicionamento |
| Hoje | a cada 30 min (`crm_meta_ads_insights_today_job`) | `date_preset=today`, por anúncio |
| 3 dias anteriores | 07:00 UTC = 4h de Brasília (`crm_meta_ads_insights_recent_job`) | `date_preset=last_3d`, por anúncio e por posicionamento |
| Ao abrir a tela | `POST crm/meta_ads_connection/insights`, se o número de hoje tiver mais de 5 min | hoje |

Uma chamada por conta de anúncios por rodada (`level=ad`, `time_increment=1`, sem `ids`). Só contas com
`meta_ads_hub` ligado e conta de anúncios escolhida. Cada escopo tem uma trava por conexão no Redis
(`crm:meta_ads:insights:lock:<id>:<escopo>`, 10 min): várias aberturas da tela geram uma leitura só. O fim da leitura
de hoje chega à tela pelo evento `crm.meta_ads.insights_updated`, só para administradores.

Os nomes de anúncio, conjunto e campanha que vêm junto renovam o cache `crm_meta_ad_objects` (sem tocar na prévia
nem na miniatura).

## Limite de uso e erros

`Crm::MetaAds::Insights::Usage` lê `x-business-use-case-usage`, `x-fb-ads-insights-throttle` e `x-app-usage`.
A partir de 75%, ou com erro de limite (4, 17, 32, 613, 80000–80014), pausa a conta de anúncios pelo tempo que a
Meta indicar (mínimo 5 min, padrão 15 min) em `crm:meta_ads:insights:pause:<ad_account_id>`. Limite nunca marca a
conexão como inválida; vai para o log como `[MetaAdsInsights] pause …`.

| Resposta da Meta | Efeito |
|---|---|
| limite | pausa, conexão intacta |
| token recusado (190) | `mark_invalid!` (no modo parceira, só o código) |
| sem permissão / objeto inexistente na conta | `status=invalid`, `last_error=ad_account_access_lost`; o resumo mostra o motivo e "Conectar de novo" |
| qualquer outra | passageira; fica no log `[MetaAdsGraph]` e a próxima rodada tenta de novo |

## Validação depois do deploy (só leitura)

```sql
-- linhas da Placement por dia, últimos 7 dias
select date, count(*), sum(spend), sum(conversations_started)
from crm_meta_ad_insights_daily where account_id = 18 group by date order by date desc limit 7;
-- carga e última leitura
select insights_backfilled_at, insights_synced_at, status, last_error from crm_meta_ads_connections where account_id = 18;
-- total de 30 dias, para comparar com o Gerenciador de Anúncios (CA-2.7)
select sum(spend) from crm_meta_ad_insights_daily where account_id = 18 and date >= current_date - 30;
```

Logs: `[MetaAdsInsights]` (pausa, carga) e `[MetaAdsGraph]` (recusa da Meta, já sem token).

## Rollback

1. Reverter o PR (o código novo para de ler; as tabelas ficam sem uso).
2. Se for preciso tirar o esquema: `bin/rails db:migrate:down VERSION=20261006200000` — apaga as duas tabelas e as
   duas colunas. Os dados são reconstruíveis pela carga de 90 dias; nada de outra tabela é tocado.
3. Snapshot RDS das duas stacks é tirado antes do deploy com migration (protocolo da fila).
