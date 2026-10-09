# Revisão final B2 — N1/STATE03 e orçamento da projeção

**Alvo:** snapshot25 `/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`  
**SHA:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`  
**Escopo:** somente projeção da lista, disponibilidade nativa em lote, gates e campos lidos.  
**Tipo:** revisão final única, independente e somente leitura.

## Resultado

**PASS final limitado a N1/STATE03. Não há residual concreto nos contratos conferidos.**

O resultado dinâmico fornecido pelo coordenador é GREEN: 222 exemplos, zero falhas, zero pendências e zero externos. JSON `/tmp/chat2you-agentes-b2-b3-check25.json`, SHA `80a61547d2542afa66d36d59837c7138da33d4670645256bef83d462fa8ff10b`. O caso misto permanece em no máximo 12 SELECTs; o caso de disponibilidade nativa de 1 para 20 agentes mantém custo constante e passa.

Esta sessão não executou a suíte. O resultado acima é evidência do snapshot coordenado pelo root; a conferência abaixo é estática e independente. Não é aceite de F0, F1, B3, produção ou CI.

## Conferência

### Projeção e orçamento

Em `app/services/autonomia/agents/list_projection.rb:10-58`, o caminho final não inclui `account` com uma consulta própria. Os agentes continuam carregando avatar, vínculos e inboxes em lote. `preload_draft_accounts` usa `ActiveRecord::Associations::Preloader` somente para rascunhos e fornece `available_records: [@account]`; a conta já autenticada é reutilizada sem abrir uma leitura de `accounts` nem aceitar outra conta.

`connection_readiness` só chama `Connection.preload_for_accounts` quando algum rascunho tem ferramenta nativa efetivamente habilitada. A leitura é feita uma vez pelos `account_id` dos rascunhos. O vetor nativo é calculado individualmente por agente e entregue ao `TestDigest`; não há nova consulta do Registry dentro do digest.

O trace anterior havia identificado dois SELECTs extras: `accounts` e `autonomia_insurance_connections`. O snapshot25 remove o primeiro e torna o segundo condicional. O GREEN dinâmico confirma o orçamento misto ≤12 e a constância do GET até 20 agentes.

### Conexão e isolamento do contexto

Em `app/models/autonomia/insurance/connection.rb:75-100`, `preload_for_accounts` deduplica IDs e seleciona somente `id`, `account_id` e `status`. Credenciais, sessão, capabilities e metadata não entram na leitura. `with_preloaded_for_accounts` grava o mapa em `ActiveSupport::IsolatedExecutionState` e restaura o valor anterior em `ensure`, inclusive em erro. Fora do contexto, `ready_for_account?` mantém o caminho legado `for_account(account).any?(&:ready?)`.

Não há cache global, reaproveitamento entre requests ou vazamento de uma conta para outra. O mapa é limitado à execução corrente da projeção e indexado pelo `account_id` que foi carregado.

### Registry, gates e Lia

Em `app/services/autonomia/agents/tools/registry.rb:68-84`, `for_agents` mantém a chamada de `for_agent` separada para cada agente. Cada agente conserva seus próprios slugs, deduplicação, catálogo fechado e `available_for?`; nenhum slug é unido por conta.

Os gates de `InsuranceCapabilities` e `InsuranceQuote::Declaracao` consultam `Connection.ready_for_account?`, portanto usam o mapa temporário durante a projeção. A lista canônica da Lia continua vindo de `Agent#ferramentas_nativas` e `QuoteAgent::Builder.ferramentas_mantidas`; a correção não substitui essa política pela configuração de outro agente.

### Segurança dos campos

O único SELECT novo de disponibilidade usa `READINESS_COLUMNS`. O mapa nativo é interno à projeção e não é serializado pela lista. A resposta continua sem credenciais, sessão, capabilities, metadata ou URL.

## Conclusão e limite

N1/STATE03 está fechado nesta revisão final limitada: orçamento dinâmico verde, isolamento preservado, gates corretos e campos seguros. Nenhuma nova correção é necessária neste escopo. F0, F1, B3, CI, merge, deploy e produção permanecem fora desta conclusão.
