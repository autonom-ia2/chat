# Revisão normal independente — B1 contratos BE-19/BE-31 e auditoria

Revisão feita sobre o fingerprint congelado de 47 arquivos (`7aaa8c39a9a8a0980fed0c838f9492964664e1192b8ce546efd8d1962c71e119`), com comparação ao baseline `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. Não executei produto, specs, build, banco, navegador ou produção e não alterei código.

## Achados

### B1-TEC-01 — média — `handoff_target_type` é aceito e salvo, mas desaparece no leitor do agente

**Prova:** `Autonomia::Agents::ConfigContract::PUBLIC_KEYS` aceita `handoff_target_type` (`app/services/autonomia/agents/config_contract.rb:2-5`) e o PRD exige que a chave entre no slice de `_agent.json.jbuilder` (`docs/agentes-ia-redesign/PRD.md:519,532`). O serializer atual só devolve `handoff_strategy`, `handoff_target_id` e as demais chaves (`app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder:16-26`); `handoff_target_type` não está no slice. O spec de exposição repete a omissão e, portanto, não a detecta (`spec/requests/api/v1/accounts/autonomia/agent_config_exposure_spec.rb:43-46`).

**Causa:** o contrato de escrita foi fechado sem alinhar o allowlist do leitor legado. A chave pode passar pelo create/PATCH, mas não retorna no GET do agente.

**Efeito:** depois de salvar `member`/`team`/`any`, a tela não consegue reconstruir a escolha após reload e pode exibir o padrão ou sobrescrever a configuração; o traçado BE-19 → leitor do handoff fica incompleto.

**Correção mínima:** incluir `handoff_target_type` no slice do `_agent.json.jbuilder` e no spec de exposição. Não abrir o serializer para outras chaves.

### B1-TEC-02 — média — a resposta da porta operacional oferece `native_tool_slugs` para a Lia

**Prova:** o PRD e o desenho determinam que `native_tool_slugs` não é oferecida no Agente de Cotação e que a lista válida é a do deploy (`docs/agentes-ia-redesign/PRD.md:544`; `docs/agentes-ia-redesign/design/B1.md:272-274`). O Builder grava essa lista no `config` da Lia (`app/services/autonomia/insurance/quote_agent/builder.rb:371-376`). A validação bloqueia apenas a escrita (`app/services/autonomia/agents/config_contract.rb:73-79`), mas uma alteração válida de qualquer outra chave retorna todas as chaves operacionais sem exceção (`app/controllers/concerns/super_admin/accounts_agent_operation_config.rb:37-41`). Assim, o mesmo PATCH da Lia devolve `operation_config.native_tool_slugs` e um cliente genérico pode tratá-la como uma opção da tela.

**Causa:** o fechamento foi aplicado ao input, mas não ao payload de saída da action.

**Efeito:** a lista de ferramentas mantida pelo deploy é exposta e o contrato F7 apresenta como configurável um campo que deve permanecer fora da oferta da Lia; a recusa da escrita não impede essa exposição.

**Correção mínima:** ao serializar a resposta para `agent.instrucao_mantida?`, retirar `native_tool_slugs` do `operation_config` (ou devolver um estado explicitamente indisponível, sem o valor). Manter a recusa antes do lock e sem auditoria.

### B1-TEC-03 — alta — PATCH público pode apagar uma alteração operacional concorrente

**Prova:** o PATCH público lê o blob inteiro, faz o merge e salva sem lock (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb:44-55,207-213`). A nova porta operacional lê o blob dentro de `with_lock` e grava a configuração completa (`app/services/autonomia/agents/operation_config.rb:18-48`). Não há `lock_version` no schema/modelo do agente (`app/models/autonomia/agents/agent.rb:3-24,41-44`). Sequência possível: (1) PATCH público lê `config` sem a chave `voice_reply`; (2) SuperAdmin grava `voice_reply` e a auditoria, dentro do lock; (3) o PATCH público salva seu snapshot mesclado e apaga `voice_reply`. O inverso também pode perder a alteração pública.

**Causa:** o lock protege apenas concorrentes que entram em `OperationConfig`; o merge legado do endpoint público continua sendo um read-modify-write fora do mesmo lock/transação.

**Efeito:** uma mudança BE-31 pode desaparecer sem erro, embora exista linha no `AuditLog` dizendo que ela foi aplicada; também podem ser apagadas chaves públicas ou calculadas alteradas entre a leitura e o save.

**Correção mínima:** fazer a leitura/merge/save do PATCH de agente sob o mesmo `@agent.with_lock` (recarregando o agente dentro do lock), ou usar uma escrita JSONB atômica que preserve as chaves concorrentes. O spec deve intercalar os dois caminhos e reler config/auditoria.

## Conclusão

**B1 não está aprovado nesta rodada.** Os três achados são concretos: um leitor público incompleto, uma saída operacional que viola a exceção da Lia e uma corrida de escrita que pode apagar configuração auditada. Nos caminhos não afetados por esses pontos, a revisão confirmou a validação bruta antes de strong params, tipos sem coerção, escopo por conta, exclusão de sistema/Lia antes da escrita, `with_lock` transacional, presença old/new, máscaras, ator SuperAdmin e filtros de auditoria por conta/agente/chave. Nenhuma correção, teste, commit, push, merge, fila, deploy ou produção foi executado.
