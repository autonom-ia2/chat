# Auditoria global 08 — runtime e regressão

**Data:** 2026-10-09
**Escopo:** answerer, prompt, retriever, ferramentas, handoff, jobs, IA nativa, copilot e cotação, comparados aos agentes ativos.
**Base auditada:** worktree agentes-ia-prd, branch docs/agentes-ia-prd, HEAD 532a5b7beb56902d2a0168013a3e8b657ba31488.
**Método:** leitura estática e dos artefatos locais, seguindo a auditoria de arquitetura de agentes em 12 camadas. Não houve alteração de produto, testes, fixtures ou Git, nem execução de teste nova.

## Limite da conclusão

Não há evidência para declarar ausência universal de regressão. A comparação com main é uma diferença de integração: main está em 28e1e0ac8b3835577f7469368f03a86d1a8dab0d, o worktree está 136 commits atrás conforme o inventário, e o runtime de produção não foi verificado diretamente. O parecer abaixo separa fato confirmado, risco condicionado e lacuna.

Os artefatos .codex/preview/global-audit-20261009/working-vs-source80.json e proof-inputs-gestao80.log registram os 367 inputs de produto/spec iguais ao source80; entre os snapshots de gestão 79 e 80 houve somente docs e whitespace AST na especificação de handoff. Portanto, a falha Ruby abaixo é baseline de validação do source80/current, não uma regressão funcional recém-demonstrada.

## Achados

### P1 potencial — falha de roteamento pode impedir a liberação para humano

**Gatilho:** uma resposta sinaliza handoff, ou a cotação entra no caminho de escalada, enquanto o agente tem handoff_target_type=member/team e a atribuição do membro/equipe ou seu callback levanta uma exceção (por exemplo, estado concorrente ou erro de persistência).

**Efeito:** Responder#release_to_humans e AvisoAoAtendente#liberar_para_equipe executam HandoffRouter#route antes de conversation.bot_handoff!, dentro de with_lock. Se o roteador levanta, a transação sai antes de bot_handoff!; o rescue externo registra o erro e devolve silêncio/nota, deixando a conversa potencialmente com o bot ou pending. O cliente pode receber uma resposta que sinaliza passagem sem a conversa ter sido liberada.

**Evidência confirmada por código:**

- app/services/autonomia/agents/operate/responder.rb:173-183 chama route nas linhas 177–179 e só depois chama bot_handoff! na linha 180; o rescue de handoff_if_signaled está em :155-157 e o de skip_for_humans em :168-170.
- app/services/autonomia/agents/operate/aviso_ao_atendente.rb:45-67 repete a mesma ordem para a escalada da cotação; o rescue em :50-53 cai em notar('ia_falhou').
- app/services/autonomia/agents/operate/handoff_router.rb:44-52 chama Conversations::AssignmentService#perform; :55-73 faz update! de equipe e eventual AutoAssignment::AgentAssignmentService#perform, sem rescue local nem fallback em caso de exceção.
- O diff contra o pai confirma que o comportamento anterior fazia bot_handoff! diretamente e que o roteador foi inserido antes dele.

**Classificação:** P1 potencial, confirmado estaticamente e condicionado à exceção no serviço de atribuição; não reproduzido por teste novo por restrição da auditoria.
**Recomendação mínima:** garantir a liberação do bot mesmo quando a atribuição falhar, e degradar o destino para any com evento/nota de fallback. O roteamento não deve impedir bot_handoff!.

### P1 de gate / P2 de produto não confirmado — saída de recusa sem registro

**Gatilho:** o modelo, em Testar/copilot sandbox, chama especialista ou ferramenta assíncrona/não permitida; Answerer#skip_test_tool gera Tools::Recusa.para_modelo.

**Efeito observado na bateria:** o scanner de recusas encontra answerer.rb#skip_test_tool#1, mas recusa_registro_spec.rb não possui gatilho para esse ID. A suíte termina com 2344 examples, 1 failure, 3 pending; portanto o contrato de cobertura não fecha e o gate não pode ser considerado verde.

**Evidência confirmada:**

- .codex/preview/global-audit-20261009/ruby-global79.log:515-534 registra a falha em spec/services/autonomia/agents/tools/recusa_registro_spec.rb[1:2], com a mensagem saída nova sem gatilho ... answerer.rb#skip_test_tool#1.
- app/services/autonomia/agents/answerer.rb:424-434 registra a saída dinâmica em skip_test_tool; os ramos de especialista, async e escrita de viewer passam por ele em :409-415.
- spec/support/varredura_de_recusas.rb:78-104 varre chamadas de Recusa.para_modelo e spec/services/autonomia/agents/tools/recusa_registro_spec.rb:584-588 exige uma entrada de gatilho para cada saída.
- O mapa já cobre dispatch_tool_call#1 e run_specialist#1, mas não skip_test_tool#1.
- O resultado informa três pendências de evals pagos, explicitamente desativados; elas não são falhas de produto.

**Baseline:** o resultado foi executado sobre o snapshot global79 com conteúdo backend correspondente ao source80; proof-inputs-gestao80.log confirma igualdade de inputs backend/spec AST entre os snapshots de gestão 79 e 80. A cópia source80/current contém as mesmas linhas. Isso caracteriza falha preexistente do baseline de validação, sem prova de regressão nova contra produção.

**Recomendação mínima:** adicionar ao contrato de registro um gatilho determinístico para cada ramo de skip_test_tool (ou consolidar o produtor em saída já registrada), preservando o ID/código e sem relaxar o scanner. Até isso, marcar a bateria como falha de gate.

### P2 potencial — exceções inesperadas de retrieval são convertidas em base vazia no caminho gateado

**Gatilho:** Retriever#retrieve levanta uma exceção diferente de Autonomia::Agents::Retriever::RetrievalError no Testar/copilot, como uma falha de banco ou outro erro de infraestrutura.

**Efeito:** Answerer#retrieve_snippets captura StandardError em app/services/autonomia/agents/answerer.rb:278-293 e retorna [] também quando trust_instruction é falso. Assim o answer não chega ao safe_handoff('retrieval_unavailable') reservado para RetrievalError; o modelo pode ser chamado com a base vazia. O efeito final depende da resposta do modelo e não foi reproduzido.

**Classificação:** P2 potencial, confirmado no fluxo estático; impacto runtime é hipótese condicionada ao tipo de exceção e à resposta gerada.
**Recomendação mínima:** no caminho gateado, deixar somente os erros explicitamente recuperáveis degradarem para vazio; propagar falhas de infraestrutura para o handoff seguro já implementado.

## Cobertura específica da lane

- **Answerer e ferramentas:** o modo Testar marca skipped_tools, recusa especialistas/async e bloqueia escrita de viewer; a cobertura estática dessas saídas é o achado de gate acima. Não há prova de execução externa no Testar.
- **Prompt:** PromptBuilder separa superfície externa, copilot e teste para greeting/fallback/handoff; não encontrei exposição de prompt ou scaffold nos resultados lidos.
- **Retriever:** projeção material usa fontes aprovadas e trata o salvage out-of-business; a lacuna relevante é o rescue amplo de StandardError descrito acima.
- **Handoff:** destino inválido retorna any e é logado; o risco está na exceção durante destino válido antes da liberação do bot.
- **Jobs/IA nativa/copilot:** o Playground limita cotação a uma rodada e ao TTL de InteractiveRequest menos ResponsesClient::REQUEST_TIMEOUT; copilot interno segue surface: :copilot e não conecta inbox de cliente.
- **Cotação:** Builder.rodadas_do_turno mantém seis rodadas somente no atendimento real de cotação; o caminho Testar limita a uma. Agent expõe config['voice'] por store_accessor, portanto a nota de passagem não tem o problema de método ausente inicialmente considerado.

## Lacunas e validação

- Não foram executados testes novos, nem chamadas de produção, banco, deploy ou provedores pagos.
- A segunda bateria (papéis/shared roles/SuperAdmin/status/auto-assignment) ficou sem execução porque o planner bloqueou o snapshot por local-project-not-clean; os artefatos compartilhados existem no M2, mas não foram forçados.
- Houve falha de transporte no MCP de filesystem (HTTP request failed no endpoint local); a leitura foi recuperada pelo terminal local autorizado. A falha fatal de permissão de aplicação não se repetiu depois dessa recuperação.
- Não foram usados prompts completos, dados de clientes, secrets ou credenciais.

**Parecer da lane 08:** há um bloqueio de gate confirmado no registro de recusas e um P1 potencial de handoff condicionado a exceção de atribuição. O redesign não deve ser tratado como livre de regressão runtime até que esses dois pontos tenham, respectivamente, o contrato registrado e o fallback de liberação protegido.
