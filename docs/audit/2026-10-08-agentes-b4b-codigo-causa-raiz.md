# RCA B4b — falhas do check38 e lint da fatia

**Data:** 2026-10-08
**Escopo:** B4b (BE-12, BE-29 e BE-30)
**Estado:** correção local aplicada; GREEN ainda não foi executado.

## Causas confirmadas

1. `b4b_playground_contract_spec.rb` atribuía a sanitização ao `Playground`. O contrato real é que
   o `Playground` encaminha o histórico bruto ao `Agents::Copilot`, que o sanitiza na fronteira de
   `test_mode` antes do `Answerer`. O teste foi ajustado para provar essa fronteira sem mudar o
   comportamento de segurança.
2. `ai_request_results_spec.rb` tratava `test` e `suggest` como se compartilhassem o mesmo executor.
   `test` usa `Playground` e preserva o histórico do Testar; `suggest` usa `Agents::Copilot` e
   entrega o histórico marcado como dado não confiável. A expectativa agora diferencia os dois
   caminhos e continua proibindo a exposição da instrução.
3. O lint do check38 encontrou pequenas violações introduzidas na implementação B4b: modificador
   multilinear e `present?` negado no `Playground`; método `generate` no limite, navegação segura
   redundante no `Answerer`; cadeia de relação multilinear no `PromptBuilder`; sete parâmetros no
   `Copilot`; e classe aninhada/complexidade excessiva no sanitizador compartilhado. Foram corrigidos
   com fluxo explícito, extração do executor de resposta, consultas intermediárias, opções de
   palavra-chave e funções de normalização, preservando os contratos.

## Evidência e limite

O check38 registrou `658 examples, 2 failures` em
`/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd/.codex/preview/check38/ruby38.log`; as
duas falhas são as descritas acima. O lint registrou 39 ocorrências em 17 arquivos; esta fatia
corrigiu somente os arquivos B4b sob sua ownership (`playground.rb`, `answerer.rb`, `prompt_builder.rb`,
`copilot.rb` e `conversation_context.rb`).

Validação local desta correção: `ruby -c` nos cinco serviços e nas duas specs, todos `Syntax OK`, e
`git diff --check` sem erro. Nenhuma suíte, serviço, provider, banco, job, navegador ou produção foi
executado nesta correção. O resultado não declara GREEN nem autoriza merge, fila, deploy ou produção.
