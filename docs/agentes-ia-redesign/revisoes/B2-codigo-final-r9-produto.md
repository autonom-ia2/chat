# B2 — checagem final de contrato e estilo

**Data:** 2026-10-07
**Alvo:** snapshot `20261007-190704-532a5b7b-42bf732f84-0ababeca` em
`/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`
**SHA de conteúdo:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`
**Escopo:** enum, gate do Copilot, ordem da validação, contrato de configuração e resíduos Enterprise.

## Resultado

**B2 permanece aberto por qualidade de código.** O resultado coordenado informado para o snapshot
registra 222 exemplos Ruby verdes, zero pendências/externos e 43 testes JavaScript verdes. A bateria de
lint, porém, ainda tem seis ofensas em 106 arquivos analisados. Não há, nesta checagem, novo defeito
funcional no enum, no gate do Copilot ou no contrato público de configuração.

## Contrato verificado

`Agent.actuation` continua com `external: 0`, `internal: 1` e `both: 2`
(`app/models/autonomia/agents/agent.rb:91-95`). A validação na fronteira só aceita o nome textual
presente no enum (`app/controllers/concerns/autonomia/agents/request_validation.rb:12-20`); valores
numéricos são rejeitados antes de `create`/`update` e antes de qualquer assign. A validação do Copilot
vem depois e considera somente `internal`/`both` (`:22-31`), consultando as quatro condições do serviço
compartilhado — CRM, Autonom.ia, Copilot e CRM AI
(`app/services/autonomia/agents/copilot_availability.rb:10-20`).

A ordem observável permanece: o controller registra `fetch_agent` e então inclui o concern
(`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:1-3`); o concern registra, nessa ordem,
configuração pública, tipo do enum e disponibilidade do Copilot
(`request_validation.rb:4-8`). A validação pública ocorre antes de `agent_params`, que ainda sanitiza
e mescla a configuração sem substituir o blob protegido
(`agents_controller.rb:159-173,188-200`; `config_contract.rb:1-47`). Não encontrei alteração de contrato
ou regressão funcional nessa sequência.

## Resíduos que mantêm o lote aberto

### B2-FINAL-STYLE-01 — três ofensas no concern de validação

`app/controllers/concerns/autonomia/agents/request_validation.rb:5-7` declara três
`before_action` para `create` e `update`. O concern não define esses métodos lexicalmente; eles existem
no controller que o inclui. O lint `Rails/LexicallyScopedActionFilter` continua acusando as três linhas.
Isso é uma falha de estilo/estrutura do lint, não uma falha funcional comprovada no callback.

### B2-FINAL-STYLE-02 — três ofensas no spec Enterprise real

`spec/enterprise/requests/api/v1/accounts/autonomia/agents/analytics_wrong_replies_spec.rb:104-107`
mantém a continuação dos argumentos de `create(:message, ...)` desalinhada para a regra de hash/argument
alignment. A correção anterior apontou para um caminho de controller diferente; o arquivo real de
requests permaneceu intocado. O residual é de formatação do spec e não muda o comportamento da gaveta.

## Correção mínima futura

Registrar os três callbacks no `AgentsController`, imediatamente após o `include`, mantendo a ordem
atual, e deixar o concern apenas com os validadores privados; isso remove a ambiguidade lexical sem
mudar o contrato. Em seguida, alinhar as três linhas do `create(:message, ...)` no spec Enterprise
real. Rodar novamente somente o lint direcionado e a bateria coordenada já usada. Até essa checagem,
B2 não deve ser declarado GREEN.

Esta checagem foi somente leitura; não alterei produto, specs, runtime, banco, produção ou configuração.
F0/F1 não são aceitos por este relatório.
