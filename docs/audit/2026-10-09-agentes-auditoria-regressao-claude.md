# Auditoria de regressão do working tree do redesign de Agentes — 09/10/2026

Auditoria independente (Claude Code) do working tree não commitado da worktree `agentes-ia-prd` (HEAD `532a5b7beb`, 146 commits atrás de `origin/main`). Orquestração com 13 agentes: 6 lentes só de leitura, 1 executor de testes e 6 verificadores adversariais. Nada foi editado, commitado ou enviado para produção.

## Veredito

**Não pode subir.** Há 1 P0 e vários P1 confirmados. Todos afetam contas **sem** o redesign ligado.

Causa-raiz comum: o `RedesignGate` existe só no frontend (rotas, Sidebar, páginas de entrada) e no `_account.json.jbuilder:38`. Nenhum controller, service ou job do backend consulta o gate. A alegação do relatório do Codex, "sem alterações de runtime do atendimento", é **falsa**. Desligar a flag no super admin não devolve o comportamento de `origin/main`.

## Testes executados (os que o Codex não rodou)

| Bateria | Resultado |
|---|---|
| RSpec dos 67 specs novos ou modificados | 677 exemplos, **4 falhas** (`external_agent_lifecycle_spec` :92 :106 :123 :299) |
| RSpec de regressão do runtime (autonomia, crm/ai, super_admin, enterprise) | 5231 exemplos, **6 falhas** (as 4 acima + `insurance/receita/sem_regex_spec` :142 :153), 74 pendentes |
| RSpec complementar fora de autonomia (waha, ai_requests, auto_assignment, audit_logs) | 1087 exemplos, 0 falhas |
| Vitest de `app/javascript` inteiro | 8714 testes, **8 falhas** em 2 arquivos que passam na base: `FieldConfigurator.spec.js` (bisseção: `Dialog.vue:121`) e `AudiencesPage.spec.js` (SidePanel com Teleport) |
| Build Vite de produção | OK, sem import órfão |
| ESLint (173 arquivos) | 0 erros |
| RuboCop (154 arquivos) | **23 ofensas**, CI de lint vermelha |
| i18n do fork, `guia:check`, `formatos:check` | OK (na base desatualizada) |

As falhas foram classificadas como introduzidas pelo diff. O RSpec rodou num banco de teste isolado, `chatwoot_test_agentesprd` (127.0.0.1:55432), que pode ser apagado.

## Achados confirmados (após verificação adversarial)

### P0
- **Salvar no PanelTune legado quebra para todo agente manual, ativo e ligado** (422). `activation_contract.rb:4-36` + `agents_controller.rb:8`, sem gate. Saudação, fallback, tom, atuação, handoff, público e horário deixam de salvar.

### P1: atendimento em produção, todas as contas
1. **O prompt ao vivo volta a mandar copiar a `fallback_message`.** Isso reverte a correção `373bf51396` de junho. `prompt_builder.rb:275-285`.
2. **A saudação e a `handoff_strategy` ("Nunca" / "sempre perguntar") entram no prompt ao vivo.** Antes, nenhum service lia `handoff_strategy`. Contas que marcaram "Nunca" no painel antigo, sem efeito até hoje, passam a não encaminhar. `prompt_builder.rb:258-306`.
3. **Toda passagem para humano cria uma nota privada nova.** Dispara `message_created` (webhooks, n8n, automações, relatórios). `responder.rb:142-154`, `nota_do_encaminhamento.rb`.
4. **"Ajustar com IA" em agente guiado descarta em silêncio** nome, saudação, tom, voz e perguntas, e mesmo assim grava `applied=true`. `builder_attributes.rb:5-10`, `builder.rb:1440`.
5. **O histórico de instruções já gravado vira não restaurável** (metadata `{}` nas linhas atuais), e a volta de manual para guiado dá 422 ou restaura uma versão guiada antiga sem aviso. `instruction_versioning.rb:42`, `instruction_contract.rb:29`.
6. **O fechamento do Construtor passa a ser decidido pelo schema `knows`.** Pula o portão de materiais e regride o loop do T13. `builder.rb:1187-1273`.
7. **Gate só no front** (causa-raiz, ver acima).

### P2 (selecionados)
- O `HandoffRouter` roda dentro do `with_lock`, antes do `bot_handoff!`. Com membro ou equipe configurados, uma falha desfaz o handoff e a conversa fica presa com a IA. `responder.rb:173-184`.
- O Copiloto da conversa passa a exigir `CRM_AI_ENABLED`. Se essa variável estiver desligada em produção, o botão aparece e a API responde 404. `copilot_availability.rb:15`.
- O config público virou allowlist de 8 chaves: PATCH com chaves operacionais recebe 422, e internal/both passa a exigir o copiloto. `config_contract.rb:41`, `request_validation.rb`.
- O Testar (inclusive o legado) grava `agent.config` com lock e `save!` a cada mensagem. Usuário só-ver passa a escrever no registro, e dado legado inválido gera 500. `defer_interactive_ai.rb:16`, `agent_state_store.rb:189`.
- O Testar passa a rodar com `test_mode` e `trust_instruction`, pulando especialistas e ferramentas assíncronas. A Lia deixa de cotar no teste. `playground.rb:17-37`.
- O retriever do atendimento ao vivo passa a decidir pela `MaterialProjection`, sem equivalência comprovada. `retriever.rb:102`.
- O index e o show passam pela `ListProjection`; qualquer exceção derruba a lista e o painel (500). O painel legado refaz o fetch a cada troca de aba e redireciona para a lista em qualquer falha. `AgentPanelPage.vue:199-235`.
- Abrir o Construtor cria um agente "Novo agente" (string sem i18n), e o reaper deixa de apagar rascunhos com mensagem: sobra lixo na lista. `build_thread.rb:100`, `reap_stale_drafts_job.rb`.
- Renomear o agente renomeia o AgentBot espelho e pode apagar o avatar do bot (`purge`). `agent.rb:141`, `mirror_identity_sync.rb`.
- A lista de FAQ passou a exigir `autonomia_manage` (antes bastava `view`). O resume e o show do build thread também exigem manage. `faq_suggestion_policy.rb:5`, `build_threads_controller.rb:83`.
- O drilldown "respostas erradas" mudou de formato e quebra o card legado (chave Vue duplicada). `analytics_controller.rb:46`.
- As escolhas do Agente de Cotação ficaram editáveis só com `autonomia_manage`, sem `insurance_manage`. `quote_choices_controller.rb:7`.
- UI compartilhada sem gate:
  - `Dialog.vue` (quebra o `FieldConfigurator`);
  - `SidePanel.vue` (a trava de Tab quebra os dropdowns de Automações; Campanhas → Público com spec vermelho);
  - Logs de auditoria (filtros "Agente" e "Operação" para todas as contas).
- Guia: o `porques.md` descreve telas novas para contas que não as veem. O `formatos-das-acoes.json` foi regerado sobre base velha e com `modelo: AgentBot` errado (inclui waha). Conflito certo com a main nos arquivos gerados.
- Specs desatualizados: `external_agent_lifecycle_spec` (contrato mudou sem gate) e `sem_regex_spec` (lista de exceções R18 não atualizada; mudar a lista exige OK do Rodrigo).
- `PanelTune.vue:48` lê `autonomia_agents_redesign`, mas o backend emite `..._enabled`: o caminho novo de resume nunca roda (o spec mocka a chave errada).

### P3 / fora de escopo
- `auto_assignment/agent_assignment_service.rb:60` (core do Chatwoot) foi tocado sem necessidade; o comportamento é equivalente.
- `waha_inboxes_controller.rb` mudou a mensagem de erro de provisionamento.
- O resume é um GET que escreve (`force_close: false`).

## O que está OK
- Não há migration; o estado novo fica em jsonb existente (`agent.config`, `instruction_versions.metadata`, `account.internal_attributes`).
- O gate tem default desligado (variável `AUTONOMIA_AGENTS_REDESIGN` + chave na conta).
- O isolamento entre contas nos endpoints novos está correto (escopo por conta).
- Os arquivos removidos (`localeTag.js`, `useModalFocus.js`) tiveram os 22 imports migrados; o build passa.
- Nenhum `<select>` nativo foi introduzido.

## Recomendação

1. **Não subir este working tree como bloco.** Commitar só em uma branch de resgate (sem PR) para preservar o trabalho.
2. **Gate no backend primeiro.** Todo before_action, contrato e bloco de prompt novo deve consultar `RedesignGate` (ou o próprio agente/conta) antes de mudar comportamento. Sem isso, contas sem redesign nunca ficam iguais a `origin/main`.
3. **Separar em PRs a partir de `origin/main` atualizado**, nesta ordem:
   - (a) refactors puros sem mudança de comportamento (helper `localeTag`, composable `useModalFocus`), com os specs atuais verdes;
   - (b) backend de Agentes atrás do gate, com RSpec;
   - (c) runtime do atendimento (prompt, nota, HandoffRouter, retriever) em PR próprio, com decisão explícita do Rodrigo por mudança e teste do tester de produção;
   - (d) frontend novo atrás do gate;
   - (e) mudanças em UI compartilhada (Dialog, SidePanel, audit logs) só com spec e conferência visual;
   - (f) Guia regerado sobre a main, por último.
4. **Decisões de produto pendentes** para o Rodrigo: a nota privada em todo handoff, `handoff_strategy='never'` passar a valer, a saudação no prompt ao vivo e a allowlist de config.

Evidência bruta: resultado do workflow `wf_68a4ec3d-15f` e logs do executor no scratchpad da sessão (`a_out.txt` … `f_out.txt`).
