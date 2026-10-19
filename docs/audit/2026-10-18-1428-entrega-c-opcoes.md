# #1428 entrega C — opções clicáveis na pergunta do "Mudar conversando" (18/10/2026)

Registro de decisão, eval pago e riscos conhecidos. Sem prompt, sem chave e sem dado de cliente.

## Decisões (Rodrigo, 18/10)

- A pergunta de conflito, que é do código, leva dois botões fixos: "Manter assim" e "Quero mudar" (i18n en/pt_BR).
  O código sabe que é o conflito pelo caminho que gerou a pergunta, nunca lendo o texto.
- Tocar numa opção manda na hora, como escrever e mandar.
- A frase repetida entre o cartão ⚠ e a pergunta fica fora desta entrega (Issue #1850).

## Eval pago (tema 6, Builder ajuste por lista)

- Spec: `spec/services/autonomia/agents/builder_ajuste_por_lista_eval_spec.rb`, com 3 cenas novas da entrega C
  (`c_opcoes_passagem_vaga`, `c_opcoes_parcial_tamanho`, `c_opcoes_sem_inventar_horario`). Também ganharam
  expectativa de opções as cenas `t6a_duas_frases_e_preco`, `explica_o_que_faz`, `t6b_contraditorio` e
  `pedido_e_pergunta`. O juiz ganhou o campo `opcoes_coerentes`.
- Comando: no snapshot do M2, com banco de teste próprio (`chatwoot_test_1428c`) e a chave pela entrada padrão:
  `AUTONOMIA_EVAL_PAGO=1 AJUSTE_POR_LISTA_EVAL=1 AJUSTE_POR_LISTA_EVAL_TETO_USD=<teto> AJUSTE_POR_LISTA_EVAL_CENA=<cenas>
  bundle exec rspec spec/services/autonomia/agents/builder_ajuste_por_lista_eval_spec.rb`.

| Rodada | Cenas | Placar | Custo (US$) |
|---|---|---|---|
| Cenas de opções | 4 | 4/4 | 0,079 |
| Todas | 19 | 17/19 | 0,317 |
| Repetição das 2 que falharam (`explica_o_que_faz`, `t6c_so_o_tom`; nenhuma tinha opção) | 2 | 2/2 | 0,058 |
| Depois de mudar a descrição do campo | 7 | 7/7 | 0,126 |

- Eval: US$ 0,58. Testes da demo no M2 com o Construtor real: US$ 0,06 na primeira rodada (total então US$ 0,64) e
  US$ 0,06 depois das revisões. Total da entrega: **US$ 0,70** (teto US$ 1).
- As 2 falhas da rodada cheia foram variação do juiz: em `t6c_so_o_tom` ele contradisse o próprio critério da cena.
  As duas passaram na repetição.
- O que as cenas de opções mostraram: o pedido vago e o tamanho de resposta vieram com 2–3 opções coerentes. O horário
  veio sem nenhuma opção, sem inventar valor. Onde não havia pergunta, não veio opção.
- Sem eval novo na rodada das revisões: o prompt e o schema do modelo não mudaram.

## Risco conhecido, sem código (revisão adversarial, item 5, INFO)

Uma aba velha, aberta antes de alguém voltar o agente por Versões em outra aba, continua mostrando as opções da
pergunta até reler a conversa. O servidor já as tirou do state, e tocar numa delas só manda uma fala do dono, que o
Construtor lê como qualquer outra. Não há escrita indevida. Fica registrado, sem correção.
