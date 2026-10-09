# Auditoria global de Agentes — 06 — contratos de criação

Data: 2026-10-09  
Escopo: contratos frontend/backend da criação, retomada, materiais, teste, publicação e pronto.  
Worktree auditada: /Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd  
Branch/HEAD informado: docs/agentes-ia-prd / 532a5b7beb56902d2a0168013a3e8b657ba31488  
Baseline informado no handoff: main 28e1e0ac8b3835577f7469368f03a86d1a8dab0d.

## Veredito

O lote não está pronto para PR enquanto o P1 abaixo permanecer. Não encontrei P0 nos caminhos auditados. Isso não é uma afirmação de ausência universal: a conclusão está limitada aos arquivos, contratos e estados descritos nesta auditoria.

- **P1 — contradiz o contrato de retomada:** erro 401/404/422 ao hidratar a thread manda a pessoa para a lista, embora B3 exija manter o agente e a pessoa na tela com texto localizado.
- **P2 — contrato de fechamento sem caller na tela nova:** no_materials e force_close existem no backend e no store, mas a jornada nova nunca os envia. Um caso de material pendente pode depender indefinidamente da leitura textual do modelo.
- **P2 — conflito assíncrono perde o código:** o backend devolve 409 build_in_progress, o store inicia polling, mas a página exibe erro genérico e não limpa esse erro quando a geração termina.

Nenhuma alteração de código, runtime, banco, fixture, snapshot ou Git foi feita por esta auditoria. O arquivo desta auditoria é a única entrega desta frente.

## Evidência e método

- Li o HANDOFF, PRD §§6.2, 6.6, 6.7 e 7, B3, B4b e F2-F3, concentrando a leitura nos contratos citados no escopo.
- A prova .codex/preview/global-audit-20261009/working-vs-source80.json informa source80_exists=true, 367 entradas examinadas e differences=[]; usei a árvore de trabalho correspondente.
- Comparei chamadas da página, composable, store e API com params, strong params, serializers, jobs, locks e efeitos persistidos.
- Inspecionei specs existentes como evidência de cobertura, sem tratá-las como prova independente quando repetem a implementação.
- A revisão posterior do root refutou a hipótese preliminar de quebra do PATCH de apresentação: o wrapper global JSON de config/initializers/wrap_parameters.rb aplica o fallback agent no namespace; o probe standalone Rails 7.1.5.2 confirmou 200 com name/greeting em .codex/preview/global-audit-20261009/rails-params-wrapper-probe-ascii.json, com escopo de herança em .codex/preview/global-audit-20261009/rails-params-wrapper-scope.json.
- Não rodei bateria Ruby/Vitest, IA paga, produção ou prévia: a bateria Ruby global pertence à coordenação.
- As diferenças de árvore antiga levantadas na frente 05, incluindo as verificações readonly de routes.rb e interactive_operation.rb, não foram contadas como defeitos deste contrato; não há remoção introduzida confirmada nesta frente.

## Achados

### P1-06.2 — falha da retomada redireciona para a lista

**Gatilho:** uma pessoa com permissão de gestão escolhe Continuar e o GET nested de retomada retorna 401, 404 ou 422, por exemplo thread inexistente, agente manual ou recusa da Lia.

**Efeito:** AgentCreationPage.loadEntry chama resume em app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.vue:338-361. Qualquer exceção, inclusive a resposta de retomada, entra no catch de app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.vue:379-384, mostra alerta genérico e executa goToList. A pessoa perde a tela do agente e o contexto que deveria permitir corrigir ou continuar.

B3 exige explicitamente manter a pessoa na tela para 404/401/422 e exibir texto localizado em docs/agentes-ia-redesign/design/B3.md:260-267. O backend está alinhado: BuildThreadsController#resume resolve agente/thread account-scoped e aplica as recusações em app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb:7-17, enquanto BaseController traduz manual para 422 com código em app/controllers/api/v1/accounts/autonomia/base_controller.rb:19-31.

**Causa:** o store preserva a projeção anterior, mas converte o erro em um novo Error sem response/status/code em app/javascript/dashboard/store/modules/autonomiaBuildThreads.js:211-227 e app/javascript/dashboard/store/utils/api.js:95-111. A página não consegue distinguir a recusa e usa o redirect como tratamento universal.

**Teste/cobertura:** AgentsContinue.integration.spec.js:246-273 espera explicitamente retorno à lista em 401/404. Esse teste confirma a implementação atual, mas contradiz B3 e não deve ser usado como aprovação do contrato. O spec de store em autonomia/buildThreads.spec.js:504-523 verifica a preservação do store, não a decisão de rota.

**Proposta:** preservar uma exceção normalizada com status e code no action resume; manter a rota e renderizar erro inline localizado para 401/404/422. Só sair pela ação explícita da pessoa. Atualizar o teste de integração para provar permanência do agente e ausência de start/create.

**Confiança:** alta.

### P2-06.3 — sinais de fechamento existem, mas a tela nova não os chama

**Gatilho:** a pessoa escolhe não usar materiais ou tenta encerrar a etapa Conte/Materiais pela ação da tela depois de responder o que já sabe.

**Efeito:** o backend aceita e persiste os sinais privados no_materials e force_close em app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb:104-123; o store fornece declareNoMaterials e completeMaterials em app/javascript/dashboard/store/modules/autonomiaBuildThreads.js:377-399; o API mergeia esses extras no POST de messages em app/javascript/dashboard/api/autonomia/buildThreads.js:49-65. Porém a página nova só usa BuilderChat, anexo, materiais e a navegação condicionada a readyForTest em app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentBuildTellPage.vue:148-170 e app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.vue:223-226. Não há caller novo para nenhuma das duas actions.

O único uso de completeMaterials encontrado é o caminho legado em app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentBuilderPage.vue:454-484. Assim, a tela nova depende da leitura textual user_asked_to_close/close_intent? do modelo para fechar. Se houver material needs_resend ou uma resposta ainda marcada como pendente, o botão continua bloqueado e não há sinal determinístico da intenção da pessoa. B3 diz que esses sinais vêm da tela, são privados e não devem criar mensagem artificial em docs/agentes-ia-redesign/design/B3.md:248-254.

**Causa:** a implementação nova migrou o layout e o botão de avanço, mas não conectou o contrato de fechamento já criado no store. A Escolha também sempre envia withKnowledge=true em app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentBuildChoosePage.vue:104-119; não há ação explícita de sem base na jornada nova.

**Teste/cobertura:** os unit specs do store em autonomia/buildThreads.spec.js:526-556 provam somente que as actions montam os extras. Não há teste de página que prove o request com no_materials/force_close na jornada nova.

**Proposta:** conectar uma ação explícita de encerramento da tela nova às actions existentes, aguardar o 202/poll e só então avançar. Preservar a guarda de knows do backend, que deve devolver a pergunta faltante em vez de fechar à força.

**Confiança:** alta para a ausência de caller; média para a frequência do bloqueio, porque o caminho textual do modelo ainda pode fechar em muitos casos. A severidade sobe para P1 se o requisito operacional for que o botão da tela seja a autoridade de fechamento.

### P2-06.4 — 409 assíncrono não chega como estado compreensível

**Gatilho:** dois envios concorrentes ou um retry dentro da geração ativa fazem BuildThreadsController devolver 409 build_in_progress em app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb:47-67 e :141-145.

**Efeito:** o store reconhece o 409, inicia polling, mas relança o erro cru em app/javascript/dashboard/store/modules/autonomiaBuildThreads.js:333-343. useAgentCreation registra esse erro e AgentCreationPage transforma qualquer erro em texto genérico em app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.vue:111-116. A UI pode continuar exibindo “erro ao enviar” mesmo quando o polling conclui a geração, sem usar o código estável para dizer “ainda respondendo”.

**Causa:** o tratamento de concorrência foi implementado no store, mas não existe mapeamento de status/code no composable ou na página nem limpeza do erro ao settle.

**Teste/cobertura:** a lógica de polling e o branch 409 foram lidos estaticamente; não houve teste de concorrência/runtime nesta frente.

**Proposta:** manter o polling, converter 409/build_in_progress em estado transitório localizado e limpar o erro quando o poll aplicar uma resposta pronta ou falha definitiva. Cobrir o caso com duas chamadas, sem duplicar mensagem ou SubmitJob.

**Confiança:** alta no caminho de erro; média no impacto visual persistente, pois depende do momento em que o poll settle.

## Matriz de contratos verificados

| Caminho | Chamada e payload | Efeito backend | Resultado da auditoria |
|---|---|---|---|
| Escolha → Conte | POST build_threads com type, actuation, with_knowledge e autonomia_agent_id opcional | cria thread e rascunho antes do 202; enfileira SubmitJob | Compatível no caminho nominal; a escolha não escreve agente por fora |
| 202 do Construtor | resposta envelopada em payload com id/status/state; show por id | processing → ready/failed; store faz polling | Compatível; create/messages e show usam o mesmo id |
| Retomar | GET nested agents/:agent_id/build_thread | última thread account-scoped por id DESC; não cria thread/job | Backend/store compatíveis; política de erro da página é P1 |
| Mensagens/materiais | POST messages com message, client_message_id, image_signed_ids e extras | persiste turno, sinaliza flags, inicia um job | Forma compatível; caller dos sinais não existe na tela nova |
| Fontes/reutilização | source[...] para create multipart, source_id inteiro para copy, payload para reusable | kind é resolvido no controller; cópia sob lock; ingest assíncrono | Compatível estaticamente |
| Teste | POST agents/:id/test com message, history e images | 202 com poll_url; sessão/digests são gravados antes do job | Compatível; o teste concluído atualiza o estado privado |
| Poll do teste | GET poll_url até done/failed | resultado inclui projeção pública do teste | Compatível: DeferInteractiveAi sempre emite poll_url em app/controllers/concerns/defer_interactive_ai.rb:8-14 |
| Apresentação | PATCH agents/:id com name/greeting | wrapper global JSON infere agent; controller persiste os campos | Compatível no probe standalone; app frontend não foi bootado |
| Ligue único/múltiplo | POST publish com inbox_id ou inbox_ids e agent.config.response_window | valida tudo, locks, ativa e conecta em transação | Compatível; frontend manda inbox_ids e não manda name/greeting |
| Pronto | show do agente e channels após publish | projeção final de status/canais | Compatível no caminho nominal |
| Manual/Lia/viewer | manual/Lia recusam retomada; viewer não recebe build thread | 422/401 account-scoped | Guards backend presentes; a página nova perde status/código no erro |

## Cobertura e lacunas

Cobri as páginas Escolha, Conte, Teste, Ligue e Pronto; API/store de agents, buildThreads, sources e channels; controllers/concerns/models/jobs/serializer de thread, teste e publicação; os estados E1–E6 e as respostas 202, 401, 404, 409 e 422 relevantes. Também conferi instrução manual, retomada guiada, materiais reutilizáveis, digest/sessão do teste e publicação multi-inbox.

Ficaram como lacunas de evidência, sem virar aprovação: nenhum teste real de browser nesta rodada; nenhuma execução de job ou provedor de IA; nenhum teste de dupla submissão; o app frontend não foi bootado para confirmar o caller completo da apresentação; e nenhuma prova runtime de 401/404/422 na página nova. O probe standalone do controller confirmou somente o wrapper/strong params do Rails, não a jornada frontend inteira. A bateria global Ruby e as verificações de integração da coordenação continuam sendo evidência separada.

O contrato 202/poll_url nominal está fechado por leitura cruzada: o controller sempre cria o InteractiveRequest, agenda o job e devolve poll_url; o helper trata done/failed; o endpoint de leitura restringe conta, usuário e token; o recorder grava digest, ator e validade. Isso não cobre provider real nem qualidade do modelo.

O contrato de publicação nominal também está fechado por leitura: a tela só envia canais elegíveis e responseWindow; a API monta inbox_ids e agent.config.response_window; Publisher valida instrução, teste atual, copilot e inbox antes de escrever e conecta todos sob transação. Isso não transforma a aprovação local em autorização de merge, deploy ou produção.

## Ações recomendadas antes da próxima frente

1. Corrigir P1-06.2 e trocar o spec que aprova o redirect por permanência localizada na tela.
2. Decidir e conectar a autoridade de fechamento da tela nova; se o botão não deve enviar os sinais, remover ou documentar o contrato morto antes do PR.
3. Mapear 409 para estado transitório e cobrir sem duplicar turno/job.
4. Reexecutar as verificações de frontend/backend da coordenação após essas correções; nenhum teste desta auditoria foi promovido a prova de release.
