# Checagem limitada B3/BE-05 — integração do PanelTune

**Alvo:** snapshot25 `/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`  
**SHA:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`  
**Escopo:** somente a correção do P1 no `PanelTune`: retomada, histórico, flag, manual, erros, envio sem thread e `ChoiceSelect`.  
**Tipo:** primeira checagem limitada da correção, somente leitura.

## Resultado

**PASS limitado — o P1 da integração do PanelTune está fechado neste escopo.**

O resultado JS25 informado pelo coordenador é GREEN: 43 casos, incluindo os 9 casos do PanelTune, com SHA `0fb7f86e8e5e0520d6f7fae49b259fa2aa5274ff0d5e03245ee438ac68d3ed85`. Os 14 casos Ruby do reader/writer BE-05 também permanecem GREEN segundo o mesmo registro. Não executei esses testes.

Esta checagem não é revisão final do B3 e não aprova F0/F1. O F0 continua uma dependência futura explicitamente fora deste resultado.

## Conferência

### Retomada e histórico

Em `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue:215-245`, o painel verifica o modo manual, respeita a flag `currentAccount.autonomia_agents_redesign === true`, aguarda `autonomiaBuildThreads/resume({ agentId })` e só abre o diálogo depois do sucesso. O fluxo novo não faz `RESET` no componente nem abre uma conversa vazia antes da hidratação. O `BuilderChat` recebe `builderMessages` do store e, portanto, mostra a thread real retornada pelo resume.

O primeiro envio, em `:258-288`, exige `threadId` no fluxo novo antes de qualquer upload. Com o id presente, despacha somente `autonomiaBuildThreads/send`; não há fallback para `start`. A prova correspondente está em `PanelTune.f0-compat.spec.js:151-195`.

### Thread ausente, manual e erros

Quando a retomada não deixa id, `:261-267` mostra erro e retorna antes de upload, `start` ou `send`. O modo manual é recusado na fronteira `:221-225`, sem `resume`, reset, abertura ou escrita. A spec cobre ambos os casos em `:226-266`.

Falhas 401, 404 e 422 do resume caem no tratamento `:240-243`: o diálogo não abre e o agente permanece na tela. A matriz está em `PanelTune.f0-compat.spec.js:268-291`. A ação `start` continua preservada exclusivamente quando a flag está desligada, em `:228-231` e `:269-279`; a spec comprova esse caminho legado em `:197-224`.

### Escolhas acessíveis

O `PanelTune` importa `ChoiceSelect` e usa o componente nos três campos de atuação, tom e passagem em `:506-549`. O quarto campo, política para contato sem cadastro, usa `ChoiceSelect` em `AgentAudienceForm.vue:192-205`. Não há `<Select>` nativo nesses campos.

## Conclusão e limite

A correção mínima do P1 conectou o painel existente ao `resume`, preservou a criação legada atrás da flag, bloqueou manual/erro/thread ausente e trocou os quatro selects previstos. Nenhum residual concreto foi encontrado na checagem limitada. Não houve edição de produto, teste, build, navegador, banco, rede, produção, commit, push, merge ou deploy.
