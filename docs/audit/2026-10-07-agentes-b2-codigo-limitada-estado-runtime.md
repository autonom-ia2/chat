# Audit — checagem limitada B2 de estado, sessão e digest

Data: 2026-10-07

## Alvo e escopo

Leitura somente do snapshot24:

- caminho: `/Users/Shared/maccluster-workspaces/chat2you/20261007-185427-532a5b7b-b1aa0b036a-315b68de/src`;
- SHA: `b1aa0b036a4d47b5c82d889cb07de3cd05a395db71554c5464fb71d7760b9d8f`;
- escopo: `B2-CODE-STATE-01`, `02`, `04`, normalização de silêncio/confiança/voz e vetor nativo efetivo do `TestDigest`.

Não revi `Connection`, `Registry` ou `ListProjection` como integração N1; essa verificação pertence ao
owner independente. Não houve execução de RSpec, build, banco, navegador, serviço ou produção.

## Conferência

1. `InteractiveJob` revalida pedido e claim após a operação; expiração observada registra `stale`. A
   finalização usa `XX/KEEPTTL` e, se a chave desaparecer entre as checagens, a sessão também é marcada
   `stale`. `AgentStateStore` exige a sessão atual e estado pendente sob lock.
2. O polling encaminha a `session_id` do pedido ao `TestResultRecorder`. Uma divergência retorna um
   payload tipado `stale` antes de expor digests; a spec S1→S2 cobre essa proveniência.
3. `TestDigest` usa o vetor produzido por `Tools::Registry` ou o vetor pré-carregado da projeção, e
   hasheia somente identidade pública. A spec disponível/indisponível exige digests diferentes e ausência
   de URL/token.
4. Silêncio, confiança e voz passam pelos normalizadores reais (`Responder`, `Answerer` e `Config`).
   A spec comprova equivalência efetiva e mudança efetiva, sem colocar texto privado no payload.

## Resultado

**PASS limitado, sem residual concreto encontrado nesta fatia.** A execução não foi feita por esta
sessão. Depois da leitura, o principal comunicou 222 exemplos Ruby, uma falha de orçamento da projeção
N1 (14 SELECTs para 20 agentes, fora deste escopo), e aprovação dos casos novos de STATE, digest privado
e vetor nativo. O lote B2 ainda não é GREEN; não há declaração de CI ou release.
