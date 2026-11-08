# Eval do pedido em uma frase da Prospecção (#2696, F4) — 08/11/2026

## Resultado: NÃO RODOU (bloqueio)

O eval está pronto, mas não foi executado. Não há chave de provedor de IA disponível de forma legítima no ambiente
local de desenvolvimento:

- a worktree e o checkout principal não têm `.env` (só `.env.example`);
- nenhuma variável `OPENAI_API_KEY` (ou parecida) no ambiente da sessão.

Pelas regras da tarefa, não se usa chave de produção nem `.secrets` de outros projetos. Sem chave, sem rodada.
Custo gasto: US$ 0,00.

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

A régua compara com string (`include?` no quê e no onde, igualdade nos ajustes e no modo). Não interpreta a frase.

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

Depois de rodar, registrar aqui: acertos de 23, os erros por caso e o custo real.
