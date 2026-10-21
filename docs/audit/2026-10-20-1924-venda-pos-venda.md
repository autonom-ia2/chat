# #1924: IA de assunto separa venda de pós-venda (registro de decisões e validação)

Data: 20/10/2026. Branch `feat/1924-venda-x-pos-venda`, base `feat/1918-destravar-etapa` (PR #1921).

## Decisões

- **Escopo: todas as contas, sem flag.** A regra do tipo do funil e a janela de 12 mensagens valem para todas as
  contas. Motivo: é correção de causa raiz de um erro de roteamento (cancelamento indo para funil de venda), não
  recurso novo. Em aberto para o Rodrigo: pôr atrás de flag e ligar só no piloto antes.
- **Ordem de decisão única na regra.** (1) dúvida sobre o que o card atual está entregando agora, ou desistência da
  cotação antes de comprar: fica no assunto atual; (2) cancelamento, problema ou mudança de quem já comprou: pedido
  novo, no funil cujo nome, "quando usar" ou tipo cobre; (3) senão, as regras gerais. O nome e o "quando usar" valem
  mais que o tipo (o interruptor "conta como venda" pode estar ligado num funil de atendimento antigo).
- **Sem funil que sirva:** com assunto atual, fica nele; **sem assunto atual, abre no funil mais próximo**, como antes
  do #1924, para a equipe não perder o pedido de vista. O volume de cards criados não muda nesse caso. Em aberto para
  o Rodrigo: preferir "ainda não" (nenhum card) nessa situação.
- **Texto neutro dos funis com card sem nome:** só com `crm_avaliar_toda_mensagem` (que adota o card da chegada no
  funil escolhido). Sem a flag fica o texto de antes, que favorece o funil do card sem nome, para não deixar um card
  vazio para trás.
- **Janela de mensagens:** 12 mensagens dos dois lados; as 5 mais recentes com texto seguem até 5.000 caracteres (como
  a janela de 5 lia); as 7 mais antigas, até 2.000. Pior caso ~39 mil caracteres (antes 25 mil).

## Eval pago (só conversas sintéticas, 8 ramos inventados)

Modelo maior real; Jev simulado com certeza zero (o modelo maior decide sempre).

| Rodada | Casos | Placar | Custo (US$) |
|---|---|---|---|
| antes (main da base), 1ª versão | 12 | fica 1/3, atendimento 4/6, venda 3/3 | 0,0321 + 0,0313 |
| depois, 1ª versão | 12 | 12/12 | 0,0309 + 0,0306 |
| antes, ampliado | 18 | fica 2/4, novo 11/12, volta 1/1, nao_cria 1/1 | 0,0483 |
| depois, ampliado | 18 | 18/18 | 0,0502 |
| depois, revisão 2 (critério endurecido + 3 casos sem card só com funis de venda) | 21 | 21/21 | 0,0636 |

Total gasto: **US$ 0,2870** de um teto de US$ 0,30. Critério da revisão 2: falha, sem cota, sem conteúdo ou dúvida
não contam como acerto; "fica" e "nao_cria" exigem resposta `mesmo_assunto` com estado `kept`.

Tamanho do que vai ao Jev (caracteres do corpo, média nos casos): 2.185 antes, 3.403 depois.

## Limites

- **O caminho em que o Jev responde sozinho, seguro, não foi avaliado.** O Jev real (Typesafe) é outro provedor pago,
  fora do orçamento autorizado nesta Issue. O texto que vai a ele cresceu ~55%; não há medida da taxa de respostas
  seguras antes/depois.
- Um caso por ramo em cada categoria: amostra pequena.

## Validação local

- `rspec spec/services/crm/subjects/ spec/services/autonomia/decisores/`: 171 exemplos, 0 falhas, 2 pendentes (evals
  pagos desligados).
- Specs vizinhos do Estado (decisor_leituras, typesafe_ai/decisor, responder_email_autoria, waha/rich_native): 37
  exemplos, 0 falhas.
- Rubocop nos 9 arquivos Ruby tocados: sem ofensas.
- `pnpm guia:build` e `pnpm guia:check`: mapa em dia.
