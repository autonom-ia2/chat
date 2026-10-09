# Checagem limitada B2 — estado, sessão e digest

**Data:** 2026-10-07  
**Alvo congelado:** snapshot24 em `/Users/Shared/maccluster-workspaces/chat2you/20261007-185427-532a5b7b-b1aa0b036a-315b68de/src`  
**SHA do alvo:** `b1aa0b036a4d47b5c82d889cb07de3cd05a395db71554c5464fb71d7760b9d8f`

## Escopo

Checagem independente e limitada dos achados `B2-CODE-STATE-01`, `02` e `04`, além da normalização
do digest e do vetor nativo efetivo do `TestDigest`. Confrontei o desenho B2, a causa raiz registrada,
as provas RED22/23 disponíveis e o código congelado.

Não revi a integração N1 de `Connection`, `Registry` e `ListProjection`; essa fatia tem revisão
independente. Não executei RSpec, build, banco, navegador, serviço ou produção. A checagem Ruby do
snapshot24 ainda estava sendo coordenada pelo principal e não foi tratada como GREEN.

## Resultado

**PASS limitado no código estático, sem residual concreto encontrado.** O resultado não antecipa a
execução coordenada, CI ou aprovação de release.

## Evidência

### STATE-01 — TTL e pedido expirado

`InteractiveJob#perform` revalida o pedido e o marcador de claim depois de `operation.perform`, antes
de chamar o recorder (`app/jobs/crm/ai/interactive_job.rb:10-22`). Se o Redis expirou, registra a
sessão como `stale` e sai. Se a expiração ocorrer depois dessa checagem, `finish_operation` só mantém a
conclusão quando `InteractiveRequest.finish` consegue atualizar a chave existente com `XX/KEEPTTL`;
se falhar, a sessão é convertida em `stale` (`app/jobs/crm/ai/interactive_job.rb:53-61`;
`app/services/crm/ai/interactive_request.rb:25-39`). A chave não é ressuscitada.

O estado privado também exige a mesma sessão e `completion=pending` dentro do lock antes de gravar a
conclusão (`app/services/autonomia/agents/agent_state_store.rb:144-160`). A prova preparada para a
expiração remove a chave durante `Playground#run` e exige ausência de `completed/valid` e de uma leitura
Redis posterior (`spec/requests/api/v1/accounts/autonomia/agents/test_state_integration_spec.rb:100-115`).
O caminho cobre tanto a expiração observada durante a operação quanto a falha da finalização posterior.

### STATE-02 — identidade da sessão no polling

O controller passa ao recorder a `session_id` guardada no próprio pedido (`app/controllers/api/v1/accounts/ai_requests_controller.rb:22-38`).
`public_payload` rejeita a sessão atual quando ela diverge da sessão do pedido antes de calcular o
resultado (`app/services/autonomia/agents/test_result_recorder.rb:31-41,143-159`). O resolver ainda
exige versão, sessão, ator e os três digests compatíveis (`app/services/autonomia/agents/agent_state_resolver.rb:107-143`).

O cenário S1→S2 verifica que o polling de S1 retorna `stale`, `valid=false` e nenhum digest da sessão
atual, enquanto S2 permanece `completed/valid` (`spec/requests/api/v1/accounts/autonomia/agents/test_state_integration_spec.rb:117-138`).
Não encontrei caminho no contrato atual que reintroduza a prova de S2 no pedido S1.

### STATE-03 — vetor nativo efetivo

`TestDigest.for_agent` calcula o vetor efetivo chamando a mesma `Tools::Registry.for_agent` usada para
montar as ferramentas do runtime; quando a projeção já carregou o vetor, recebe-o explicitamente e não
volta a consultar o catálogo (`app/services/autonomia/agents/test_digest.rb:14-24,54-57`). O componente
do digest inclui somente `kind`, `slug` e nome público, sem URL ou token (`app/services/autonomia/agents/test_digest_components.rb:31-49`).

O spec troca a ferramenta nativa disponível por uma lista vazia e exige mudança em `tools_digest` e no
`tested_digest`, além de verificar que credenciais não atravessam o resultado
(`spec/services/autonomia/agents/test_digest_spec.rb:156-175`). A checagem aqui é somente do contrato do
digest; o limite de consultas da projeção N1 permanece com o reviewer próprio.

### STATE-04 — valores efetivos de silêncio, confiança e voz

O digest reutiliza os leitores existentes: `Responder.normalize_silence_token` com o fallback do token
padrão (`app/services/autonomia/agents/test_digest_components.rb:51-62`; `app/services/autonomia/agents/operate/responder.rb:42-44`),
`Answerer.effective_confidence_threshold` com parse e clamp (`app/services/autonomia/agents/test_digest_components.rb:110-116`;
`app/services/autonomia/agents/answerer.rb:45-54`) e `Config.voice_for` (`app/services/autonomia/agents/test_digest_components.rb:127-134`;
`app/services/autonomia/agents/config.rb:298-308`). Não há uma segunda implementação de defaults para
esses campos.

O spec comprova que tokens com marcação/espaços, confiança `1.0`/`2.0` e voz com caixa/espaços geram o
mesmo digest efetivo, enquanto uma mudança real de confiança e silêncio altera o digest
(`spec/services/autonomia/agents/test_digest_spec.rb:177-198`). O payload continua contendo apenas
hashes e identificadores permitidos; os valores privados não são persistidos no resultado.

## Limite da conclusão

Este parecer fecha somente a checagem dos contratos acima. Depois da leitura, o principal comunicou o
resultado do snapshot24: 222 exemplos Ruby, uma falha no orçamento da projeção mista de 20 agentes
(14 SELECTs, pertencente à integração N1 fora deste escopo), e os casos novos de STATE, digest privado e
vetor nativo passando. Isso não torna o lote B2 GREEN: a falha N1 permanece aberta e os demais owners,
CI e as gates de telas reais continuam pendentes.
