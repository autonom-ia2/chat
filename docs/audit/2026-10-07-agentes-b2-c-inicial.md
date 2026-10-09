# B2-C inicial — causas antes da correção

Data: 2026-10-07  
Worktree: `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
Branch: `docs/agentes-ia-prd`

## Escopo e evidência

Esta nota registra as causas observadas na primeira validação dos serviços e da projeção de canais antes de qualquer correção deste bloco. O job executou 117 exemplos: 87 passaram e 30 falharam, sem erro fora de um exemplo (`/tmp/chat2you-agentes-b2-initial.json`). O log Rails usado para a investigação é o do snapshot M4:

`/Users/Shared/maccluster-workspaces/chat2you/20261007-171803-532a5b7b-137087fb42-2b3f3f5e/src/log/test.log`

Os demais 28 failures pertencem a arquivos e ownerships de outras fatias; não são alterados aqui.

## C1 — HTTP 500 na projeção de canais

**Sintoma:** `spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb:61` recebeu HTTP 500.

**Causa comprovada:** `app/controllers/api/v1/accounts/autonomia/agents/channels_controller.rb:65` acessa `link.agent_id`. O modelo `Autonomia::Agents::AgentInbox` declara a associação `belongs_to :agent` com `foreign_key: :autonomia_agent_id` em `app/models/autonomia/agents/agent_inbox.rb:32-36`; não há método/coluna `agent_id`. O log do snapshot confirma `NoMethodError (undefined method 'agent_id' for an instance of Autonomia::Agents::AgentInbox)` na linha 3751, chamado a partir de `occupied_inboxes`.

**Efeito:** qualquer inbox ocupado por um agente mantido quebra a resposta inteira antes do Jbuilder.

**Correção mínima:** usar a associação já carregada (`link.agent.id`) para preencher o campo público `occupied_by.agent_id`, mantendo o contrato da API sem criar uma coluna ou endpoint.

## C2 — `has_schedule` de horário da caixa retornava `false`

**Sintoma:** `spec/requests/api/v1/accounts/autonomia/agents/channels_spec.rb:90` esperava `true` para a inbox `Horário da caixa` e recebeu `false`.

**Causa comprovada:** `app/controllers/api/v1/accounts/autonomia/agents/channels_controller.rb:78` construía o mapa com `inboxes.index_with`. Como `inboxes` é uma lista de objetos `Inbox`, as chaves resultantes eram os próprios objetos. O Jbuilder consulta esse mapa por inteiro em `app/views/api/v1/accounts/autonomia/agents/channels/index.json.jbuilder:17` (`fetch(inbox.id, false)`), portanto não encontrava a chave e aplicava o fallback `false`.

O dado de entrada não era o problema: o log registra a criação da inbox com `working_hours_enabled: true` nas linhas 3785 e 3793, e a requisição carrega a agenda CRM da inbox 3131 na linha 3846. A falha ocorria na chave do mapa, depois da regra compartilhada.

**Efeito:** uma caixa com horário comercial ligado aparecia na UI como se não tivesse horário; o mesmo defeito atingia caixas conectadas e ocupadas quando a renderização chegava a elas.

**Correção mínima:** construir o mapa com chaves `inbox.id` explícitas (`to_h { |inbox| [inbox.id, ...] }`) e manter a precedência da função compartilhada: agenda CRM utilizável, depois horário da caixa.

## C3 — achados de lint diretamente nesta fatia

O RuboCop do snapshot (`m2-b20d7658e3aa4664b3c543ecd1efb905`) apontou, nos arquivos sob esta ownership:

- indentação da cadeia `joins/where/pluck` e `Rails/Pluck` em `channels_controller.rb`;
- `Naming/PredicateName` para `EngagementGate.has_schedule?`;
- `Performance/CollectionLiteralInLoop` e `Style/BitwisePredicate` na matriz de quatro flags de `copilot_availability_spec.rb`;
- `Style/IfUnlessModifier` e `Rails/SkipsModelValidations` em `mirror_identity_sync_spec.rb`;
- `Rails/SkipsModelValidations` no helper de vínculo arquivado de `channels_spec.rb`.

São ajustes de forma ou de fixture de teste; não mudam autorização, escopo de conta, payload nem a regra de horário.

## Limite desta etapa

Nenhum RSpec, banco, build, push, PR, merge ou produção será executado neste bloco. Após os ajustes, ficam pendentes uma nova execução no snapshot autorizado e a separação dos failures das outras ownerships.

## Correções aplicadas após o registro das causas

- `channels_controller.rb` agora usa `link.agent.id` e gera o mapa de agenda por `inbox.id` explícito; a chamada interna foi renomeada para `EngagementGate.schedule?` para preservar a regra do projeto e eliminar o falso positivo de lint.
- A matriz de flags do Copilot usa uma lista local e `Integer#anybits?`; o request spec usa `instance_double` verificável.
- Os fixtures de espelho e canais usam `update!` e o caso agregado de canais declara `aggregate_failures`, sem pular validações silenciosamente.
- Os dois serviços novos usam a forma compacta de classe exigida pelo RuboCop.

Validações locais, sem banco: `ruby -c` nos sete arquivos Ruby da fatia, `git diff --check` e RuboCop direcionado nos oito arquivos (`ok`, 0 offenses). A correção funcional ainda precisa ser confirmada no próximo snapshot; não foi executado RSpec neste bloco.
