# B2 — recibo final da causa N1/STATE03

**Data:** 2026-10-07  
**Snapshot final:** `/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`  
**SHA:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`  
**Escopo:** somente orçamento da projeção, disponibilidade nativa em lote, gates e campos lidos.

## Causa e correção fechadas

O snapshot24 falhou com 14 SELECTs quando o contrato permitia no máximo 12. O trace anterior atribuiu os dois extras a `includes(:account)` e à leitura incondicional de `autonomia_insurance_connections`.

No snapshot25, `ListProjection` remove o `includes(:account)` e reutiliza a conta autenticada com `ActiveRecord::Associations::Preloader#available_records`. A leitura de conexões passou a ocorrer somente quando algum rascunho possui ferramenta nativa habilitada. O contexto de disponibilidade segue temporário, isolado e restaurado em `ensure`; a política do Registry continua individual por agente.

## Evidência final

O coordenador informou GREEN no job final: 222 exemplos, zero falhas, zero pendências e zero externos. JSON `/tmp/chat2you-agentes-b2-b3-check25.json`, SHA `80a61547d2542afa66d36d59837c7138da33d4670645256bef83d462fa8ff10b`. O caso misto respeita ≤12 SELECTs; o caso nativo de 1→20 agentes mantém custo constante.

A revisão estática confirmou:

- `READINESS_COLUMNS` contém somente `id`, `account_id` e `status`;
- `ActiveSupport::IsolatedExecutionState` é restaurado em `ensure`;
- `Registry.for_agents` não combina slugs entre agentes;
- os gates usam a disponibilidade canônica por conta;
- o vetor interno não leva credenciais, sessão, capabilities, metadata ou URL ao payload.

**Estado final:** PASS limitado a N1/STATE03. Não há residual concreto neste escopo. F0, F1, B3, CI, merge, deploy e produção não foram avaliados.
