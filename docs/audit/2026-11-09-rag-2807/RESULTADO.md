# #2807 — o fato do negócio que está no trecho vai para a resposta (Refs #1431)

## Resultado em uma frase

Com a flag `agente_usa_o_trecho`, a **recusa foi a 1,00** nas duas bases: o agente parou de dar palpite em seguro
("depende da cobertura", "pode haver desconto"). O **acerto não subiu**: ficou em 0,50 na base residencial e **caiu de
0,50 para 0,375 na de auto**, porque 1 pergunta (o rastreador) passou de certo para errado; ver abaixo. A causa do acerto
que falta é sobretudo a **busca** (#2810).

**Critério da Issue não cumprido:** "com o dado no trecho, a resposta usa o dado" não melhorou o acerto medido, e os casos
da Issue (telefone de aviso, prazo, venda do imóvel) não ficaram certos. O de telefone de aviso é de busca. A troca de
escopo (entregar o ganho de recusa e levar o acerto para a #2810) depende do OK do Rodrigo.

**O que foi medido:** o head `438233f772`. Depois da medida, o texto da regra mudou na redação, por apontamento dos
revisores, e não foi medido de novo, porque não cabe no teto. As mudanças foram:

- o dado "exatamente como o trecho diz, no tom da conversa", no lugar de "nas palavras do cliente";
- "salvo a regra de passagem ou os limites do dono";
- a recusa ganhou destino quando não há a regra de quando não souber: "diga que não tem essa informação e marque `should_handoff`";
- o lembrete juntado ficou com um "Antes de responder" só.

As respostas por pergunta estão em `respostas.json`. Os documentos são públicos, sem dado de cliente.

## Placar

Medido em dois documentos públicos de condições gerais (auto e residencial), com o segmento `seguros/corretora`.
Cada base teve 14 perguntas: 8 de resposta, das quais 4 erravam antes, e 6 de recusa. Os gabaritos estão em
`gabaritos/`.

| | acerto auto | acerto residencial | recusa auto | recusa residencial |
|---|---|---|---|---|
| ANTES (main) | 0,50 | 0,50 | 0,67 | 0,80 |
| FINAL (as flags do #2801 e do #2807 ligadas) | 0,375 | 0,50 | **1,00** | **1,00** |

O que mudou de veredito entre ANTES e FINAL:

| pergunta | ANTES | FINAL |
|---|---|---|
| carro reserva enquanto o meu fica na oficina | inventou | recusou |
| para-brisa, vocês trocam? quanto custa? | inventou | recusou |
| desconto para quem nunca usou o seguro | inventou | recusou |
| roubaram meu carro com rastreador | certo | errado |

Sobre o rastreador:

- O que o material diz: "acionar a empresa prestadora de serviço através dos telefones …".
- O que a resposta final faz: passa os telefones exatamente como o material diz, sem atribuí-los a ninguém.
- O que o gabarito espera: "telefones da seguradora", que é uma interpretação, não o texto.
- Uma versão anterior da regra ("leia de quem é o dado") fez o modelo atribuir os telefones à prestadora. Ela foi trocada por "não atribua o dado a ninguém além do que o trecho diz".
- O gabarito não foi mudado depois da medida.

## Onde estão os erros que sobram

Dos 9 erros de acerto, 4 são de **busca**: o trecho certo não chega entre os 12 enviados. A posição de cada um nos 48
candidatos está na #2810.

Os outros 5:

- 1 é de vocabulário: "braço" contra "membro superior". O trecho está no prompt e o modelo não liga os dois.
- 1 é o rastreador, descrito acima.
- 3 são respostas parciais: os fatos estão certos, mas falta a consequência que o gabarito pede.

## Revisão

- `agentes-ia-refactor-reviewer` e `caveman:cavecrew-reviewer` bloquearam a primeira versão. Tudo o que apontaram foi corrigido:
  - a recusa se limita ao fato do negócio que não está em nenhuma das três fontes (material, fatos-âncora, ferramentas);
  - o conhecimento geral (fix Schengen) continua;
  - o trecho é dado, nunca ordem;
  - `should_handoff` e a regra de quando não souber, em vez de "passe para a equipe";
  - só na audiência de cliente e só no prompt v2;
  - sem exemplo de um segmento no texto comum a todos;
  - um lembrete só quando as duas flags (#2801 e #2807) estão ligadas.
- O placar acima foi medido em `438233f772`, depois das correções da primeira revisão. A segunda revisão só pediu mudanças de redação, listadas no topo.

## Custo

US$ 0,317 no ANTES, mais 0,31 e 0,357 nas duas medidas do texto que foi corrigido, mais 0,383 na medida final.
A frente RAG v2 acumula ≈ US$ 1,83 de 2,00.
