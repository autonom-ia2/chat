# 2026-09-10 · Entrega 4 · A mensagem de encerramento parcial nunca rodou

Plano do Agente de Cotação (épico #291). Branch `fix/entrega-4-encerramento-parcial`.

## Causa raiz

O contrato de `Native::Base` mistura dois níveis: textos que o `AsyncRunJob` publica pela CLASSE
(`accepted_message`, `waiting_message`, `failure_message`, `partial_message`) e trabalho que o
`Bound`/job chamam na INSTÂNCIA (`precheck`, `closing_deliveries`). A cotação definia
`partial_message` como método de instância — a frase de seguros nunca saía; o cliente lia o texto
genérico do `Base` ("algumas consultas não responderam"). E `precheck`/`closing_deliveries` tinham
default em `class << self`, nível que nenhum chamador alcança.

## Decisões

- `partial_message` da cotação vai para `Declaracao` (classe), como os outros três textos.
- `precheck` e `closing_deliveries` do `Base` passam ao nível de instância (o que é chamado).
- Guarda `base_contrato_de_nivel_spec`: varre `Registry.all` e reprova texto de classe redefinido na
  instância, e trabalho de instância definido na classe — é o termo 4 ("o mesmo defeito procurado
  nos outros textos") virando teste, para o próximo ramo não repetir.
- Exemplo pelo caminho real (`async_run_job_encerramento_parcial_spec`): cotação de verdade,
  submetida, com preço entregue, prazo vencido → o job publica a frase de SEGURADORAS.

## Validação

- Suíte ampla (tools, specialists, answerer, jobs/tools, models/agents): 350 exemplos, 0 falhas.
- Mutação: voltar `partial_message` para a instância reprova o exemplo do job E a guarda.
- Termo 1 (conversa real com parte das seguradoras sem responder): só em produção, após deploy,
  numa cotação real em que o prazo estoure — depende de autorização de cotação.

## Revisões

Codex e adversarial: APROVADO COM RESSALVAS, todas aplicadas: guarda estendida ao contrato inteiro
(16 métodos); conector `mock` fixado no exemplo; datas corrigidas (a frase nasceu em 08/09,
`c7ae6997e1`, não 04/09); o exemplo afirma o comparativo e a frase, nesta ordem.

## Fora de escopo, registrado

- `ReapStaleRunsJob` fecha em silêncio uma execução abandonada que já tinha entregue preço (nem
  comparativo nem fecho) — vizinho do termo 4, forma diferente. Issue própria.
- `tool_name` no contrato da nativa não tem chamador: código morto em quatro lugares.
