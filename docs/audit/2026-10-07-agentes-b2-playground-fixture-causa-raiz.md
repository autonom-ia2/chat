# B2 — causa raiz da fixture stale no Playground

**Data:** 2026-10-07  
**Escopo:** somente `spec/requests/api/v1/accounts/autonomia/agents/playground_spec.rb`  
**Resultado de referência:** Ruby23, 222 exemplos, 2 falhas, 0 pendentes e 0 externos; job `m2-4f6cc8a7d985410aa45fab47bf5744a9`; JSON `/tmp/chat2you-agentes-b2-b3-check23.json`; SHA informado `1bfcafb8c825fa882c2a59da7fb9fddb95337470a63b7449c4971fe4c476923e`.

## Causa antes da correção

O caminho real `DeferInteractiveAi#prepare_agent_test!` gera `inputs['session_id']`
com `SecureRandom.uuid` e passa esse valor para `AgentStateStore.start_pending!`.
O spec, porém, fazia `AgentStateStore.read` devolver sempre
`session_id: 'server-session-1'`. Essa identidade não era a do pedido Redis criado
pelo POST.

Na leitura do polling, `TestResultRecorder.public_payload` compara a sessão do
pedido com a sessão lida do estado. A divergência é corretamente classificada como
`stale`, com `valid: false`. Portanto, a expectativa de uma resposta concluída podia
falhar por uma fixture stale, e o caso de viewer podia passar `valid: false` pela
razão errada, sem provar a regra de que `autonomia_view` conclui a resposta mas nunca
produz um teste válido.

## Correção mínima autorizada

Capturar no stub de `start_pending!` o `session_id` que o request realmente recebeu e
usar essa captura no stub de `read`, inclusive no cenário de viewer. O caso de viewer
deve exigir `status: completed` e `valid: false`; assim, um retorno `stale` não
satisfaz a expectativa. Nenhum guard, serviço, controller ou contrato de produção
entra nesta correção.

Este registro foi escrito antes da alteração da fixture. Não houve execução local de
RSpec, build, banco, serviço ou produção nesta etapa.

