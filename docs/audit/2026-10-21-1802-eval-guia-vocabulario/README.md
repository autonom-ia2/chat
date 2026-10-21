# #1802, 6.B: vocabulário do Guia por pacote (21/10/2026)

**Base avaliada:** branch `feat/segmentos-f2-guia-vocabulario`, sobre `origin/main` 1dc4275bcf, com as três
camadas de `lib/operator_guide/pacotes/**/guia-instrucao.md` deste PR.

**Orçamento:** aprovado pelo Rodrigo, teto de US$ 2,00 no total.

**Como rodou:** `spec/services/autonomia/guide/vocabulario_eval_spec.rb`. Rodada 1 abaixo; rodada 2 mais adiante.
- Passa pelo Guia de verdade (`Autonomia::Guide::Chat`), com `AUTONOMIA_PACOTES_ENABLED` ligado. A base de telas já
  é a do pacote da conta nas duas variantes; o que muda é só a instrução.
- Variantes intercaladas: `sem_camada` (a instrução geral, como hoje) e `com_camada` (a geral + a camada do tipo).
- Três contas de teste com nome neutro ("Grupo Vale") e os mesmos dados (funil Comercial, três cards fictícios):
  corretora, saúde e benefícios, e seguradora (para provar que a camada `seguros` não fala de corretora nem cotação).
- Quatro perguntas por tipo, iguais nos três, com as palavras que o operador usa ("vendas", "cliente"). Uma repetição.
- O juiz é o gpt-5.4, não sabe a variante e responde um booleano por critério. Nenhuma conferência por lista de
  palavras.
- Banco de teste próprio (`chatwoot_test_1802guia`). Nada em produção. Sem dado de cliente.

## Resultado da rodada 1

| Tipo | Sem camada | Com camada |
|---|---|---|
| Corretora | 0/4 | 3/4 |
| Saúde e benefícios | 1/4 | 3/4 |
| Seguradora | 1/4 | 2/4 |
| **Total** | **2/12** | **8/12** |

Por critério (12 respostas em cada variante):

| Critério | Sem camada | Com camada |
|---|---|---|
| Usa o vocabulário do tipo | 6/12 | 11/12 |
| Correta e útil | 6/12 | 8/12 |
| Chama de segurado sem apólice | 0/12 | 0/12 |
| Diz vendedor ou ganho | 0/12 | 0/12 |
| Seguradora diz corretora ou cotação | 0/4 | 0/4 |

**Onde a camada fez diferença:**
- **"Quantas vendas eu fechei esse mês?"**: sem a camada, os três tipos respondem "1 venda". Com ela: "1 seguro
  fechado" (corretora e seguradora) e "1 plano fechado" (saúde).
- **"Como cadastro um cliente novo?" (corretora)**: com a camada, o Guia cadastra como contato e explica que
  vira cliente quando a pessoa compra.
- **"Como marco que o cliente fechou?" (corretora)**: com a camada, "abra o card da cotação".

Nenhuma resposta, com ou sem a camada, chamou alguém de segurado sem apólice, falou em vendedor ou ganho, ou pôs a
seguradora como corretora.

## O que reprovou com a camada, e por quê

- **"Onde vejo as propostas paradas?" reprovou nas 6 respostas, com e sem a camada.** O Guia manda para
  Campanhas > Anúncios > Resultado ("O que fazer hoje"), em vez do funil. O problema está no fluxo que a busca
  traz para essa pergunta, não no vocabulário. Fica como achado para a base do Guia, fora deste PR.
- **"Como marco que o cliente fechou?" na seguradora:** o juiz reprovou o "funil de Vender". Mas "Vender" é o tipo do
  funil (Editar funil > Para que serve), e a resposta está certa. Os dados que o juiz recebeu não diziam que o funil
  Comercial é do tipo Vender. É um falso negativo do juiz. A mesma frase passou na corretora.

Nenhum dos dois casos pede mudança no texto das camadas. A rodada 2, depois da revisão, mediu só os casos que mudaram.

## Gasto da rodada 1

US$ 1,1117 de US$ 2,00, com o juiz incluído. Foram 24 respostas e 24 julgamentos em 9 minutos, sem execução pulada.
O gasto é a soma do consumo gravado (`Crm::AiUsageEvent`). Os embeddings da base não têm tarifa na tabela e
saem como zero.

## Rodada 2: seguradora e insurtech (depois da revisão)

**Base:** 3e33c2897f (o commit do PR com a origin/main mesclada) e os ajustes da revisão:
- A camada `seguros` ganhou texto positivo: quem atende e vende é a **equipe**, o pedido do cliente é a **proposta**
  e, depois de emitida, a **apólice**. Se uma tela ou um menu se chama "Cotação", o nome da tela vai como está.
- O juiz agora sabe que o funil Comercial é do tipo Vender, que o menu Cotação existe e que o nome dele, citado como
  aparece, não conta contra o vocabulário.
- Duas perguntas só para seguradora e insurtech, que já vêm com a palavra do outro tipo: p5 "Como crio uma cotação
  nova?" e p6 "Como faço uma proposta para um cliente?". Também rodou de novo a p4 "Como marco que o cliente fechou?".
- Filtros: `GUIA_VOCABULARIO_EVAL_TIPOS=seguradora,insurtech`, `GUIA_VOCABULARIO_EVAL_PERGUNTAS=p5,p6,p4` e
  `GUIA_VOCABULARIO_EVAL_TETO_USD=0.85`, o que sobrava dos US$ 2,00.

| Tipo | Sem camada | Com camada |
|---|---|---|
| Seguradora | 1/3 | 1/3 |
| Insurtech | 1/3 | 2/3 |

| Critério (6 respostas por variante) | Sem camada | Com camada |
|---|---|---|
| Diz corretora ou cotação como palavra dela | **4/6** | **0/6** |
| Usa o vocabulário do tipo | 2/6 | 6/6 |
| Correta e útil | 2/6 | 3/6 |
| Segurado sem apólice / vendedor ou ganho | 0/6 | 0/6 |

**O que a rodada mostra:**
- **O critério que importa ficou limpo com a camada.** Sem ela, nas p5 e p6, o Guia fala de "cotação nova",
  "agente de cotação" e "proposta a partir de uma cotação". Com ela, fala de "nova proposta", "proposta de seguro" e
  "card no funil" (0 de 6).
- **A p4 deixou de reprovar** nos dois tipos e nas duas variantes (4/4). O falso negativo da rodada 1 era o juiz.
- **A p5 reprova na utilidade com e sem a camada.** "Cotação nova" leva o Guia ao fluxo do agente de cotação no
  WhatsApp (comparativo em PDF), que é da corretora. O problema está na base que a busca traz para essa pergunta, não
  no vocabulário. É o mesmo tipo de achado da p3 da rodada 1, fora deste PR.
- **A p6 responde com uma pergunta** ("proposta de seguro ao contato ou card no funil?"). O juiz aceitou uma vez
  (insurtech, com camada) e reprovou as outras por não dar o caminho.

**Gasto da rodada 2:** US$ 0,5132 de US$ 0,85, com o juiz incluído. Foram 12 respostas e 12 julgamentos, sem
execução pulada.

## Gasto acumulado

US$ 1,1117 (rodada 1) + US$ 0,5132 (rodada 2) = **US$ 1,6249 de US$ 2,00**.

## Arquivos

- `sem-x-com-camada.json`: rodada 1. Placar, custo e cada execução (resposta, veredito e justificativa do juiz).
- `rodada-2-seguradora-insurtech.json`: rodada 2, no mesmo formato.
- Nenhum dos dois tem prompt, chave ou dado de cliente.
