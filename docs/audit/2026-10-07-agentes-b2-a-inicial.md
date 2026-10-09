# B2 — implementação inicial da fatia A: diagnóstico antes da correção

Data: 2026-10-07  
Snapshot de validação: `/tmp/chat2you-agentes-b2-initial.json`  
Resultado observado: 117 exemplos, 30 falhas, 0 falhas fora dos exemplos e 0 pendências.

Este registro foi escrito antes de qualquer correção deste bloco. A leitura foi feita sobre o snapshot capturado; não foram executados testes, banco, build ou RuboCop nesta etapa.

## Causas identificadas

| ID | Causa provada | Evidência e efeito | Escopo |
| --- | --- | --- | --- |
| B2A-01 | `TestDigest#stringify` decide se um valor é hash por `respond_to?(:to_h)`. | `Array#to_h` é chamado para listas de IDs, ferramentas e outras entradas de material; o snapshot registra `TypeError: wrong element type Integer at 0 (expected array)` em `app/services/autonomia/agents/test_digest.rb:193`. A exceção quebra o cálculo do digest e também respostas de telas que o reutilizam. | Fatia A; corrigir recursão tipada para Hash/Array/valor escalar. |
| B2A-02 | `TestResultRecorder.normalize` usa a mesma heurística `respond_to?(:to_h)`. | A normalização de `skipped_tools` e resultados com arrays falha com `TypeError: wrong element type Hash at 0 (expected array)` em `app/services/autonomia/agents/test_result_recorder.rb:93`. | Fatia A; corrigir recursão sem converter Array via `to_h`. |
| B2A-03 | O estado E2m descarta `retention_hours: nil` ao compactar o hash de extras. | O exemplo do contrato espera a chave explícita nula, mas o snapshot recebe apenas `code`, `continuation` e `text` (`spec/services/autonomia/agents/state_resolver_spec.rb:52-55`). | Fatia A; preservar o campo tipado nulo no estado manual. |
| B2A-04 | A fronteira operação → recorder não explicita todos os fatos do contrato de conclusão. | Nos exemplos de playground, a chamada observada a `TestResultRecorder.complete!` não contém `result_real_ai_deferred: true` nem `valid_for_state: false`, embora o contrato teste esses fatos; a operação somente deixa o recorder inferi-los. | Fatia A; passar os fatos explícitos e manter a decisão de validade no recorder/store. |
| B2A-05 | O exemplo de falhas acumula chamadas do mock dentro de um loop e faz uma asserção de chamada única a cada iteração. | O snapshot acusa a segunda passagem como duas chamadas recebidas, embora sejam dois status distintos do mesmo fluxo. É uma falha do teste, não evidência de duas gravações do produto. | Spec da fatia A; coletar as chamadas e comparar a sequência uma vez. |
| B2A-06 | A fixture legada de requests de IA não habilita `CRM_AI_ENABLED`. | Os exemplos de copilot retornam 404 antes do fluxo e geram falhas em cascata; a fixture já habilita as flags de agentes, kanban e copilot, mas não a flag de IA usada pela rota. | Spec da fatia A; completar o ambiente da fixture sem alterar a guarda de produção. |
| B2A-07 | Falhas de integração, polling e índice são consequências do erro de serialização acima. | O snapshot mostra `Nokogiri::HTML4::Document` onde o exemplo esperava JSON e a integração termina em `completion: error`; o backtrace converge para o fluxo de digest/recorder. Revalidar depois das correções, sem antecipar causa nova. | Fatia A e consumidores; pendente de validação. |
| B2A-08 | A invalidação de material precisava comparar a sessão fotografada pelo escritor dentro do mesmo lock do agente. | Os testes atuais de `MaterialProjection` já chamavam `AgentStateStore.invalidate_if_current!` com a sessão antiga; sem esse escritor no store, um processamento atrasado poderia limpar o teste pendente ou concluído iniciado depois. | Fatia A e material; corrigir com retorno booleano e preservação da sessão atual. |

## Limites da correção

A falha de `MaterialProjection` (mudança de versão de entrada), as falhas de canais e as falhas de componentes de outras ownerships permanecem fora deste bloco. A correção não deve incluir estado informativo de material/cliente/mídia no digest efetivo, nem manter o campo auxiliar `material_input_digest` se ele não participa do contrato B2; timestamps de ferramenta devem manter precisão de microssegundos.

O relatório de lint do snapshot (`/tmp/chat2you-agentes-b2-lint.log`) registra 172 ofensas em 84 arquivos. As correções desta fatia tratam somente as ofensas nos arquivos sob sua ownership e não desabilitam cops nem alteram limites globais.

## Correções aplicadas neste bloco

- `TestDigest` e `TestResultRecorder` agora percorrem Hash, Array e valores escalares sem chamar `Array#to_h`; mantêm valores falsos/nulos e não incluem `material_input_digest` no contrato.
- E2m preserva `retention_hours: nil`; a conclusão passa explicitamente `result_real_ai_deferred` e `valid_for_state` pela operação até o recorder, que continua recalculando a permissão efetiva antes da escrita.
- A fixture legada de copilot recebeu `CRM_AI_ENABLED`; o exemplo de falhas compara a sequência de gravações uma única vez; a fixture de administrador espera `autonomia_manage`.
- O fluxo de operação assíncrona foi separado em um módulo de agente para manter a classe principal sob o limite de tamanho, e os controladores foram divididos em helpers de responsabilidade única.

Validação estática desta etapa: `ruby -c` nos arquivos Ruby alterados e `git diff --check` passaram. A bateria RSpec, o RuboCop, banco, build e produção ficam para o snapshot coordenado pelo root.

Após a leitura dos testes da projeção de material, entrou no mesmo bloco a correção de concorrência já exigida pelo contrato: `MaterialProjection` chama `AgentStateStore.invalidate_if_current!` com a sessão fotografada pelo escritor, e o store só limpa o teste dentro do `Agent.with_lock` quando essa sessão ainda é a atual. A sessão nova permanece intacta quando o escritor antigo chega depois; foram acrescentados os dois casos de store correspondentes.

## Lint estrutural do snapshot16 — causas antes da correção

O lint oficial de 87 arquivos (`m4-93e85d65ebf54079b509e0c18294fdce`) encontrou 57 ofensas. Antes desta correção, as causas da fatia A eram:

- os serviços novos ainda usavam módulos aninhados, listas de parâmetros longas e métodos que acumulavam normalização, validação, decisão e escrita;
- `AgentStateStore#complete!` ainda expunha `result` não usado e keywords opcionais misturadas às obrigatórias; `sanitize_skipped_tools` concentrava catálogo, validação e serialização;
- `AgentStateResolver` concentrava a máquina de estado, a validação do teste e a classificação de invalidação em métodos extensos;
- `TestDigest#call` e `person_values` acumulavam montagem de componentes, e as specs tinham descrições string, helpers longos e alinhamentos pendentes;
- `ai_requests_spec` mantinha dois grupos de request no nível superior.

As três ofensas em `index_spec.rb` e `test_state_integration_spec.rb` ficam com o root conforme a ownership combinada. Nenhuma correção de lint deve alterar guardas, API pública, sessão esperada, digest efetivo ou sanitização privada.

## Validação funcional do snapshot16 — causa antes da correção

O snapshot16 (`/tmp/chat2you-agentes-b2-initial16.json`) executou 124 exemplos, com 20 falhas. Oito falhas diretas da recorder e os erros derivados de polling/integração vieram de `NameError` para `AgentStateStore` após a compactação de `TestResultRecorder`: `class Autonomia::Agents::TestResultRecorder` não mantém o escopo léxico dos módulos aninhados, então referências não qualificadas deixaram de resolver. A correção deve qualificar explicitamente os constantes do namespace, preservando a compactação estrutural.

## Correções estruturais posteriores ao snapshot16

Data: 2026-10-07. O erro de resolução foi corrigido qualificando as referências externas em
`TestResultRecorder` e extraindo a serialização privada de `AgentStateStore` para
`AgentStateStoreSerialization`; isso mantém o escopo compacto sem alterar o contrato público do
store. Também foram extraídos os componentes de pessoa do digest, reduzidos os parâmetros de
`complete_state`/`completed_test` a um objeto de conclusão e separados os auxiliares da máquina de
estado. A chamada de `complete!` continua carregando ator, permissão efetiva, digest, material,
resultado e ferramentas sanitizadas; nenhuma dessas chaves privadas entra na resposta pública.

As specs sob esta ownership foram alinhadas ao nome real dos serviços e ao layout do RuboCop; a
spec do resolver foi renomeada para `agent_state_resolver_spec.rb`. O grupo de requests de IA foi
nivelado em um único grupo RSpec, preservando as duas fixtures de ambiente.

Validação estática após a correção: `ruby -c` nos arquivos Ruby da fatia A, `git diff --check` e
`bundle exec rubocop --force-exclusion` nos arquivos da fatia A passaram sem saída de erro. Nenhum
RSpec, banco, build, produção, commit ou push foi executado após o snapshot16; a validação funcional
seguinte deve ser feita pelo snapshot coordenado pelo root.

A checagem final de whitespace desta etapa foi executada com saída capturada em `/tmp/chat2you-b2a-diff-check.out`; `git diff --check` retornou `0`.

## Diagnóstico do snapshot17 — causas antes da correção

O snapshot17 (`/tmp/chat2you-agentes-b2-initial17.json`) executou 124 exemplos, com quatro falhas. O
índice E1/E2 fica com o root; as três causas desta fatia são:

| ID | Causa provada | Evidência e efeito | Escopo |
| --- | --- | --- | --- |
| B2A-09 | `AgentStateResolver#normalize` ainda decide que qualquer objeto com `to_h` é hash. | `app/services/autonomia/agents/agent_state_resolver.rb:170-175` chama `Array#to_h` quando a projeção pública contém `skipped_tools` como uma lista de hashes. O snapshot17 registra `TypeError: wrong element type Hash at 0 (expected array)` no polling do viewer; a resposta vira 500. | Serviço do resolver e spec unitária do resolver. |
| B2A-10 | O cenário de falha parcial intercepta o construtor da operação, que também é usado pelo endpoint de polling. | `spec/requests/api/v1/accounts/autonomia/agents/playground_spec.rb:154-165` faz `InteractiveOperation.new` levantar a falha do provedor. O job deve falhar, mas o mesmo stub atinge `AiRequestsController#show` no polling e devolve HTML/500 (`NoMethodError` da fixture ao ler `parsed_body`). | Somente fixture do cenário; o produto deve continuar tratando o pedido já finalizado como falho. |
| B2A-11 | O teste do recorder espera conclusão quando a entrada contém erro de provedor. | `TestResultRecorder#failure_completion` (`app/services/autonomia/agents/test_result_recorder.rb:82-89,142-147`) classifica `result[:error]` como `error` e chama `AgentStateStore.fail!`; a expectativa em `spec/services/autonomia/agents/test_result_recorder_spec.rb:138-146` procura `complete!`. A recusa é a proteção correta; o teste precisa provar `fail!`, ausência de `complete!` e ausência dos campos privados no namespace real. | Spec do recorder, sem relaxar sanitização ou gravar diagnóstico do provedor. |

Nenhuma dessas causas autoriza expor erro bruto no polling, marcar E4 ou gravar `completion` enviado pelo
cliente. A correção desta etapa tratará somente o ramo Hash/Array do resolver e alinhará as duas fixtures
às decisões já existentes.

## Diagnóstico do snapshot18 — causa antes da correção

O snapshot18 (`/tmp/chat2you-agentes-b2-initial18.json`, SHA informado pelo coordenador
`8a0f1c79aa7e8199e346dd75748d700d71fd10d0e6d34082a37e3dbc20a6f0d7`) executou 124 exemplos, com uma
falha. A falha é um vazamento real do estado de teste anterior durante o polling de uma operação falha:

| ID | Causa provada | Evidência e efeito | Escopo |
| --- | --- | --- | --- |
| B2A-12 | `AiRequestsController#test_payload_for` usa `result.respond_to?(:to_h)` como presença de resultado. | Em Ruby, `nil.respond_to?(:to_h)` é verdadeiro. Depois de `InteractiveJob` finalizar uma operação como `status=failed`, `InteractiveRequest` contém `result=nil`, mas o controller ainda chama `TestResultRecorder.public_payload`; a leitura de estado privado já concluído (`read` da fixture com hashes `aaaa`/`bbbb`) vira um bloco `test.valid=true` na resposta falha. O snapshot18 registra `status=failed`, `result=nil` e esse teste válido. | Controller de polling, reservado ao root; a spec existente já prova que a falha não pode expor teste. |

O contrato exige que falha/partial/timeout nunca forme E4 nem exponha a prova anterior. A correção mínima é
condicionar o payload de teste ao status concluído e a um resultado Hash presente, sem consultar o estado
privado para um pedido falho; preservar `status=failed`, `result=nil` e ausência de `test`.
