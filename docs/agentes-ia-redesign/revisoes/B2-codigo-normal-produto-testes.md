# Revisão normal B2 — código — produto, UX e testes

Escopo: revisão independente do código B2 no snapshot imutável `fb59e799170f2c57a42bf498a0beaebba382305b0f75df50a4fb2b351af0ef27`, em `/Users/Shared/maccluster-workspaces/chat2you/20261007-180541-532a5b7b-fb59e79917-20069aba/src`. A leitura confrontou o PRD, o desenho B2/F1 e os contratos de lista, estado, material, copilot, analytics e retomada.

Não executei RSpec, build, banco, navegador ou produção nesta revisão. A bateria ampla comunicada pelo principal ainda não está verde: há sete falhas de fixture nos fluxos de copilot porque as fixtures ativam três flags e não `CRM_AI_ENABLED`, quarta condição exigida pelo BE-32. Isso é preparação de teste e não foi reclassificado como defeito de produto nesta revisão.

## Achados

### B2-CODE-01 — alto (P1): inteiro do enum contorna o bloqueio de copilot

**Prova.** O contrato B2 exige que `internal` e `both` retornem `422 copilot_unavailable` antes de qualquer gravação quando o copilot não está disponível (`docs/agentes-ia-redesign/design/B2.md:599-603,650`; `docs/agentes-ia-redesign/PRD.md:545`). No snapshot, o guard transforma o parâmetro em texto e só reconhece os nomes (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:93-100`):

```ruby
requested = params.dig(:agent, :actuation).to_s
return unless %w[internal both].include?(requested)
```

O parâmetro depois é permitido diretamente (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:195-202`), enquanto o model declara `actuation` como enum inteiro (`app/models/autonomia/agents/agent.rb:90-94`). O próprio controller registra que o enum normaliza entrada string ou inteira (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:247-250`). Portanto, `actuation: 1` ou `actuation: 2` passa pelo guard como `"1"`/`"2"`, mas é convertido pelo enum para `internal`/`both` no assign. Com copilot indisponível, a API pode persistir uma atuação interna sem o `422` previsto.

**Efeito.** A tela pode listar um agente interno que a instalação não consegue atender, e a regra de no-write do BE-32 fica bypassável por um cliente que use o valor numérico do enum. A especificação existente cobre somente os nomes (`spec/requests/api/v1/accounts/autonomia/agents/copilot_availability_spec.rb:42-57,80-96`), então não detecta esse caminho.

**Correção mínima.** Validar o contrato documentado na fronteira antes do assign e rejeitar valores numéricos com o erro estável de enum inválido, ou aplicar uma validação equivalente que impeça que o valor inteiro alcance o enum. Acrescentar casos de create e PATCH com `1`/`2`, verificando resposta e ausência de mudança parcial. Não basta converter o número para o nome no guard: o endpoint deve continuar aceitando somente o formato público documentado.

### B2-CODE-02 — médio (P2): a chave do canal da lista diverge do contrato público

**Prova.** O requisito BE-01 define `channels: [{inbox_id,name,channel_type}]` (`docs/agentes-ia-redesign/PRD.md:514`). O endpoint de canais existente também expõe `inbox_id` (`app/views/api/v1/accounts/autonomia/agents/channels/index.json.jbuilder:1-8`). Porém, a projeção usada diretamente pelo serializer da lista produz `id` (`app/services/autonomia/agents/list_projection.rb:99-103`), e o serializer a repassa sem adaptação (`app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder:38-43`). O exemplo do desenho B2 usa `id` (`docs/agentes-ia-redesign/design/B2.md:113-118`), enquanto o desenho F1 apenas diz que o front consome `channels[]` sem fixar a chave (`docs/agentes-ia-redesign/design/F1.md:35-41`).

**Efeito.** Um consumidor da primeira tela que siga o PRD ou o endpoint de canais procura `inbox_id` e recebe `undefined`; outro que siga o exemplo B2 usa `id`. O cartão pode continuar mostrando nome/quantidade, mas qualquer ação que precise identificar o vínculo fica sujeita a uma interpretação divergente entre F1 e o painel de canais.

**Correção mínima.** Fixar uma única chave no contrato B2/F1, preferencialmente `inbox_id` por ser o nome normativo do PRD e o já usado pelo endpoint de canais, ajustar a projeção e adicionar uma asserção de request no formato exato. Se a decisão de manter `id` for intencional, ela precisa ser explicitada no PRD e no F1 como contrato único; manter os dois formatos implícitos é o risco concreto.

## Conferências sem novo achado

- A precedência E1–E6/E2m e a retomada de estado são coerentes com os leitores de lista e estado; a seleção da última thread usa a mesma ordenação por `id` descendente.
- Material, retriever, digest e writers preservam a distinção entre `knowledge` e mídia; mídia não é contada como material por inferência do front.
- As janelas de estatísticas da lista acompanham Analytics, e os números internos não são inventados.
- O DTO de respostas marcadas respeita conta, janela, permissão antes de ordenação/limite, múltiplas marcações na mesma conversa e ocultação de conteúdo.
- A disponibilidade do copilot consulta as quatro condições no serviço compartilhado; o problema observado na bateria ampla é a fixture sem `CRM_AI_ENABLED`, não uma mudança normativa do gate.

## Conclusão

B2 não deve ser considerado GREEN: há um bypass P1 do guard de copilot por entrada numérica do enum e uma divergência de contrato P2 para a identidade do canal na lista. Nenhuma correção de produto foi feita nesta revisão.
