# F1 — causa raiz do vazamento entre exemplos da página

Data: 2026-10-07  
Escopo: `AgentsListPage.spec.js`; correção de isolamento do harness antes da execução focada.

## Evidência observada

O baseline29 carregou 199 assertions e terminou com exit 1 por uma única `UnhandledRejection`. O erro
apareceu no terceiro exemplo, com `No useMapGetter export` vindo de `TeleportWithDirection`. A sequência
confirmou que o primeiro wrapper da página (lista) e o segundo wrapper (vazio) continuavam montados quando
o exemplo de releitura desatualizada começava.

## Causa raiz

Os exemplos chamavam `mount` sem registrar desmontagem. O segundo exemplo deixava a árvore vazia viva; quando
o estado compartilhado voltava a conter um agente no terceiro exemplo, a árvore anterior reagia às mesmas refs
e montava componentes reais sem os stubs daquele exemplo. O erro de `useMapGetter` era consequência do leak de
componentes/Teleport, não uma falha do contrato da lista nem um mock ausente que devesse esconder o problema.

## Correção limitada

`AgentsListPage.spec.js` agora importa `enableAutoUnmount` do Vue Test Utils e o registra com `afterEach`.
Nenhuma assertion, payload, stub de componente ou contrato de produto foi alterado. A limpeza acontece ao fim
de cada exemplo, antes de o próximo exemplo reutilizar `listState`.

Validação estática: `node --check` da spec e `git diff --check` passaram. A execução focada final permanece
pendente para a sessão principal; não foram executados banco, seed, serviço ou suíte pesada neste bloco.
