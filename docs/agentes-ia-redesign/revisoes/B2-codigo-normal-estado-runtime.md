# Revisão normal B2 — código — estado, proveniência e execução assíncrona

Escopo: revisão independente do estado privado, digest, validade do teste, identidade do ator e
pipeline assíncrono de B2. A leitura foi feita no snapshot imutável
`fb59e799170f2c57a42bf498a0beaebba382305b0f75df50a4fb2b351af0ef27`, em
`/Users/Shared/maccluster-workspaces/chat2you/20261007-180541-532a5b7b-fb59e79917-20069aba/src`,
confrontando `docs/agentes-ia-redesign/design/B2.md` e os leitores reais do agente.

Não executei RSpec, build, banco, navegador ou produção. A bateria ampla comunicada pelo principal ainda
tem falhas de fixtures antigas de copilot; isso não foi usado como prova de falha de runtime nesta revisão.

## Achados

### B2-CODE-STATE-01 — alto (P1): pedido Redis expirado ainda pode produzir teste válido

**Prova.** O contrato de B2 diz que pedido expirado é inválido e não pode formar a prova de teste
(`docs/agentes-ia-redesign/design/B2.md:379-386`). O pedido Redis tem TTL de 30 minutos e `finish` apenas
desiste quando a chave já sumiu (`app/services/crm/ai/interactive_request.rb:1-32`). O job lê e reivindica
o pedido uma vez, executa a operação e grava o resultado no `AgentStateStore` antes de chamar `finish`
(`app/jobs/crm/ai/interactive_job.rb:10-28`; `app/services/crm/ai/interactive_operation_agent_test.rb:13-54`).
O `TestResultRecorder` fecha a sessão usando só os dados carregados do pedido e o estado atual do agente
(`app/services/autonomia/agents/test_result_recorder.rb:13-29,73-110`).

Se a chave expirar durante `operation.perform`, o recorder ainda grava `completion=completed` e o job
depois encontra `data.nil?` em `finish`; a lista pode então mostrar E4, enquanto o polling do pedido
retorna 404. A conclusão deixou de ter uma requisição viva e não pode ser auditada pelo resultado que a
originou.

**Correção mínima.** Vincular a conclusão a uma verificação atômica de existência/lease do pedido no
mesmo passo que permite gravar o estado, ou revalidar a chave antes do recorder e registrar `stale` se
ela expirou. `finish` deve continuar sem ressuscitar a chave; a correção precisa impedir a gravação,
não apenas esconder o polling.

### B2-CODE-STATE-02 — alto (P1): o polling de um pedido antigo recebe o estado da sessão atual

**Prova.** O contrato exige que sessão divergente seja stale e que o polling mantenha a identidade do
pedido (`docs/agentes-ia-redesign/design/B2.md:384-401`). O controller autentica o pedido, mas monta o
bloco `test` chamando `public_payload` sem passar o `session_id` contido em `data['inputs']`
(`app/controllers/api/v1/accounts/ai_requests_controller.rb:22-35`). O recorder, por sua vez, lê o
único `AgentStateStore` atual do agente (`app/services/autonomia/agents/test_result_recorder.rb:31-53`),
e o resolver aceita qualquer sessão quando o contexto não fornece uma (`app/services/autonomia/agents/agent_state_resolver.rb:132-137`).

Cenário concreto: S1 termina, S2 é iniciada e o usuário consulta o request de S1. O JSON externo traz o
resultado de S1, mas `test.status`, `valid` e os digests são calculados sobre S2. Se S2 já terminou,
o request antigo pode apresentar a prova da sessão nova; se S2 está pendente, a resposta concluída fica
com um bloco `test` pendente. O ator é o mesmo usuário, mas a proveniência do resultado está errada.

**Correção mínima.** Passar a sessão do request ao recorder e exigir igualdade antes de montar o bloco
`test`; em caso de divergência devolver um estado tipado stale sem consultar a prova de outra sessão.
Manter as verificações atuais de conta, membro e token.

### B2-CODE-STATE-03 — alto (P1): disponibilidade de ferramenta nativa não entra no digest efetivo

**Prova.** B2 exige que o digest reflita o vetor de ferramentas que o runtime realmente entrega ao modelo
(`docs/agentes-ia-redesign/design/B2.md:280-296,347-355`). O `TestDigest` registra apenas a lista mantida
ou a configuração bruta de slugs (`app/services/autonomia/agents/test_digest.rb:33-55`). Já o caminho de
execução monta as nativas por `Tools::Registry.for_agent`, que seleciona cada slug e aplica
`available_for?` (`app/services/autonomia/agents/tools/registry.rb:68-76`), e o `Tools::Bound` usa esse
resultado no prompt (`app/services/autonomia/agents/tools/bound.rb:23-31`). Por exemplo,
`InsuranceCapabilities.available_for?` remove a ferramenta quando a feature está desligada ou não há
conexão pronta (`app/services/autonomia/agents/tools/native/insurance_capabilities.rb:75-82`).

Assim, a mesma configuração `native_tool_slugs` produz um prompt com a ferramenta quando a conexão está
pronta e outro prompt sem ela quando a conexão cai, mas o `tested_digest` permanece igual. O agente pode
continuar E4 apesar de a prova ter sido feita com um catálogo diferente do que será usado na execução.

**Correção mínima.** Calcular o componente do digest a partir do catálogo efetivo da mesma Registry usada
no runtime, incluindo apenas identidade pública e estado de disponibilidade necessário para distinguir o
vetor; manter a representação hash e sem credenciais. Cobrir ativação e perda de disponibilidade antes
de live.

### B2-CODE-STATE-04 — médio (P2): digest de operação usa valores crus onde os leitores usam valores efetivos

**Prova.** A matriz de B2 manda hashear valores efetivos, com os mesmos defaults e normalizações do
runtime (`docs/agentes-ia-redesign/design/B2.md:252-296`). O digest usa diretamente `silence_tokens`
(`app/services/autonomia/agents/test_digest.rb:41-48`), `confidence_threshold`
(`app/services/autonomia/agents/test_digest_components.rb:26-32`) e `voice`
(`app/services/autonomia/agents/test_digest_components.rb:43-50`). Os leitores fazem outra coisa:
`Responder` aplica trim, minúsculas, remoção de marcação e fallback para o token padrão
(`app/services/autonomia/agents/operate/responder.rb:97-105`); `Answerer` faz parse estrito e clamp do
limiar (`app/services/autonomia/agents/answerer.rb:648-659`); `Config.voice_for` normaliza espaço/caixa
e cai em `marin` quando necessário (`app/services/autonomia/agents/config.rb:298-308`).

Por exemplo, `[' OK ']` e `['ok']` têm o mesmo efeito para o Responder, `1.0` e `2.0` resultam no
mesmo limiar após clamp, e `" FEMININA "` e `"feminina"` escolhem a mesma voz. As representações
cruas geram digests diferentes e invalidam uma prova que ainda tem o mesmo comportamento, levando o
usuário a E3 sem mudança efetiva.

**Correção mínima.** Montar esses campos pelos leitores/normalizadores já existentes e hashear somente
o resultado efetivo, sem criar defaults ou coerções paralelas. Acrescentar casos de equivalência e de
mudança efetiva; não relaxar a validação da entrada.

## Conferências sem novo achado

- `AgentStateStore` grava o namespace privado sob lock, valida a sessão na conclusão e preserva o ator e
  a permissão efetiva (`app/services/autonomia/agents/agent_state_store.rb:39-53,148-183`).
- O resolver mantém E5/E6 antes do teste, rejeita conclusão de viewer para E4 e exige digest, versão e
  ator `AccountUser` com permissão de gestão (`app/services/autonomia/agents/agent_state_resolver.rb:39-63,107-143`).
- A projeção de material separa `kind=knowledge` de mídia, usa uma única decisão para digest e leitura,
  e registra o maior `updated_at` das entradas prontas (`app/services/autonomia/agents/material_projection.rb:69-116,200-211`).
- O pipeline de ingestão conserva a geração anterior em falha e usa token para impedir que um re-sync
  antigo sobrescreva o novo (`app/models/autonomia/agents/source.rb:151-196`; `app/services/autonomia/agents/knowledge/ingestor.rb:51-72`).

## Conclusão

B2 não deve ser considerado GREEN: há quatro achados concretos no vínculo entre estado, proveniência,
digest e execução assíncrona. Nenhuma correção de produto foi feita nesta revisão.
