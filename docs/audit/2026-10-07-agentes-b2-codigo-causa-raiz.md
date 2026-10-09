# B2 — causa raiz dos achados de estado e runtime

Data: 2026-10-07

Escopo desta seção: os quatro achados `B2-CODE-STATE-01..04` da revisão normal de estado, contra o
snapshot imutável `fb59e799170f2c57a42bf498a0beaebba382305b0f75df50a4fb2b351af0ef27`. Este registro
precede qualquer correção de produto. Os specs RED serão escritos no checkout da branch, mas não serão
executados antes do snapshot coordenado.

## B2-CODE-STATE-01 — pedido expirado pode concluir teste

**Causa raiz:** o lease do pedido Redis só é verificado na leitura inicial. O job executa a operação e
chama o recorder sem uma prova de que a chave ainda existe; `finish` corretamente usa `XX/KEEPTTL`, mas
isso apenas evita ressuscitar o pedido depois que o recorder já gravou a conclusão no estado privado do
agente. A conclusão, portanto, não é atomicamente vinculada à requisição viva.

**Efeito:** uma operação iniciada antes do TTL pode marcar E4 depois da expiração, embora o polling seja
404. O estado do agente fica com uma prova que não pode mais ser associada ao pedido que a produziu.

**Contrato para o RED:** expirar a chave durante `perform` deve impedir `TestResultRecorder.complete!`
e não pode deixar `completion=completed`, `valid_for_state=true` ou uma chave Redis recriada.

## B2-CODE-STATE-02 — polling de S1 pode ler a prova atual de S2

**Causa raiz:** `AiRequestsController#show` entrega ao `public_payload` apenas o agente e os digests
atuais; não passa a sessão presente em `data['inputs']`. `TestResultRecorder.public_payload` lê o único
teste atual no `AgentStateStore`, e o resolver aceita esse contexto sem a identidade do pedido.

**Efeito:** depois que S2 substitui S1 no mesmo agente, o GET do pedido concluído de S1 pode apresentar
status, validade e digests de S2. A resposta perde a proveniência da sessão que o pedido representa.

**Contrato para o RED:** o polling de S1, após iniciar S2, deve retornar estado tipado `stale`/inválido
sem expor `tested_digest`, `material_snapshot_digest` ou `valid=true` da sessão S2; S2 deve continuar
inalterada.

## B2-CODE-STATE-03 — digest de nativas ignora disponibilidade efetiva

**Causa raiz:** `TestDigest` hasheia slugs/configuração mantida e linhas pré-carregadas, enquanto o
runtime chama `Tools::Registry.for_agent`, que filtra cada ferramenta por `available_for?`. O digest não
é calculado sobre o mesmo vetor efetivo que chega ao modelo e não há contrato explícito que impeça
consultas por agente ou a inclusão de credenciais.

**Efeito:** a conexão/feature de uma nativa pode cair, o prompt mudar e a mesma configuração continuar
com o mesmo `tested_digest`. O estado pode permanecer E4 apesar de a prova ter sido feita com outro
catálogo. Uma implementação ingênua também pode introduzir N+1 ou vazar configuração sensível.

**Contrato para o RED:** mudança de `available_for?` altera o componente de ferramentas e o digest;
20 agentes com o mesmo catálogo produzem um número constante de leituras do catálogo, sem credenciais
nem identidade privada. A projeção/listagem mantém os limites já definidos (até 12 consultas da lista e
até 20 do GET, quando aplicável), sem consulta por agente adicionada pelo digest.

## B2-CODE-STATE-04 — digest usa valores crus em vez dos efetivos

**Causa raiz:** os componentes do digest leem diretamente `config['silence_tokens']`, o valor bruto de
`confidence_threshold` e `config['voice']`. Os leitores de runtime aplicam normalização própria já
existente: silêncio com trim/lower/remoção de markup e fallback; confiança com parse/clamp; voz por
`Config.voice_for` com trim/lower/fallback.

**Efeito:** duas entradas que produzem exatamente o mesmo comportamento geram hashes diferentes e
invalidam o teste sem mudança efetiva. Se a correção duplicar os normalizadores, abre uma segunda fonte
de defaults e pode divergir depois.

**Contrato para o RED:** equivalentes efetivos devem compartilhar o digest; mudanças após os limites ou
fallback devem alterá-lo. Os exemplos devem observar os helpers de runtime existentes, sem repetir sua
lógica nos specs ou criar coercão pública nova.

## Ordem de implementação autorizada

Primeiro entram somente os specs RED das quatro causas. Depois do snapshot e da execução coordenada, a
implementação fica limitada a `AgentStateStore`, `AgentStateResolver`, `TestResultRecorder`, `TestDigest`,
`InteractiveOperationAgentTest`, `InteractiveJob`, `AiRequestsController` e normalizadores existentes
quando uma extração real for necessária. Nenhum outro controlador, rota, modelo, locale ou frontend entra
nesta correção.

## Specs RED preparados

- `spec/requests/api/v1/accounts/autonomia/agents/test_state_integration_spec.rb`: expiração durante a
  operação e polling de S1 depois da conclusão de S2.
- `spec/services/autonomia/agents/test_digest_spec.rb`: disponibilidade efetiva da Registry sem segredo
  persistido e equivalência dos valores normalizados de silêncio, confiança e voz.
- `spec/requests/api/v1/accounts/autonomia/agents/index_spec.rb`: vinte agentes com nativas, contagem
  constante de SELECTs e limite de doze SELECTs da projeção.

Os exemplos foram somente escritos e ainda não foram executados. O próximo passo é capturar o snapshot
coordenado e rodá-los no wrapper de testes autorizado; nenhuma alteração de produto foi feita neste bloco.

## RED22 antes da correção

O snapshot22 foi executado pelo principal no wrapper autorizado, sem testes pagos, banco de produção ou
build local: `222 exemplos`, `8 falhas`, `0 pendências` e `0 erros externos` (`/tmp/chat2you-agentes-b2-b3-red22.json`,
SHA `c31bf81db0867e25bd4dc2c3e78f4a45e4f738a691b3f5d6bb90012c6a53b1bb`). As quatro falhas de runtime
confirmaram `B2-CODE-STATE-01..04`: expiração ainda gravava `completed/valid`, polling de S1 mostrava
`completed/valid` de S2, vetor nativo disponível/indisponível mantinha o mesmo digest e valores efetivos
equivalentes mantinham digests diferentes.

O quinto resultado foi a preparação de desempenho: o primeiro spec substituía `Registry.for_agent` por
um stub e esperava vinte chamadas. O RED observado (`0` chamadas) só provava que a fixture não exercitava
a Registry real; não provava as consultas de `available_for?`. A causa da fixture é usar um mock do ponto
que precisava ser medido. A correção da preparação troca o stub por `InsuranceCapabilities` real, uma
`Connection` local sintética pronta e a flag local do módulo, instrumentando SELECTs de 1 para 20 agentes.
Nenhuma rede, credencial ou provedor pago entra no ensaio.

Este registro foi feito antes das extrações de produto autorizadas abaixo.

## Correção do bloco STATE01–04

Depois do RED22, o bloco único autorizado foi implementado sem tocar no modelo `Agent`, nas rotas,
no `BaseController` ou nos controladores de criação. O job interativo só grava a conclusão do teste
enquanto o pedido Redis continua pendente; uma expiração observada durante a operação encerra a sessão
como `stale` e não recria a chave. O polling passa a levar a `session_id` do próprio pedido ao
`TestResultRecorder`; uma sessão antiga recebe apenas o estado tipado `stale`, sem os digests da sessão
atual.

O `TestDigest` passou a montar o vetor nativo efetivo pela `Tools::Registry`, mantendo no hash somente
identidade pública segura da ferramenta, e os componentes passaram a reutilizar os normalizadores de
runtime para voz, confiança e tokens de silêncio. O teste de disponibilidade unitário continua isolando
o catálogo; o ensaio de custo foi corrigido para usar `InsuranceCapabilities` real, uma conexão local
sintética `ready` e a flag local do módulo, sem credencial, rede ou provedor pago. A fixture mede a
projeção de 1 e 20 agentes e exige o limite de 12 SELECTs e a igualdade entre os dois vetores.

Esta seção registra a implementação e a correção da preparação do ensaio; a validação RSpec coordenada
do snapshot ainda não foi executada por esta sessão.
