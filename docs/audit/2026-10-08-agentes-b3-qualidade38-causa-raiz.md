# B3 — causa raiz e correção do bloqueio de qualidade 38

## Escopo

O bloqueio 38 encontrou 39 ocorrências de RuboCop em 17 arquivos. Esta correção cobre somente os
arquivos B3 sob a responsabilidade desta fatia: `AgentsController`, `BuildThreadsController`,
`Agent`, `Builder` e `Publisher`. Os arquivos de B4b e os arquivos atribuídos ao root permanecem
intocados.

## Causa raiz

As entregas de criação, edição e publicação concentraram contratos novos nos controllers e no
modelo, elevando métricas de tamanho/complexidade. Alguns ajustes menores de estilo também ficaram
no caminho principal: exceções com nome longo, cadeia de limpeza do enqueue dentro do método público,
coerções redundantes no contexto `knows`, conversão manual para hash e uma negação de `include?`.

## Correção aplicada

- extraí os contratos de ativação e publicação dos controllers para concerns pequenos, preservando os
  mesmos parâmetros, respostas e guards;
- extraí o histórico de versões de instrução do `Agent` para seu concern de responsabilidade própria;
- reduzi a complexidade de `apply_builder_config!` e isolei a limpeza de falha de enqueue;
- dividi a validação de publicação em pré-condições de teste, Copilot e canal;
- corrigi as ocorrências de estilo do `Builder` (`index_with`, argumentos não usados e coerções em
  interpolação) e do `Publisher` (`exclude?`).

## Verificação local

`ruby -c` passou nos oito arquivos Ruby alterados nesta fatia e `git diff --check` passou. Não foram
executados testes, serviços, provedores, banco ou revisão ampla neste bloco.
