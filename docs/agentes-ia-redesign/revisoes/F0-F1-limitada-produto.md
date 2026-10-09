# Confirmação limitada R1 — produto/D9

**Data:** 2026-10-07  
**Alvo:** snapshot31 `d974cedd1b5a1df30148ac5712f7ce1ff8d376b366fa23966f27b72a53577e5c`.  
**Escopo:** somente os dois achados do parecer `F0-F1-R1-produto.md`: adaptadores de etapas/locale e integração real do `AgentSwitch`.  
**Método:** leitura dos componentes e dos novos specs. Não executei Vitest, navegador, build, banco ou produção; a suíte e o navegador serão executados pelo coordenador.

## Resultado

**STOP — os dois achados têm prova nova, mas nenhum está fechado nesta confirmação limitada.** Há cobertura `pt_BR` para os adaptadores e um spec unitário real do `AgentSwitch`, porém ainda faltam provas de contrato nos consumidores pedidos pela correção. Não alterei produto nem specs.

## R1-01 — adaptadores de etapas e locale

**Estado: residual de cobertura (média), STOP.**

- `AgentSteps.spec.js:6-32` monta somente `pt_BR`. Confirma as quatro etapas, textos e `aria-label`, mas não exercita o mesmo adaptador com catálogo `en` nem emite `go`.
- `JourneyStepBar.spec.js:6-33` monta somente `pt_BR` e confirma as três etapas, textos e `aria-label`, mas também não verifica `go`.
- `JourneyStepper.spec.js:14-18,42-52` usa `en` e cobre `go` indiretamente pelo wrapper, mas não substitui uma prova explícita dos dois adaptadores em `en` e `pt_BR`; o caminho `AgentSteps` continua sem qualquer caso `en`.
- O spec genérico `StepsBar.spec.js` continua usando rótulos fabricados, portanto não prova as chaves dos catálogos.

A causa é cobertura incompleta da matriz solicitada: foram adicionados casos brasileiros e um caso indireto de Campanhas, mas não a combinação explícita `en`/`pt_BR` + evento `go` para cada adaptador. A correção mínima é acrescentar esses casos aos specs dos próprios adaptadores, mantendo `Pronto` fora da barra e conferindo texto, ARIA e índice emitido.

## R1-02 — `AgentSwitch` real na lista

**Estado: residual de integração (média), STOP.**

- `AgentSwitch.spec.js:17-64` monta o componente real sobre `LabeledSwitch` e confirma E5 (`aria-checked=true`, rótulo e `false`), E6 (`aria-checked=false`, rótulo e `true`) e `disabled`. Essa parte fecha somente o wrapper isolado.
- `AgentRow.spec.js:37-49` ainda substitui `AgentSwitch` por um botão stub. O caso E5 em `:64-73` só verifica que o stub existe; não há caso E6, evento `toggleStatus`, payload de pausa/religação ou switch real bloqueado por `busy`.
- O produto já calcula o rótulo por estado em `AgentRow.vue:45-50` e passa `checked`, `disabled`, `aria-label` e `label` ao componente real em `:231-237`, mas essa integração permanece sem prova.

A causa é a separação entre a prova unitária do wrapper e o consumidor: o novo spec verifica o contrato interno, enquanto o spec do cartão continua ocultando exatamente o wiring que o achado pediu. A correção mínima é montar `AgentRow` com `AgentSwitch` real em E5 e E6, disparar o controle e conferir `toggleStatus` com `{ status: 'paused', enabled: false }` e `{ status: 'active', enabled: true }`, além de provar `busy` no switch.

## Conclusão e limite

A confirmação limitada falhou por dois resíduos concretos de prova. O coordenador deve executar a suíte e o navegador conforme planejado, mas esse resultado estático já impede marcar R1 como aprovada. Conforme o handoff, registrar a causa antes de qualquer correção e parar se a checagem final ainda encontrar erro. Nenhum merge, fila, deploy ou produção foi executado.
