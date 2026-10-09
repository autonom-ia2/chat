# Checagem limitada B1 — contratos TEC-02 e TEC-03

Checagem somente leitura sobre o fingerprint congelado de 53 arquivos (`04baa47e5200089e89a17e322769890cc9263aab44f1870bd762c4b35f298738`), comparado ao baseline `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. O escopo foi limitado às duas correções solicitadas: saída operacional da Lia e atomicidade entre o PATCH público e a porta operacional. Não revisei `handoff_target_type` nem reabri a revisão normal. Não executei produto, specs, build, banco, navegador ou produção.

## B1-TEC-02 — saída operacional da Lia: PASS

`ConfigContract::OPERATIONAL_KEYS` continua contendo `native_tool_slugs` para agentes comuns (`app/services/autonomia/agents/config_contract.rb:7-11`), e a validação continua recusando essa chave quando `agent.instrucao_mantida?` (`app/services/autonomia/agents/config_contract.rb:73-79`). Portanto, a correção não removeu a capacidade operacional dos agentes que podem receber a configuração.

Na resposta da action, `render_agent_operation_config` parte da lista fechada e cria uma lista local sem `native_tool_slugs` quando o agente é Lia (`app/controllers/concerns/super_admin/accounts_agent_operation_config.rb:37-43`). A expressão `keys -= [...]` produz uma nova lista; não altera a constante congelada. O valor mantido pelo Builder permanece no `config` e a resposta só fatia as chaves que podem ser oferecidas. A action é realmente usada pelo `SuperAdmin::AccountsController`, que inclui a concern (`app/controllers/super_admin/accounts_controller.rb:1-3`), e não encontrei override Enterprise desse caminho.

Há prova de contrato no request spec: a Lia recebe uma configuração operacional válida, a resposta contém `voice_reply`, não contém `native_tool_slugs` e o valor mantido continua no banco (`spec/requests/super_admin/autonomia_agent_operation_spec.rb:358-370`). A recusa de escrita continua coberta (`spec/requests/super_admin/autonomia_agent_operation_spec.rb:345-356`). Não há vazamento residual nesse caminho.

## B1-TEC-03 — PATCH público e operação sob o mesmo lock: PASS

O `update` público agora abre `@agent.with_lock` antes de executar as guardas de Lia, descartar instrução gerada, montar os parâmetros, mesclar o `config`, validar canais e salvar (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:44-59`). Como o objeto foi recarregado pelo lock antes do bloco, `merge_config!` lê o `config` atual e mescla somente as chaves públicas recebidas (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:210-215`). As guardas manuais e de agente interno continuam antes do `save!` e dentro da mesma transação; o registro de versão posterior grava apenas a associação de histórico (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:111-123`, `app/models/autonomia/agents/agent.rb:370-376`).

A porta operacional usa o mesmo domínio de lock: `OperationConfig#perform!` revalida dentro de `@agent.with_lock`, faz o merge sobre o blob atual, salva e cria o AuditLog na transação (`app/services/autonomia/agents/operation_config.rb:18-48`). Assim, o read-modify-write público e a escrita operacional são serializados pelo mesmo registro do agente, preservando ambos os campos.

O spec de regressão intercalada força a leitura pública do agente, executa depois uma operação operacional auditada em outra instância e só então deixa o PATCH continuar. Ele confirma `voice_reply`, a chave pública e o AuditLog depois da requisição (`spec/requests/api/v1/accounts/autonomia/agents/config_contract_spec.rb:110-131`). As jornadas de Lia continuam cobrindo recusa de modo manual, instrução e troca de tipo antes de qualquer escrita (`spec/requests/api/v1/accounts/autonomia/journeys/external_agent_lifecycle_spec.rb:237-335`). Não encontrei bypass de merge/save fora do lock no endpoint público revisado.

## Evidência e limite

A prova informada do snapshot 10 (`180` exemplos Ruby sem falhas e `43` exemplos JS sem falhas) não é tratada aqui como aprovação da bateria ampla nem do B1 inteiro. Esta checagem é estática e limitada aos dois contratos acima; a validação ampla e a revisão final permanecem gates separados.

## Conclusão

**PASS limitado — B1-TEC-02 e B1-TEC-03 fechados, sem erro residual encontrado.** Nenhuma correção adicional é indicada nesta checagem.
