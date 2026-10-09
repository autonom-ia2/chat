# Revisão final — desenho B3/BE-05

**Alvo:** `docs/agentes-ia-redesign/design/B3.md`  
**SHA-256 do alvo:** `6cb1a38fd27e6cc79f232317967c4ba5250e3eb336fdfd6c7aab8e35ecd0c486`  
**Fontes:** PRD, `docs/audit/2026-10-07-agentes-b3-mapeamento.md`,
`revisoes/B3-desenho-normal-integracao.md` e o código aberto citado no desenho.

## Resultado

**PASS final — não encontrei erro residual concreto nos contratos revisados.**

Esta foi uma revisão somente documental e estática. Não executei testes, banco, navegador, serviços ou
produção, e não alterei o desenho B3 nem código de produto. O documento continua DRAFT e o resultado não
autoriza implementação, merge, fila, deploy ou produção.

## Conferências

- **E1/E2 versus D22:** o desenho não usa a presença de `agent_id` para inferir ajuste. Ele conserva o
  rascunho já vinculado como criação enquanto `instruction` estiver ausente e permite o schema completo,
  incluindo nome, voz e apresentação. Quando a instrução já existe, inclusive no caminho top-level legado,
  aplica somente `instruction`, `human_card`, `scaffold`, `handoff_rule` e `config.guardrails`; voz, nome,
  atuação, fallback, perguntas, canais e demais configuração permanecem protegidos. Isso corresponde ao
  D22 e ao ciclo E1–E4 do PRD.

- **Autoridade da escrita:** o filtro antecipado do Builder está corretamente subordinado ao
  `Agent#apply_builder_config!`. O desenho exige `Agent.with_lock`, releitura do agente, localização do
  token/thread e nova avaliação de `instruction.present?` antes de escolher criação completa ou allowlist.
  Assim, uma corrida entre o primeiro fechamento e um ajuste posterior não transforma o writer em autoridade
  do navegador ou do Builder.

- **Modo manual e corrida:** há duas portas distintas e necessárias: recusa no controller/fetch antes de
  append, modelo e enqueue quando o agente já é manual; e recusa dentro do mesmo lock autoritativo antes de
  `apply_builder_attributes!` quando a troca para manual ocorre depois do enqueue. O desenho também mantém a
  recusa `InstrucaoMantida` para a Lia, sem expor instrução privada. O caso de corrida está descrito com
  preservação da instrução manual e código estável.

- **Leitor e reset:** a busca combina conta e agente resolvido, escolhe `id DESC` e não usa `updated_at`.
  O reset altera somente `state.force_close`, é idempotente e usa a ordem Agent → BuildThread. Não cria
  thread, não inicia job, não troca token/status e não limpa mensagens ou materiais. Essa mutação no GET é
  exigida pelo contrato BE-05, portanto não é um achado.

- **Escopo, permissões e privacidade:** `autonomia_manage` vem antes da leitura, viewer recebe 401, agente
  arquivado, de sistema, inexistente, cross-account ou sem thread não confirma dados e retorna 404. A Lia
  mantém `instrucao_mantida`. O envelope reutilizado filtra `instruction`, `scaffold`, `draft_config`,
  tokens e configuração privada; mensagens só aparecem atrás do guard de edição.

- **Store e jornada:** `resume(agentId)` hidrata pelo GET nested, aplica a thread real e só inicia polling
  para `processing`. O primeiro envio usa o mesmo id e não chama `create`/`start`; erros 401/404/422 não
  fabricam conversa. O fluxo antigo permanece preservado com a flag desligada, e o desenho registra a
  regeneração do Guia após rota/controller/GET.

## Limite do resultado

A ausência atual da rota nested e da ação de `resume` é a lacuna de implementação declarada pelo próprio
B3, não um defeito residual do desenho. A implementação ainda precisa provar os casos RED/GREEN descritos,
inclusive isolamento, manual/Lia, E1/E2, allowlist D22, reset e zero criação no reload.
