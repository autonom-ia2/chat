# #2212 — eval pago do classificador de comentários (27/10/2026)

Teto autorizado pelo Rodrigo em 27/10, repassado pela sessão Meta aprovar: **US$ 5 somando todas as rodadas** do #2212.

## O que foi medido

`Crm::MetaAds::ComentariosIa::Classificador` com o Jev real (`jev-1.13.0`, Typesafe):

- 40 comentários fictícios, em quatro fichas: decoração, academia, loja de roupa e um post sem oferta;
- a maioria em pt-BR, com um em inglês e um em espanhol;
- cada caso tem a lista das respostas aceitas.

Arquivo: `spec/services/crm/meta_ads/comentarios_ia/classificador_eval_spec.rb`. Roda só com `CRM_EVAL_PAGO=1` e
`TYPESAFE_API_KEY`. Nenhum prompt nem dado de cliente foi gravado.

## Rodadas

| Rodada | Acertos | Sem decisão (fica para a pessoa) | Decisão errada | Privado em reclamação | Custo |
|---|---|---|---|---|---|
| r1 | 36/40 | 3 | 1 (crítica à professora → esconder) | 0 | US$ 0,000932 |
| r2 | 36/40 | 4 | **0** | 0 | US$ 0,000961 |

- **Entre a r1 e a r2:** a descrição de "esconder" passou a dizer que crítica, grosseria ou reclamação nunca se escondem. Na r2, a crítica caiu em "sem decisão" (certeza < 0,7) e ficou para a pessoa.
- **Os 4 sem decisão da r2:**
  - "Vocês atendem em Campinas?";
  - a crítica à professora;
  - "Valor?";
  - "Quanto custa?" num post sem oferta.

  Nenhum recebe ação da IA: o comentário segue sem resposta na lista de comentários.

## Custo

- **Por comentário:** cerca de US$ 0,000024, com 570 tokens de entrada em média e saída sem custo no Jev.
- **Gasto total do #2212 até aqui:** US$ 0,0019 de US$ 5.
- **Teto diário proposto:** 200 comentários por conta por dia, o mesmo número da tela aprovada. Dá no máximo ~US$ 0,005 por conta por dia no classificador. O teto existe para limitar o volume de mensagens à Meta, não o custo.
- **Ainda não medido:** a leitura do post, que monta a ficha com um modelo generativo. Ela entra no PR seguinte e terá o seu próprio eval dentro do mesmo teto.
