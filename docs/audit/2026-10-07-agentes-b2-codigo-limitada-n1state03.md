# B2 — recibo da checagem limitada N1/STATE03

**Data:** 2026-10-07  
**Alvo imutável:** `/Users/Shared/maccluster-workspaces/chat2you/20261007-185427-532a5b7b-b1aa0b036a-315b68de/src`  
**SHA informado:** `b1aa0b036a4d47b5c82d889cb07de3cd05a395db71554c5464fb71d7760b9d8f`  
**Escopo:** somente a integração N1 de disponibilidade nativa e o vetor entregue à projeção/digest.  
**Fora do escopo:** TestDigest/job/recorder como implementação, revisão geral B2, testes, banco, build, rede e produção.

## Base da checagem

A causa registrada em `docs/audit/2026-10-07-agentes-b2-n1state03-causa-raiz.md` mediu 9 SELECTs para um agente e 47 para 20 agentes no snapshot23. A correção precisava eliminar a leitura repetida da conexão sem unir slugs de agentes, sem cache global e sem carregar segredo.

## Conferência

- `Autonomia::Insurance::Connection.preload_for_accounts` deduplica os IDs e seleciona somente `id`, `account_id` e `status`. Não carrega credenciais, sessão ou capabilities.
- `with_preloaded_for_accounts` usa `ActiveSupport::IsolatedExecutionState` e restaura o valor anterior em `ensure`. O estado é limitado à execução da projeção; não há cache de processo, conta ou request reaproveitado.
- `ready_for_account?` usa o mapa somente quando o contexto de projeção está ativo. Fora dele, mantém exatamente a leitura anterior por `for_account(account).any?(&:ready?)`.
- `Registry.for_agents` executa `for_agent` individualmente dentro do contexto temporário. Cada agente conserva seus próprios slugs, deduplicação, catálogo e `available_for?`; não há união por conta. A Lia continua derivando sua lista do catálogo mantido pelo deploy.
- `ListProjection` pré-carrega `account`/vínculos, faz uma leitura de conexões por IDs de conta dos rascunhos e guarda o vetor nativo por `agent.id`. O `TestDigest` recebe esse vetor já calculado; o callsite não pede novamente o Registry por agente.
- O serializer do vetor não é exposto pela lista: o mapa nativo permanece interno à projeção e os campos selecionados para disponibilidade não incluem segredo.

## Atualização após a execução Ruby24

A execução coordenada encontrou um residual concreto no orçamento geral: 222 exemplos, 1 falha, 0 pendências/externos. A falha é `index_spec[1:5]`: a projeção mista esperava no máximo 12 SELECTs e observou 14. O registro de execução é `/tmp/chat2you-agentes-b2-b3-check24.json`, SHA `9ef84ec2669c887ad6f1ca4a1db3dcc4898344504365f9a7ae69c418c3bbca04`, job `m2-6c966836c151480392595bde27e5df9c`.

O caso separado de disponibilidade nativa de 1 para 20 agentes passou com custo constante. Assim, a integração de disponibilidade em lote não pode ser declarada completamente GREEN porque o limite de projeção mista falhou, mas a evidência não aponta falha no vetor nativo 1→20.

A causa aparente a confirmar antes da correção final é a soma de duas leituras novas incondicionais em `ListProjection`: `includes(:account, ...)` em `app/services/autonomia/agents/list_projection.rb:11` e `Connection.preload_for_accounts(...)` em `:29`. O primeiro carrega a conta para toda projeção; o segundo executa a leitura de disponibilidade para todos os agentes de rascunho, ainda que a projeção não tenha ferramenta nativa que precise desse gate. O código prova os dois caminhos, mas a atribuição exata dos dois SELECTs deve ser confirmada pelo coordenador com o trace do caso que falhou.

**Estado:** STOP. A avaliação estática anterior fica preservada como evidência, mas o resultado limitado final não é PASS por causa do orçamento observado. Nenhum produto foi editado e esta sessão não executou testes, build, banco, rede ou produção. A correção e a única checagem final permanecem sob coordenação do root.
