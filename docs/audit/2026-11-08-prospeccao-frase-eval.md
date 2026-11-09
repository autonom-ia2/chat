# Eval do pedido em uma frase da Prospecção (#2696, F4) — 08/11/2026

## Resultado: 23 de 23, custo real US$ 0,003

Duas rodadas em 08/11/2026, com a chave OpenAI de desenvolvimento do cofre local do Rodrigo (a chave não foi impressa
nem gravada). O teto aprovado foi de US$ 2,00.

| Rodada | Acertos | Custo real | Tokens (entrada / saída) | Maior saída |
|---|---|---|---|---|
| 1 (instrução original) | 22 / 23 | US$ 0,003051 | 17.115 / 2.678 | não medido |
| 2 (depois da revisão r1) | 23 / 23 | US$ 0,002967 | 18.311 / 2.271 | 137 tokens |

- Erro da rodada 1: em "dentistas perto de mim", a IA pôs "perto de mim" em "Onde?". A instrução passou a dizer que um
  lugar que depende de onde a pessoa está deixa "Onde?" vazio e pede o bairro ou a cidade. Não foi usada nenhuma lista
  de palavras. Na rodada 2, o caso exige esse pedido.
- A maior saída (137 tokens) fica bem abaixo do teto `MAX_OUTPUT_TOKENS = 600` do interpreter.
- Total gasto nas duas rodadas: cerca de US$ 0,006.

## Risco residual

- "Perto de mim" (e qualquer lugar que depende de onde a pessoa está) não tem teste determinístico. Quem decide é o
  modelo, pela instrução; os specs dublam a IA e não cobrem isso. A única prova é o eval pago, que passou na rodada 2.
- Regra: todo PR que mexer em `INSTRUCTIONS` do `Autonomia::Prospecting::SearchInterpreter` roda o eval no mesmo PR e
  registra o resultado aqui. O comentário em cima de `INSTRUCTIONS` diz isso.

## O que está pronto

- Spec: `spec/services/autonomia/prospecting/search_interpreter_eval_spec.rb`, desligado por padrão (fica `pending`).
- Liga com `AUTONOMIA_EVAL_PAGO=1`, `PROSPECCAO_FRASE_EVAL=1` e `OPENAI_API_KEY` (chave de desenvolvimento).
- `PROSPECCAO_FRASE_EVAL_SAIDA=<arquivo>` grava o relatório em JSON (acertos, erros por caso, tokens, custo).
- Chama o `Autonomia::Prospecting::SearchInterpreter` de verdade: mesmo modelo, mesmas instruções e mesmo schema de
  produção. A chave vai ao hook `crm_kanban_ai` de uma conta do banco de teste (a transação desfaz) e não é impressa.

## Casos (23)

- 15 pedidos claros: tipo de empresa + lugar + cada ajuste da tela (nota mínima 3/4/4,5, nota baixa, avaliações
  10/20/50, com/sem site, sem fotos, aberta agora, mostra horário, presença fraca), sem lugar, e "abre cedo" / "abre
  aos sábados" (que a tela não cobre e devem cair em "ficou de fora").
- 3 ambíguos, com mais de uma resposta aceita ("cafeterias boas", "os mais conhecidos", "perto de mim").
- 5 de "não entendi": saudação, pergunta de preço, texto sem sentido, só o lugar sem o que procurar, e uma tentativa
  de injeção de instrução.

A régua compara com uma lista de respostas aceitas por caso (minúsculas e espaços normalizados) e com igualdade nos ajustes e no modo. Ela não interpreta a frase.

## Estimativa de custo (feita antes, como exigido)

- Modelo: `gpt-6-luna` (`Crm::Ai::Config::MODEL_SUMMARY`), esforço `low`.
- Tarifa (`Crm::Ai::Pricing`): US$ 0,10 por 1M de entrada, US$ 0,50 por 1M de saída.
- Instruções + schema: ~3.000 caracteres (~900 tokens). Estimativa generosa por pedido: 3.000 tokens de entrada e
  2.000 de saída (inclui raciocínio).
- 23 pedidos × US$ 0,0013 = **US$ 0,03**, bem abaixo do teto de US$ 2,00.
- O spec recusa rodar se a estimativa passar do teto, e para no meio se o custo real (pelo `usage` da API) chegar a ele.

## Para rodar

```sh
AUTONOMIA_EVAL_PAGO=1 PROSPECCAO_FRASE_EVAL=1 OPENAI_API_KEY=<chave de desenvolvimento> \
  PROSPECCAO_FRASE_EVAL_SAIDA=tmp/prospeccao-frase-eval.json \
  bundle exec rspec spec/services/autonomia/prospecting/search_interpreter_eval_spec.rb
```

