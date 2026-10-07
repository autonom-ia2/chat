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

## Fora (F3b e F4)

Anúncio por dentro (F3b). IA na ação do dia, mensagem sugerida, resumo das 8h e alertas no WhatsApp (F4).

## Validação depois do deploy (só leitura)

```sql
select sum(spend) from crm_meta_ad_insights_daily where account_id = 18 and date >= current_date - 29;
select count(distinct conversation_id) from crm_meta_ad_links where account_id = 18 and touched_at >= current_date - 29;
```

Os dois têm de bater com "Investido" e "Conversas" do painel de 30 dias.
