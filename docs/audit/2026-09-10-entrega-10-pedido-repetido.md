# 2026-09-10 · Entrega 10 · "E aí, saiu?" não pode abrir cotação nova

Plano do Agente de Cotação (épico #291), 4ª da ordem. Issue #371. Branch
`feat/entrega-10-pedido-repetido`. Adapter: autonom-ia2/autonomia-adapters#49 (PR #50).

## O problema

Enquanto a cotação corre, o cliente pergunta se já saiu; o modelo chama a ferramenta de novo com os
mesmos dados; `ToolRun.open!` supersedia a execução viva e abria OUTRA cotação no portal do
corretor. O teto bruto de oito por hora saiu em 10/09 (volume é receita), e nada mais separava a
pergunta inocente da linha duplicada.

## Decisões

- **Nenhuma linha classifica intenção** (termo 5; Rodrigo, 10/09: "não quero regex... a IA precisa
  dar conta"). O código não lê a frase do cliente: compara a IDENTIDADE do pedido — digest da
  entrada como o ADAPTER a entende — com a da última execução. "E aí?" e "quero mudar a franquia"
  chegam iguais ao código (como argumentos da ferramenta); só os dados decidem.
- **A entrada normalizada é do adapter** (termo 3). `quote/validate` (gratuito, sem rede) passa a
  devolver `entrada`: transformações e padrões declarados no schema aplicados ao que veio, chaves
  em ordem — e NADA além do que o `start` faz (Codex, rodada 1 do adapter: `null`/`''` são valores;
  texto e lista ficam como vieram; chave herdada é dado). O erro caro é o falso negativo (dois
  pedidos diferentes com o mesmo digest); o falso positivo só reabre a duplicata que já existia.
  Os padrões continuam morando no adapter (termo 1 da entrega 2).
- `InsuranceQuote#pedido` = `Insurance::Pedido.digest(produto, validacao['entrada'])`, 32 hex,
  sem dado pessoal; a conferência é memoizada por instância (`validacao`), e `Bound` a instancia
  UMA vez para `precheck` e `pedido`. nil quando a conferência cai ou o adapter ainda não devolve
  `entrada`: nil NUNCA barra (o conferente não é portão).
- `ToolRun.open!(pedido:)` grava o digest como marca do handle (`autonomia_pedido`, em `MARCAS`:
  a ferramenta não a vê). Sem migration.
- **O que ainda conta como pedido feito** (`ToolRun.pedido_repetido`): a última execução da
  ferramenta na conversa se estiver `running`, ou encerrada (`done`/`failed`) COM entrega há menos
  de `PEDIDO_VALE_POR = 24h`. Não contam: supersedida, descartada, bloqueada, `pending` órfã, ou
  falhada sem entrega — repetir depois delas é tentar de novo, não duplicar. A janela é decisão
  registrada (o plano fala em "última execução" sem prazo; sem prazo, dados idênticos ficariam
  barrados para sempre na conversa).
- **Quando barra** (termo 6): o modelo recebe TEXTO (`Tools::PedidoRepetido`, forma da
  `Conferencia`) com o estado da consulta — "já está em andamento (começou há N minutos)" ou "já
  foi concluída há N, com N mensagens entregues" — e a instrução de responder sobre o andamento
  com as próprias palavras; dado diferente abre consulta nova. Registrado como recusa
  `pedido_repetido` (entrega 6), `onde=aceite`, com gatilho em `recusa_registro_spec`.
- O mock do conector devolve `entrada` com a mesma regra do adapter (padrão de escolha só para o
  que não veio; chaves em ordem), senão a prova do "e aí?" se aprovaria contra um adapter que não
  existe.

## Ordem de deploy

Adapter primeiro (Lambda manual), consumidor depois. Se o consumidor subir antes, `entrada` vem
ausente → `pedido` nil → nada é barrado (o comportamento de hoje). Rollback do adapter:
`gh workflow run deploy-lambda.yml --ref 5ce943b -f confirm=deploy`.

## Validação (chat2you, antes do Codex)

- Arquivos tocados (9 specs): 160 exemplos, 0 falhas, 0 erros de carga. Suíte ampla (`agents`,
  `jobs/agents`, `models/agents`, `insurance`): 708 exemplos, 0 falhas. Rubocop: 0 ofensas.
- Mutações (7, restauração em memória com `assert`; cada uma reprova o exemplo que a nomeia):
  comparação removida; compara o cru (`params`) e não a entrada normalizada; falha sem entrega conta
  como pedido; sem janela; a marca do pedido chega à ferramenta; `open!` não guarda a identidade;
  recusa da repetição não registra.
- Termos: 1 (não abre), 2 (dado diferente abre, inclusive o número do endereço), 3 (entrada
  normalizada: o padrão escrito por extenso é o mesmo pedido — bike), 4 (mutação), 5 (nenhum
  classificador — regra de desenho, sem regex, verificada em revisão), 6 (o modelo recebe o estado da
  consulta; sem `{"error"`), 7 (bike e auto). Adapter: autonom-ia2/autonomia-adapters#50 — 8
  mutações, cobertura 100%, Codex em revisão.
- Não feito: conversa real com a Lia perguntando "e aí?" no meio de uma cotação (custa uma rodada;
  fora do horário comercial, com autorização).
