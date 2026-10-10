### R2-01 [alta] §4 D12 / §7 BE-25 / §11.4 CA-RES-04
**Problema:** A regra de BE-25 ("caixas de que o usuário é membro") é mais fraca que a regra que o próprio repositório já usa para ver conversas. Hoje, uma função personalizada sem nenhuma permissão `conversation_*` não vê conversa nenhuma. Com o filtro do PRD, ela passaria a ver as conversas das caixas de que é membro. O CA-RES-04 transforma esse comportamento mais fraco em teste, e a regra também esquece o acesso por time.
**Evidência:** enterprise/app/services/enterprise/conversations/permission_filter_service.rb:2-30 (custom role → só `conversation_manage`/`unassigned`/`participating`; sem nenhuma → `Conversation.none`); app/services/conversations/permission_filter_service.rb:11-23; app/policies/conversation_policy.rb:10-36 (inbox_access? || team_access?). PRD L72, L298, L621-622, L777 (T06).
**Correção:** BE-25: filtrar `outcome_scope` com `Conversations::PermissionFilterService.new(scope, Current.user, Current.account).perform`, que já tem a extensão do EE. Reescrever CA-RES-04 e T06: uma função só com `autonomia_view`, sem `conversation_*`, recebe lista vazia; com `conversation_participating_manage`, recebe só as suas. O total do resultado continua sendo o número agregado.

### R2-02 [alta] §7 BE-23 / §11.4 CA-AJU-03, CA-AJU-10 / §9 NR-10
**Problema:** BE-23 passa a gravar versões com o texto guiado, que é IP oculto do Construtor (`before_manual`, `builder`, além do `kb_refresh` que já existe). O índice de versões mostra o texto de todas as versões quando o agente está em modo manual hoje. Então, ao clicar "Escrever as instruções eu mesmo", o dono vê, e pode restaurar no campo manual, exatamente a instrução que o controller apaga de propósito para não vazar. Isso contradiz NR-10 e o próprio motivo do `before_manual`.
**Evidência:** app/views/api/v1/accounts/autonomia/agents/instruction_versions/_instruction_version.json.jbuilder (`json.instruction instruction_version.instruction if @agent.manual?` — decide pelo modo ATUAL do agente, não pelo da versão); agents_controller.rb:142-149 ("nunca vazamos a instrução do Construtor"); knowledge/instruction_refresher.rb:127 (versão kb_refresh de agente guiado); agent.rb:285-297 (restore copia version.instruction para a coluna). PRD L296, L663, L677.
**Correção:** Em BE-23: o texto só sai para versões cujo `reason` é de autoria do usuário (`manual_edit` e `rollback` de versão manual). `before_manual`, `builder` e `kb_refresh` mostram só metadados. Restaurar uma versão guiada com o agente em manual volta para `mode=guided`, ou é recusado com `code`. Spec R: guiado → manual não expõe o texto de nenhuma versão guiada.

### R2-03 [media] §7 BE-19 / §9 NR-05
**Problema:** O PRD diz que a mudança no spec de ciclo de vida é só "trocar `temperature` por `response_window`". Mas os dois exemplos dessas linhas mandam, no mesmo PATCH, chaves protegidas (`with_knowledge` e `agente_de_cotacao`) e esperam sucesso. Com BE-19 (protegida → 422), a requisição inteira passa a ser recusada. O que esses specs afirmam muda de "preserva" para "recusa", não é uma troca de chave.
**Evidência:** spec/requests/api/v1/accounts/autonomia/journeys/external_agent_lifecycle_spec.rb:178-187 (`config: { temperature: 0.7, with_knowledge: true }` → `have_http_status(:success)`), :200-208 (`chave => {...}, 'temperature' => 0.7` → success); agents_controller.rb:191 (hoje `except(*PROTECTED_CONFIG_KEYS)` descarta em silêncio). PRD L292, L368.
**Correção:** Em BE-19 e NR-05, declarar a mudança real: os dois exemplos passam a esperar 422 `config_key_not_allowed` com `key` (`with_knowledge` / `agente_de_cotacao`) e o `config` relido igual ao de antes. Um terceiro exemplo prova que `response_window` sozinho mescla e preserva as computadas.

### R2-04 [media] §7 BE-19 / §11.7 Q12 / regras de produção
**Problema:** BE-19 fecha, também para SuperAdmin, o único caminho por API para ajustes de operação por agente que o código lê ao vivo: `voice_reply`, `voice_instructions` ("tunar sem redeploy"), `humanize_delivery`, `operate_media`, `operate_reactions`, `test_allowlist_phones` e o rollout de `native_tool_slugs` (como o `consultar_condicoes_gerais`, que a auditoria diz exigir rollout). O PRD não põe nada no lugar. Com `rails runner` proibido, o único caminho que sobra é UPDATE de jsonb por psql em produção.
**Evidência:** app/services/autonomia/agents/config.rb:232-316 (overrides por agente lidos de `agent.config`); operate.rb:53-59 (`test_allowlist_phones`); agents_controller.rb:161,190-193 (hoje aceita e mescla); docs/audit/2026-09-12-entrega-9-duvidas-de-cobertura.md:225-227 (rollout de `native_tool_slugs` necessário). PRD L292, L752.
**Correção:** Acrescentar a BE-19 um caminho controlado para essas chaves: ação no Super Admin (`SuperAdmin::AccountsController` ou uma tela do agente) com a lista dessas chaves, auditoria e spec. Ou registrar como decisão nova da §4 que esses ajustes passam a ser feitos só por psql com 🟢 e foto, com o comando no runbook.

### R2-05 [media] §7 BE-19 / §11.7 Q12 / §14
**Problema:** A volta e o aborto não cobrem a limpeza da Q12. A §14 diz que nas mudanças de caminho ao vivo (incluindo BE-19) "nenhum dado migrado precisa voltar", mas BE-19 e Q12 preveem apagar chaves de `config` em produção (com 🟢 e foto). Pior: o aborto da §11.7 dispara quando "Q12/Q13 diferentes da foto", e a limpeza aprovada torna a Q12 diferente por definição. Além disso, a Q12 só procura 4 das chaves que BE-19 fecha e deixa de fora `humanize_delivery`, `operate_media`, `operate_reactions` e `voice_instructions`, que também mudam o comportamento ao vivo.
**Evidência:** PRD L292 ("limpar só com 🟢 e foto"), L752 (Q12 com 4 chaves), L756 (aborto se Q12 ≠ foto), L852-853 (§14). Código: config.rb:239,261,275,316 (chaves ausentes da Q12 lidas ao vivo).
**Correção:** Q12 cobrir todas as chaves que BE-19 fecha e que o runtime lê. §14 ganhar a volta da limpeza (UPDATE `config = config || <foto>` por agente, só com 🟢). O aborto passa a comparar a Q12 com a foto depois da limpeza aprovada, não com a de antes.

### R2-06 [media] §4 D12 / §7 BE-25 / §6.3 O que sabe
**Problema:** O mesmo tipo de exposição que D12 corrige continua aberto em `GET faq_suggestions`. Com só `autonomia_view`, a pessoa recebe pergunta e resposta tiradas de conversas reais de qualquer caixa da conta, com `conversation_id`/`display_id` e `source_message_ids`. BE-25 só trata `analytics/conversations`. Esconder a aba "O que sabe" de quem só vê não fecha a API.
**Evidência:** app/policies/autonomia/agents/faq_suggestion_policy.rb:4-6 (`index?` = autonomia_view); faq_suggestions_controller.rb:9-16 (sem filtro por caixa); views/.../faq_suggestions/_faq_suggestion.json.jbuilder (question, answer, conversation_display_id, source_message_ids). PRD L72, L178, L195, L298.
**Correção:** Incluir no B1 (BE-25 ou BE-25b): `faq_suggestions#index` exige `autonomia_manage` (só a aba de quem edita usa), ou filtra pelas conversas visíveis por `Conversations::PermissionFilterService`. Spec R com função só `autonomia_view`.

### R2-07 [media] §11.8 Tester (T06, T15, T16, T23)
**Problema:** T15 (PATCH e DELETE com quem só vê) e T16 (PATCH `config.native_tool_slugs`) não dizem em qual agente rodam e não têm 🟢. A regra da própria seção é "escrita só em agente de teste". Se a regressão que o teste procura existir, T15 apaga e T16 liga ferramenta nativa num agente no ar (Clara/Lia). Além disso, T06, T15 e T23 precisam de usuário só-ver e de função personalizada na conta 16. Criar isso é escrita de permissões em produção, e o PRD não lista como pré-requisito (como faz com a caixa de teste de T17/T18/T21).
**Evidência:** PRD L763-767 (regras e pré-requisitos só para T17/T18/T21), L777 (T06), L786 (T15 sem alvo), L787 (T16 sem alvo, sem 🟢), L794 (T23 "usuário só-ver da conta 16").
**Correção:** T15/T16 sempre no agente de teste criado para isso, marcados [🟢]. Acrescentar pré-requisito: usuário só-ver e função personalizada "só ver agentes" na conta 16, criados com 🟢 e apagados no fim. Sem eles, T06/T15/T23 ficam BLOQUEADOS.

### R2-08 [media] §6.3 (aviso da Cotação, Ajustes) / §7 BE-17 / §11.4 CA-AJU-12
**Problema:** O "horário" da Lia está em dois lugares, e eles não se encaixam. BE-17 aceita `business_hours`, que vira a escolha `horario` colada no texto da Lia (`$horarioAtendimento`), e o aviso promete "Você escolhe nome, horário, jeito de cotar". Mas a lista de Ajustes da Lia só tem "Quando atende — 3 opções" (`config.response_window`, que só abre e fecha a porta), sem campo que grave `horario`. Ou o aviso promete o que a tela não faz, ou "Quando atende" grava uma coisa e a Lia diz outra ao cliente.
**Evidência:** app/services/autonomia/insurance/quote_agent/builder.rb:292-293 (`'$horarioAtendimento' => 'horario'`), :306-311 (horario com padrão); PRD L174-175 (aviso), L218 (Ajustes da Lia), L290 (BE-17 `business_hours?`), L681-683 (CA-AJU-12 sem horário do texto).
**Correção:** Decidir e escrever: (a) Ajustes da Lia ganha o campo "Horário que ela informa ao cliente" → `quote_choices.business_hours`, com spec de que o texto montado reflete a escolha; ou (b) tirar `business_hours` de BE-17 e "horário" do aviso. Nos dois casos, CA-AJU-12 deixa explícito o que "Quando atende" grava.

### R2-09 [baixa] §11.8 T09
**Problema:** T09 espera HTTP 200 do `POST test`, mas o endpoint é assíncrono e responde 202 com `poll_url`, como o próprio PRD diz em CA-TES-02 e T07. Do jeito que está, o tester reprovaria um comportamento correto, ou alguém afrouxaria a afirmação.
**Evidência:** app/controllers/concerns/defer_interactive_ai.rb:10 (`status: :accepted`); playground_controller.rb:14-16. PRD L573, L779 (T07 202), L780 (T09 "200").
**Correção:** T09: 202 + `poll_url`, resultado lido em `GET ai_requests/:id`, e o agente continua `draft`.

### R2-10 [baixa] §11.1 CA-GERAL-10 × §11.5 CA-CONVERSA-02
**Problema:** CA-GERAL-10 diz que o backend recusa com 401 toda escrita de quem só vê, exceto `test` e `suggest`. Mas `POST agents/message_reports` ("resposta errada") é aberto de propósito a qualquer membro da conta, inclusive a quem só vê agentes. Como está escrito, o critério reprovaria um comportamento intencional, ou levaria a fechar o endpoint e quebrar CA-CONVERSA-02.
**Evidência:** app/policies/autonomia/agents/message_report_policy.rb:5-7 (`account_user.present?`); message_reports_controller.rb:3-5,32-35 (não herda o Autonomia::BaseController; exige ver a conversa). PRD L474-476, L700-702.
**Correção:** Acrescentar `POST agents/message_reports` (e as leituras do copiloto dentro da conversa) às exceções de CA-GERAL-10, com a regra própria: qualquer membro que vê a conversa.

### R2-11 [alta] §11.8 T11, T15, T16 (regras do tester)
**Problema:** Três cenários do tester tentam escrever em agentes reais de produção, sem 🟢 e sem agente de teste. Isso contradiz a regra do próprio §11.8: "Escrita só em agente de teste [...] cada escrita em produção com 🟢". Se a guarda tiver regredido, a escrita acontece de verdade: T11 troca a instrução da Lia no ar, T15 apaga um agente (o alvo não é dito), T16 liga ferramenta nativa num agente real.
**Evidência:** PRD.md:763-764 (regra); PRD.md:782 T11 "PATCH instrução da Lia" sem [🟢]; PRD.md:786 T15 "Só-ver: PATCH e DELETE" sem alvo nem [🟢]; PRD.md:787 T16 "PATCH config.native_tool_slugs" sem [🟢]. Hoje a recusa depende só da guarda: base_controller.rb:33-35 (check_module_permission!) e agents_controller#destroy (origin/main:agents_controller.rb:58-60, destroy! direto).
**Correção:** Apontar T11, T15 e T16 para o agente de teste (para a Lia: uma cópia insurance_quote de teste ou só spec R) e marcar [🟢]. T15: dizer o id alvo e rodar primeiro o PATCH; o DELETE só roda se o PATCH devolver 401.

### R2-12 [alta] §7 BE-12 × CA-TES-03, CA-TES-04, T08, BE-24
**Problema:** Com BE-12 (trust_instruction), o motivo da passagem é o texto livre do modelo. O Playground não o reduz a um código, então não dá para mostrar "{motivo em pt-BR}", T08 ("reason da lista de CA-RES-07 ou nulo") falha por afirmação dura e CA-TES-04 ("o mesmo reason" no Playground e no Responder) compara texto cru com código curado. Só o EventLogger cura, e só para eventos. BE-12 não manda o Playground nem a nota do BE-24 curar o motivo.
**Evidência:** answerer.rb:147 `reason: parsed['handoff_reason'].presence` (caminho trust_instruction); prompt_builder.rb:21 `handoff_reason: { type: %w[string null] }` e :41 "motivo curto do handoff" (sem lista de códigos); event_logger.rb:79-94 curate_code → allowlist ou 'other'; playground/test.json.jbuilder repassa @result.handoff[:reason] cru. PRD.md:285, 577-578, 582, 779, 297.
**Correção:** No BE-12, exigir que o Playground (e a nota do BE-24) passem o motivo por `EventLogger.curate_code` antes de responder, com spec. Em CA-TES-04, comparar o motivo curado com o `handoff_reason` do evento gravado pelo Responder. T08 passa a aceitar só código da allowlist ou nulo.

### R2-13 [alta] §4 D15 / §7 BE-03, BE-08 × CA-LISTA-06/07, CA-LIG-12
**Problema:** Rascunhos que já existem (feitos antes do BE-08) não têm etapa gravada. Para eles, nenhum CA define o que a lista mostra em "Parou em ..." nem para onde "Continuar" leva. O pior: um rascunho "Pronto para ligar" antigo vai por "Escolher onde atende" direto para Ligue, e o `publish` devolve 422 `missing_test`. A tela não oferece caminho para o Teste, então esses agentes nunca ligam pela tela nova. Q7 confirma que esses rascunhos existem em produção.
**Evidência:** origin/main:reap_stale_drafts_job.rb:45-47 ("rascunho com instrução é agente PRONTO aguardando publicação" — o Construtor não muda o status); mockup screens-list.js:20 (ready → data-continue); PRD.md:281 (BE-08 só grava etapa nova), 276 (missing_test), 499-502, 604, 747 (Q7).
**Correção:** Definir no BE-08 o valor para thread sem etapa (ou agente sem thread): por exemplo, `ready` sem etapa leva ao Teste, não ao Ligue. Acrescentar a CA-LISTA-06/07 e a CA-LIG-12 um caso R/V com rascunho legado: o rascunho cai no Teste e o publish só passa depois de "Está bom, continuar".

### R2-14 [media] §9 NR-05 / §7 BE-19
**Problema:** A mudança prevista em external_agent_lifecycle_spec.rb:170-209 está descrita errada. Não basta trocar `temperature` por `response_window`. Os dois exemplos mandam chaves que o BE-19 passa a recusar com 422 (`with_knowledge` na linha 179, `agente_de_cotacao` na linha 201) e afirmam sucesso com descarte silencioso, exatamente o que o BE-19 proíbe ("nunca descarte silencioso"). Com a troca descrita, os dois continuam vermelhos.
**Evidência:** origin/main:spec/requests/api/v1/accounts/autonomia/journeys/external_agent_lifecycle_spec.rb:179 `config: { temperature: 0.7, with_knowledge: true }` + :183 `have_http_status(:success)`; :201 `config: { chave => {...}, 'temperature' => 0.7 }` + :205 success. PRD.md:292, 368.
**Correção:** No NR-05 e no BE-19: os dois exemplos passam a afirmar 422 `config_key_not_allowed` com a `key` (`with_knowledge` / `agente_de_cotacao`) e `config` relido igual. Separar num exemplo próprio o caso de chave permitida (`response_window`), com merge preservando as chaves protegidas.

### R2-15 [media] §11.8 T09
**Problema:** T09 espera "200" do `POST test`, mas o próprio PRD (§8, CA-TES-02, T07) e o código respondem 202 com `poll_url`. Com afirmação dura, o tester marca falha no comportamento correto.
**Evidência:** defer_interactive_ai.rb:10 `render json: {..., poll_url: ...}, status: :accepted`; PRD.md:780 (T09 "200; continua draft") × PRD.md:573, 778.
**Correção:** T09: "202 + poll_url; resultado da consulta com reply; agente continua `draft`".

### R2-16 [media] §11.8 T21
**Problema:** T21 espera 201 de `message_reports`, mas o `create` usa o render implícito, que devolve 200, e a spec atual afirma só `:success`.
**Evidência:** app/controllers/api/v1/accounts/autonomia/agents/message_reports_controller.rb:11-18 (sem `status: :created`); spec/requests/.../message_reports_spec.rb:36 `have_http_status(:success)`; PRD.md:792.
**Correção:** Trocar a afirmação para 200, ou incluir no B1 a mudança para `status: :created` (e atualizar a spec).

### R2-17 [media] §11.8 pré-requisitos × T06, T15, T23
**Problema:** T06 exige um usuário com função personalizada só `autonomia_view` na conta 16, e T15/T23 um usuário só-ver. Criar isso em produção é escrita: a feature `custom_roles` ligada na conta, a função e o vínculo do usuário. Os pré-requisitos citam só a caixa de teste de T17/T18/T21, sem 🟢 e sem regra de BLOQUEADO para esses três cenários.
**Evidência:** enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb:2 `ensure_custom_roles_feature_enabled`; config/features.yml:147 `custom_roles`; enterprise/app/models/enterprise/account_user.rb:7-14; PRD.md:765-767 (pré-requisitos), 777, 786, 794.
**Correção:** Acrescentar ao pré-requisito: função "só ver agentes" e usuário de teste na conta 16 (com 🟢, apagados no fim). Sem eles, T06/T15/T23 ficam BLOQUEADOS.

### R2-18 [media] §11.3 CA-LIG-07 / §11.8 T14 × CA-LIG-12 (ordem das guardas do BE-03)
**Problema:** Um rascunho sem instrução normalmente também não tem etapa `test`. T14 e CA-LIG-07 afirmam 422 `missing_instruction`, CA-LIG-12 afirma `missing_test`, e o BE-03 não diz qual guarda vem primeiro. A depender da implementação, T14 falha por afirmação dura num caso correto.
**Evidência:** PRD.md:276 (BE-03: "pré-condição BE-04 → ... ; sem etapa test → 422 missing_test", sem ordem explícita), 597-598, 604, 785.
**Correção:** Fixar no BE-03 a ordem `missing_instruction` antes de `missing_test` (ou o contrário). Em T14/CA-LIG-07, dizer se o rascunho tem etapa `test` gravada, e ter uma spec R para cada combinação.

### R2-19 [media] §4 D17 / §7 BE-12 × §11
**Problema:** A decisão de segurança D17 (quem só vê não executa no teste ferramenta HTTP com método diferente de GET) não tem critério de aceite nem spec. CA-PTES-03 só prova que quem só vê consegue testar, e CA-TES-04 cobre só a cotação. Nada prova que um POST com segredo deixa de sair.
**Evidência:** PRD.md:77 (D17), 285 (BE-12 "com quem só vê, ferramenta HTTP com método ≠ GET não executa"), 637 (CA-PTES-03), 579-583 (CA-TES-04). Hoje o job autoriza só `autonomia_view` e roda o Answerer: interactive_operation.rb:88-91, 141-148.
**Correção:** Criar CA-PTES-04 (R): ferramenta POST ligada; com só `autonomia_view`, a ferramenta não é chamada (stub HTTP com zero requisições) e a resposta vem com recusa nomeada; com `autonomia_manage`, a chamada sai. Mais um caso GET permitido.

### R2-20 [media] §6.3 / CA-RES-07
**Problema:** A lista de "todos os códigos" de motivo omite `escolhas_incompletas`, que está na allowlist e é gravado em evento para a Lia. Também falta dizer o que mostrar quando o motivo é nulo (o analytics agrupa nulo à parte). Uma spec que percorra a allowlist real falha, ou o código aparece cru na tela.
**Evidência:** app/services/autonomia/agents/operate/event_logger.rb:15-16 `ALLOWED_REASONS = %w[... escolhas_incompletas other]`; :84-87 (nil quando sem motivo); PRD.md:185-186, 627.
**Correção:** Incluir `escolhas_incompletas` (texto pt-BR) e o rótulo para nulo em §6.3 e CA-RES-07. A spec V itera sobre `ALLOWED_REASONS` exportado do backend, não sobre uma lista à mão.

### R2-21 [media] §7 BE-12 / CA-AJU-06 / Q13
**Problema:** A igualdade byte a byte só é garantida para `nil` e `low_confidence`, e Q13 só sinaliza `always_ask`/`never`. Mas `none` é um valor real: está no comentário do model como default antigo e numa spec atual do PanelTune da Lia. Agentes com `none` (ou outro valor legado) podem mudar de prompt ao vivo sem constar da lista que o Rodrigo aprova.
**Evidência:** app/models/autonomia/agents/agent.rb:125-126 "default conservador = 'none'"; origin/main:spec/requests/.../external_agent_lifecycle_spec.rb:338 `config: { handoff_strategy: 'none', ... }`; PRD.md:285, 669-670, 753.
**Correção:** No BE-12/CA-AJU-06: todo valor fora de `always_ask`/`never` (nil, `low_confidence`, `none`, desconhecido) gera instructions byte a byte iguais, com spec por valor. Q13 passa a listar ao Rodrigo qualquer valor diferente de nil/`low_confidence`.

### R2-22 [media] §4 D6 / BE-14 × CA-LISTA-06, §6.1
**Problema:** Com D6-a, a limpeza poupa só rascunho com pelo menos 1 mensagem do usuário, instrução ou material. Um rascunho que clicou "Continuar" na Escolha e saiu antes de responder aparece como "Parou em Conte" com a promessa "Fica guardado até você terminar ou excluir" e é apagado em 48 h. Nenhum CA cobre esse caso: CA-CRIAR-02 só prova o lado poupado.
**Evidência:** origin/main:app/jobs/autonomia/agents/reap_stale_drafts_job.rb:49-56 (draft guiado sem instrução nem fonte, sem atividade em 48 h → destroy); PRD.md:66, 116, 287, 499-500, 524-525.
**Correção:** Escolher e escrever no CA: (a) a frase só aparece quando o rascunho é poupado, e no rascunho vazio vale outro texto (por exemplo "Guardado por 2 dias"); ou (b) o BE-14 poupa também rascunho com etapa gravada. Acrescentar spec R do caso vazio.

### R2-23 [media] §12 × §2 O4 / §11.7 / §4
**Problema:** A correção da v2 deixou os termos finais defasados: §12 pede "Decisões D1–D11" (agora são D1–D17), "validação Q1–Q11" (O4 e §11.7 exigem Q1–Q14 nas duas stacks) e não lista os CA-BE-01..06 (§11.5b) entre os critérios 100% atendidos. Dá para aceitar a entrega sem as decisões D12–D17, sem Q12–Q14 e sem os CA de backend (inclusive o de segurança BE-19).
**Evidência:** PRD.md:808 "D1–D11"; 823 "Q1–Q11"; 805-806 (lista de CA sem CA-BE); PRD.md:42 (O4 "Q1–Q14"), 737, 706-715.
**Correção:** §12: "D1–D17", "Q1–Q14 nas duas stacks" e incluir "CA-BE-01..06" na linha de critérios.

### R2-24 [baixa] §10.2 passo 3 (validação local)
**Problema:** O glob da validação local deixa de fora specs que o próprio PRD exige: BE-25 tem spec em `spec/enterprise` e CA-GERAL-12 (R), o botão do Super Admin, cai em `spec/controllers/super_admin`. Essas specs só rodariam na CI.
**Evidência:** PRD.md:422 `spec/{requests,models,services,jobs}/**/autonomia/**`; PRD.md:298 ("em spec/enterprise"); spec/controllers/super_admin/accounts_controller_spec.rb (onde está o padrão toggle_insurance).
**Correção:** Acrescentar à lista: `spec/enterprise/**/*autonomia*`, `spec/enterprise/requests/api/v1/accounts/custom_role_module_access_spec.rb`, `spec/controllers/super_admin/accounts_controller_spec.rb` e a spec do rack_attack.

### R2-25 [baixa] CA-GERAL-10
**Problema:** "O backend recusa com 401 toda escrita, exceto test e suggest" está errado para `POST agents/message_reports`, que por desenho aceita qualquer membro da conta. Uma spec escrita ao pé da letra falha ou leva a fechar um recurso que deve ficar aberto.
**Evidência:** app/controllers/api/v1/accounts/autonomia/agents/message_reports_controller.rb:3-5, 30-35 (não herda o gate de admin; policy própria); config/routes.rb:316-319.
**Correção:** Acrescentar `POST agents/message_reports` (qualquer membro que vê a conversa) às exceções de CA-GERAL-10.

### R2-26 [baixa] CA-LISTA-05 × protótipo
**Problema:** Para agente interno, CA-LISTA-05 diz "sem linha de números", mas o protótipo mostra "Ainda sem uso". A divergência não aparece em §6.4 nem em §4, então CA-GERAL-06 (textos iguais ao protótipo) e CA-LISTA-05 se contradizem.
**Evidência:** docs/agentes-ia-redesign/mockup/src/screens-list.js:10 `if (a.actuation === 'internal') parts.push(...'Ainda sem uso')`; PRD.md:497-498, 469.
**Correção:** Registrar em §6.4 a retirada de "Ainda sem uso" (texto enganoso, D14) ou manter o texto no CA-LISTA-05.

### R2-27 [baixa] §11.8 T22, T23
**Problema:** T22 marca falha se a thread não sair de `processing` em 90 s, mas uma única chamada ao modelo pode levar até 180 s antes de dar timeout, e o BE-15 assume janela de ~10 min. O tester acusa falha num caso normal. T23 usa `agents-prod.config.ts`, que nenhum PR cria: o F0 cria só `agents.config.ts`, limitado a loopback (§11.6).
**Evidência:** app/services/crm/ai/responses_client.rb:9-10 (REQUEST_TIMEOUT = 180, MAX_RETRIES = 2); PRD.md:288, 793, 794, 398, 719.
**Correção:** T22: limite igual ao STALE_PROCESSING_AFTER do BE-15 (ou 180 s por tentativa), com latência registrada. Pôr `agents-prod.config.ts` (só leitura, usuário só-ver) no escopo do F0.

### R2-28 [alta] §6.2.4 Ligue / §6.3 Ajustes (Como fala) / CA-LIG-04 / CA-PTES-01 / BE-18
**Problema:** "Primeira mensagem" e "Perguntas para puxar conversa" não têm efeito nenhum em produção. Nenhum código de atendimento lê `greeting` nem `starter_questions`: o PRD manda editar, validar (BE-18) e mostrar esses campos, mas o cliente nunca os recebe. Isso fere O5, o princípio 8 e o CA-GERAL-14. O Testar ainda mostra a saudação (CA-PTES-01), coisa que o cliente real não vê, o que contradiz o "Testar igual à produção" do BE-12.
**Evidência:** Busca em app/, lib/ e enterprise/: `greeting`/`starter_questions` só aparecem em agents_controller.rb:158-161 (permit), builder.rb:1015-1018 (gravação) e guide/seed.rb:185. Não aparecem em prompt_builder.rb#instructions (linhas 103-113: scaffold, instrução, persona, guardrails, handoff, fallback, formato), operate/responder.rb, copilot nem widget. No front, só PanelTune.vue, BuilderReview.vue e AgentBuilderPage.vue. PRD: linhas 160-161, 207, 593, 633, 291.
**Correção:** Abrir uma decisão nova na §4: (a) implementar o efeito, com a primeira mensagem enviada pelo Operate na conversa nova e as perguntas exibidas onde o cliente ou a equipe as veja, em BE próprio com spec; ou (b) tirar os dois campos do Ligue e do Ajustes, listando a remoção na §6.4. Até decidir, o CA-LIG-04 não pode ser aceito só com "grava e relê".

### R2-29 [alta] §6.3 Ajustes (Como fala) / CA-AJU-05 / BE-12
**Problema:** "Quando não souber responder" vira controle decorativo depois do BE-12. O texto de `fallback_message` só aparece no caminho com portão (Testar de hoje e Guia). Em produção o modelo recebe só a ordem genérica de "nunca copiar textos de configuração". Quando o Testar passar a usar o caminho da produção, o campo deixa de ter efeito visível em qualquer lugar, e o PRD não trata disso (a D1 só cobre a régua e o handoff_strategy).
**Evidência:** answerer.rb:140-151: trust_instruction_result ignora fallback_message. answerer.rb:620 e 667: fallback só no handoff com portão. prompt_builder.rb:261-268: usa só `present?` e manda "Nunca copie no `reply` textos de configuração". PRD linhas 207 e 667; BE-12 linha 285.
**Correção:** Incluir na D1 (ou numa decisão nova): ou o PromptBuilder passa a entregar o texto como orientação de encaminhamento, com spec byte a byte para os agentes atuais, ou o campo sai do Ajustes e a saída entra na §6.4. Acrescentar spec CA-GERAL-14 para o campo.

### R2-30 [alta] BE-12 × §6.3 Ajustes do Agente de Cotação × CA-AJU-12 × CA-PTES-01
**Problema:** Contradição criada pela v2. O BE-12 diz que `insurance_quote` não recebe o bloco de `handoff_strategy`, mas o Ajustes da Lia continua mostrando "Quando passa para a equipe" (Quando estiver em dúvida / Sempre oferecer / Nunca). Para a Lia essas três opções não mudam nada. A legenda do Testar ("Quem decide passar para a equipe é a regra de 'Quando passa para a equipe'") também fica falsa para ela.
**Evidência:** PRD linha 285: "`insurance_quote` e agentes de sistema não recebem o bloco". Linha 218 e CA-AJU-12 (linha 681) listam "Quando passa" para a Lia. CA-PTES-01 (linha 634) não exclui a Lia. Protótipo screens-panel.js:tabAjustes linha 191: a seção é montada fora do `if (!quote)`.
**Correção:** No Agente de Cotação, mostrar só "Para quem vai" (o BE-06 vale para todos) e esconder as três opções de estratégia, listando isso na §6.4. Ajustar CA-AJU-12 e a legenda do Testar para a Lia. A alternativa seria fazer o Quote Builder ler a estratégia, o que muda o prompt da Lia e exige decisão.

### R2-31 [alta] §6.3 Ajustes item 2 (Mudar conversando) / BE-05 / CA-AJU-02
**Problema:** Retomar a conversa do Construtor sobrescreve sem aviso o que a pessoa editou à mão: nome, primeira mensagem, "quando não souber", jeito de falar (já convertido pela D10), perguntas, resumo e até o tipo. Num agente em modo manual, também troca a instrução escrita pela pessoa pela instrução gerada, que em modo manual é exposta pela API. O PRD não restringe "Mudar conversando" ao modo guiado nem diz o que é preservado. O diálogo do protótipo só promete "Toda mudança vira uma versão nova".
**Evidência:** builder.rb:1008-1022 (map_attributes inclui name, agent_type, instruction, greeting, fallback_message, handoff_rule, starter_questions, tone). agent.rb:206-231 (apply_builder_config! faz update!(merged) sem checar o modo). _agent.json.jbuilder:39 (`json.instruction agent.instruction if agent.manual?`). Protótipo screens-panel.js:180 mostra "Mudar conversando" mesmo com manual=true. PRD linhas 204-205, 278 e 661-662.
**Correção:** BE-05 deve exigir `mode=guided` (422 com code próprio no manual) e o front deve desabilitar o botão no manual, com explicação. Definir quais campos o Construtor pode reescrever na retomada (ou avisar no diálogo "vai trocar nome, jeito de falar…"). Spec: retomar não muda campos editados à mão e não expõe a instrução gerada.

### R2-32 [alta] BE-23 (2) × NR-10 × CA-AJU-03
**Problema:** Correção da v2 que quebra uma proteção existente. O BE-23 grava a versão guiada (`before_manual`) antes de passar para o modo manual. Só que, com o agente em manual, o endpoint de versões expõe o texto de todas as versões, e "Voltar para esta" copia esse texto para `instruction`, que a API expõe em manual. A instrução gerada pelo Construtor (IP oculto, descartada de propósito na troca de modo) passa a vazar. O mesmo já acontece hoje com versões `kb_refresh`.
**Evidência:** agents_controller.rb:142-149: zera a instrução gerada "nunca vazamos a instrução do Construtor". instruction_versions/_instruction_version.json.jbuilder:10: `json.instruction instruction_version.instruction if @agent.manual?`, sem distinguir a origem da versão. agent.rb:293: restore faz update_columns(instruction: version.instruction). PRD linhas 296, 663 e 373.
**Correção:** No BE-23: versões de origem guiada (builder, before_manual, kb_refresh) nunca expõem texto, nem em manual. Restaurar uma delas leva o agente de volta ao modo guiado, em vez de colar o texto no manual. Spec em agent_config_exposure_spec (NR-10) cobrindo os dois casos.

### R2-33 [alta] §6.2.4 Ligue "Quando atende" / §6.3 Ajustes item 7 / CA-LIG-05 / CA-AJU-09
**Problema:** "No horário comercial" e "Fora do horário comercial" prometem algo que o sistema não garante. Se a caixa não tem horário configurado (nem ServiceSchedule nem working_hours), as duas opções valem como "Sempre": o agente responde a qualquer hora, inclusive com a equipe presente. A tela não avisa, e o PRD não pede aviso nem desabilitação.
**Evidência:** operate/engagement_gate.rb:6-8 ("Sem nenhuma fonte configurada, a caixa conta como 'sempre aberta'") e 39-47 (`return true if open.nil?` para os dois modos). Protótipo screens-build.js:169 ("Só quando a caixa está aberta" / "Só quando a equipe não está") e screens-panel.js:165, 208 ("Fora desse horário, as conversas vão direto para a equipe"). PRD linhas 162, 213, 595 e 676.
**Correção:** Expor no `channels#index` (BE-11) se cada caixa tem horário. No Ligue e no Ajustes, com caixa sem horário, mostrar aviso ("Esta caixa não tem horário definido: {ela} vai responder sempre") com link para o horário, ou desabilitar as duas opções. Novo CA com spec do caso sem fonte de horário.

### R2-34 [media] §6.2.4 Ligue / §6.3 Onde atende / §8 rotas / D7 / CA-LIG-09 / CA-OND-05
**Problema:** O botão "Conectar um WhatsApp novo" aparece no Ligue e no Onde atende para qualquer pessoa que edita (`autonomia_manage`). A rota de conexão e o backend exigem administrador (D7). Uma função personalizada que edita agentes vê o botão e cai numa rota proibida ou recebe 401.
**Evidência:** PRD linha 329: rota `autonomia_agents_connect_whatsapp` = administrador. Linha 67 (D7). CA-LIG-09 (601) e CA-OND-05 (657) sem condição de permissão. waha_inboxes_controller.rb:15 (`authorize ::Inbox`, criar caixa = administrador). Protótipo screens-build.js:183 e screens-panel.js:156 mostram o botão sempre.
**Correção:** CA-LIG-09 e CA-OND-05: botão só para administrador. Para quem edita sem ser administrador, mostrar o texto "Peça a quem administra a conta para conectar um WhatsApp", no lugar do botão. Spec V do caso.

### R2-35 [media] CA-CON-07 / CA-SAB-01 (estados de material)
**Problema:** A tradução estado da API → tela está incompleta. (1) `needs_review` significa duas coisas: "conferência em andamento" e "conferência falhou". Com a regra atual, todo material novo mostra "Ainda não conferido… Enviar de novo" enquanto o revisor roda. (2) Material antigo com `review_status` nulo é usado pelo agente, mas "Lendo (ready sem revisão)" deixa ele em "Lendo" para sempre. (3) Material aceito mas "fora do negócio" fica fora da busca e aparece como "Pronto" verde.
**Evidência:** source.rb:141-144: begin_ingestion grava `review_status: 'needs_review', reviewed_at: nil` no início. reviewer.rb:476-485: fallback final também é needs_review, com confidence 'baixa'. retriever.rb:100-103: review_status nil continua no retrieval. retriever.rb:109-116: aceitas "Fora do negócio" são excluídas. sources/_source.json.jbuilder:19-27 já expõe reviewed_at e confidence. PRD linhas 547-551 e 253-254.
**Correção:** No CA-CON-07, distinguir por `reviewed_at`: needs_review sem reviewed_at = "Lendo"; com reviewed_at = "Ainda não conferido". review_status nulo + ready = "Pronto" (sem nota). Aceito com marcador de fora do negócio = estado âmbar "Não é sobre o seu negócio. {Ela} não usa este material.", definido pelo backend num campo próprio, sem o front ler texto.

### R2-36 [media] §6.4 "Marcar resposta como errada" / CA-CONVERSA-02 / CA-RES-05
**Problema:** O diálogo promete "Ajuda quem cuida do agente a corrigir" e pede "Qual seria a resposta certa?", mas nenhuma tela do PRD mostra o motivo nem a resposta sugerida. A gaveta "Respostas marcadas como erradas" usa o serializer genérico (contato, canal, última mensagem). O que a equipe escreve é gravado e ninguém lê.
**Evidência:** message_reports_controller.rb:12-17 grava report_reason e description em Captain::MessageReport. app/builders/v2/reports/drilldown_record_serializer.rb: nenhum campo de report. Busca no front: nenhuma tela lista message reports (só os diálogos de criação). Protótipo main.js:132. PRD linhas 232, 700-702 e 623-624.
**Correção:** Na gaveta com metric `wrong_replies`, mostrar o motivo e a resposta sugerida de cada marcação (campo novo no `analytics/conversations` só para essa métrica), com atalho "Ensinar". Ou mudar o texto do diálogo e listar a mudança na §6.4.

### R2-37 [media] §11.6 Aceite visual / CA-VISUAL-03
**Problema:** O aceite visual vale "para cada tela e estado do mapa do protótipo", mas o MAP não contém a tela Pronto nem vários estados que o protótipo desenha na barra de estados. Os 100% de cobertura visual deixam essas telas sem captura de referência.
**Evidência:** screens-extra.js:65-71 (MAP) não tem 'pronto' (viewPronto, screens-build.js:209), conte@demora/ocupado (screens-build.js:48), teste@erro (135), resumo@carregando/erro (screens-panel.js:39), ptestar@incompleto/erro (84), sabe@vazio (104), onde@falhou (142) nem conectar@conectando/ok/falhou (screens-extra.js:4). PRD linha 722.
**Correção:** Trocar a base do §11.6 de "mapa do protótipo" para "cada tela do MAP + Pronto × cada estado da stateBar daquela tela", com a lista explícita no PRD, e incluir os estados novos sem referência no protótipo (número do D7, "Ainda respondendo").

### R2-38 [media] §6.2.3 Teste (Agente de Cotação) / BE-12
**Problema:** O aviso "No teste a cotação não é feita de verdade" aparece "quando a resposta pediria cotar", mas nenhum campo do resultado do teste diz isso. O BE-12 fala em "recusa nomeada" sem definir o contrato. Sem campo, o front teria de adivinhar pelo texto da resposta, o que a regra de regex proíbe.
**Evidência:** playground/test.json.jbuilder:1-27 devolve só reply, confidence, handoff, answered_from_knowledge, used_knowledge, error, humanized e chunks. PRD linhas 154-155 e 285. CA-TES-04 (583) cobre zero ToolRun, não o aviso.
**Correção:** No BE-12, acrescentar ao resultado do teste um campo estável (ex.: `skipped_tools: [{slug, code: 'not_in_test'}]`). O front mostra o aviso só quando ele vem. Novo CA (V/R) com spec do campo.

### R2-39 [media] §6.4 Conectar um WhatsApp / CA-CONECTAR-02
**Problema:** O fluxo novo tem só 4 estados e um único texto de falha ("O código venceu antes da leitura"). A tela atual de conexão já trata outros casos: sessão desligada (diferente de código vencido), "verificando" e contagem do tempo do código. O passo do número (D7) também não tem estados de erro além de `invalid_phone` (faltam `integration_not_configured` e `remote_setup_failed`). Em sessão parada, a pessoa leria que o código venceu.
**Evidência:** ConnectionPage.vue:30-37 (failed × disconnected, textos diferentes) e 50-57 (connected, awaiting_scan, connecting, failed, disconnected, unknown). wahaQrWindow.js:4-5 (60 s no primeiro código, 20 s nos seguintes). Protótipo screens-extra.js:12. PRD linhas 228-230, 283 e 694-697.
**Correção:** No CA-CONECTAR-02, incluir "Sessão desligada" (texto próprio + reconectar), "Verificando", o tempo restante do código e os erros pt-BR do passo do número por `code` (BE-10). Reusar o mapeamento de ConnectionPage/wahaQrWindow.

### R2-40 [media] §6.1 Cartão / CA-LISTA-05 / D14 / §6.4
**Problema:** O protótipo mostra "Ainda sem uso" no cartão do agente interno, afirmação falsa porque o uso do ajudante não é medido (D14). O CA-LISTA-05 manda não ter linha de números, mas essa divergência não está listada na §6.4. Pela regra de ouro e pelo CA-VISUAL-04, a implementação ou copia o texto falso ou fica fora do protótipo sem registro.
**Evidência:** screens-list.js:10: `if (a.actuation === 'internal') parts.push(... 'Ainda sem uso')`. PRD linhas 74 (D14), 497-498 e 238-261 (§6.4 não menciona).
**Correção:** Acrescentar à §6.4: "Cartão do agente interno: sem a linha 'Ainda sem uso' (o uso não é medido, D14)".

### R2-41 [media] BE-23 (3) / CA-AJU-10
**Problema:** "autor nulo = 'Automático'" não funciona com a API de hoje. O jbuilder de versões troca autor nulo pela marca 'Autonom.ia', então o front não tem como saber que foi automático, e clientes Hub2You veriam "Autonom.ia". O BE-23 só diz "expõe reason e autor", sem pedir a mudança.
**Evidência:** instruction_versions/_instruction_version.json.jbuilder:5: `json.created_by_name(instruction_version.created_by&.name || 'Autonom.ia')`. PRD linhas 216, 296 e 678.
**Correção:** No BE-23 (3): `created_by_name` passa a ser null quando não há autor (ou um campo novo `automatic: true`). O front traduz para "Automático". Spec do caso nulo.

### R2-42 [media] §12 Termos de aceite × §4 × §2 O4 × §11.7
**Problema:** O checklist final não acompanhou a v2. Ele pede "Decisões D1–D11", mas a §4 tem D1–D17 (D12 e D17 são de segurança; D15 garante O2). Pede "validação Q1–Q11 sem desvio", enquanto O4 fala em Q1–Q14 e a regra de aborto usa Q12 e Q13.
**Evidência:** PRD linha 808 ("Decisões D1–D11"), linha 823 ("validação Q1–Q11"), linha 42 (O4: "Q1–Q14") e linha 756 (aborto com Q12/Q13).
**Correção:** §12: "Decisões D1–D17" e "validação Q1–Q14 (Q12–Q14 contra a foto de antes)".

### R2-43 [baixa] §10.1 Dependências (F3 → F6 → B6)
**Problema:** O fluxo de criação (F3: Teste, Ligue, Pronto) depende do F6, que depende do B6, e o B6 junta BE-13 (WhatsApp novo) com BE-17 (edição do Agente de Cotação, risco Médio, deploy isolado). A criação de agentes fica presa à reforma da Lia, sem relação funcional entre as duas.
**Evidência:** PRD linha 397 (B6 = BE-17 + BE-13), linha 401 (F3 depende de F6) e linha 404 (F6 depende de B6 por causa do BE-13).
**Correção:** Separar o BE-13 num PR próprio (ex.: B6a) ou fazer o F3 depender só da rota de conexão com o botão desligado até o F6 sair.

### R2-44 [baixa] §6.3 Ajustes do Agente de Cotação (Jeito de cotar) / BE-17
**Problema:** A descrição de "Jeito de cotar" no protótipo tem o nome "Lia" fixo ("Quando a Lia explica a cobertura…"). Depois de renomear pelo BE-17, a tela mostra o nome antigo. A §6.4 não corrige.
**Evidência:** screens-panel.js:175: `sect('Jeito de cotar', 'Quando a Lia explica a cobertura. Nos dois casos ela nunca responde de memória.', ...)`. PRD linhas 218 e 290.
**Correção:** Acrescentar à §6.4: o texto usa {nome} e o gênero do agente.

### R2-45 [alta] §7 BE-12 × §6.3 Ajustes (Agente de Cotação) × CA-AJU-12 × CA-GERAL-14
**Problema:** A correção do BE-12 deixa "Quando passa para a equipe" sem efeito no Agente de Cotação. O BE-12 diz que `insurance_quote` não recebe o bloco da regra no prompt, mas §6.3 e CA-AJU-12 mantêm esse controle na Lia. Ele grava `handoff_strategy` e nada lê o valor. É o mesmo tipo de controle decorativo que D1, O5 e o princípio 8 proíbem. A legenda do Testar ("Quem decide passar para a equipe é a regra de 'Quando passa'") também fica falsa para a Lia.
**Evidência:** PRD:285 (BE-12: "insurance_quote e agentes de sistema não recebem o bloco"); PRD:218 e PRD:681 (Lia: "Foto e nome, Jeito de cotar, Quando passa…"); mockup screens-panel.js:tabAjustes mostra "Quando passa para a equipe" fora do `if (!quote)`; app/models/autonomia/agents/agent.rb:125-128 (handoff_strategy só é gravado; grep não acha leitor).
**Correção:** Escolher um dos caminhos: (a) tirar "Quando passa para a equipe" da Lia em §6.3, CA-AJU-12 e Apêndice A, e registrar a divergência em §6.4; ou (b) definir como a regra entra no prompt da Lia (`QuoteAgent::Builder`), com spec e Q10. Ajustar a legenda do Testar no Agente de Cotação.

### R2-46 [alta] §4 D15 × §7 BE-03/BE-08 × CA-LISTA-02/04/07 × §6.3 cabeçalho
**Problema:** O estado `ready` sai só de "tem instrução", mas `publish` exige a etapa `test`. O Construtor fecha a instrução no fim do Conte. Um rascunho que sai depois do Conte fica `ready` com etapa `tell`. A lista mostra "Pronto para ligar" e "Escolher onde atende", leva ao Ligue, e o "Ligar" falha sempre com 422 `missing_test`. Nenhum CA diz o que a tela faz com esse código. O mesmo vale para rascunhos com instrução criados antes da flag, que não têm etapa nenhuma. Além disso, a etapa é gravada pelo front ao entrar na tela (`PATCH build_threads/:id {step}`), não por um teste feito. Então O2 não é garantido: basta abrir o Teste e sair. E não está definido se `step=live` também conta como testado.
**Evidência:** PRD:281 (BE-08: ready = com instrução; etapa enviada pelo front "ao entrar em cada etapa"); PRD:276 e 604 (missing_test); PRD:493 e 501 (ready → "Escolher onde atende"); PRD:75 (D15); app/services/autonomia/agents/builder.rb (origin/main) apply_result → apply_to_agent grava a instrução ao fechar a entrevista (needs_more_info=false), antes do Teste.
**Correção:** Fazer o `state` levar a etapa em conta: `ready` só com etapa ≥ test; senão `incomplete` com "Continuar" levando ao Teste. Definir que `publish` aceita etapa ∈ {test, live}. Gravar `test` no backend no primeiro `POST test` concluído ou no "Está bom, continuar", não só ao abrir a tela. Dizer o que acontece com rascunhos legados (redirecionar ao Teste). Criar um CA para a resposta `missing_test` na tela.

### R2-47 [alta] §6.2.2 Conte × CA-CON-02/05/11 × §7 (falta BE)
**Problema:** O painel "O que {a} {nome} já sabe" (4 itens com ✓ e o valor, barra 0–4, "N de 4 respostas", "Testar" liberado com as 4) não tem fonte no backend. O Construtor é uma entrevista do modelo com até 6 perguntas e outro roteiro (objetivo, nome, tom, horário, quando passar, o que nunca fazer). Ele absorve respostas fora de ordem, e o schema não devolve quais tópicos foram respondidos. O BE-07 só trata o nome. Sem um campo do backend, o front teria de adivinhar pelo texto ou pela contagem de turnos, o que a regra do Rodrigo proíbe.
**Evidência:** app/services/autonomia/agents/builder.rb:35-66 (BUILDER_SCHEMA: nenhum campo de cobertura do roteiro); builder.rb:1077-1103 (state_for: só needs_more_info, next_question, draft_config); builder.rb:664 (MAX_INTERVIEW_QUESTIONS = 6); a instrução-mãe §5.1 lista 6 tópicos; mockup screens-build.js:47-56 (`b.answers[s.key]` com 4 chaves fixas); PRD:139-144 e 543-544.
**Correção:** Criar um BE (por exemplo BE-26, junto com BE-07/BE-09 no B3): o schema ganha `knows: {negocio, publico, quando_chama, nome}` (string ou vazio) em `properties` e `required`; a instrução-mãe ganha o roteiro de 4 itens (interno: no que ajuda, quem usa, o que evita, nome); `state_for` grava e o `show.json.jbuilder` expõe. CA-CON-05/11 passam a ler esse campo.

### R2-48 [alta] §8 Rotas × §6.2 × fluxo do Builder
**Problema:** A rota da criação `agents/:agentId/build/:step(tell|test|live)` precisa de `agentId` ao entrar no Conte. Mas o rascunho só nasce depois da 1ª resposta do usuário, ou na abertura quando o front manda `with_knowledge` explícito (KB-first), e mesmo assim só quando o job assíncrono termina. Os Materiais do Conte também exigem `agentId` desde o início. O PRD tira a pergunta "Com/Sem base" e não define se a tela nova manda `with_knowledge`. Com isso a entrada no Conte não tem endereço válido, e "Parou em Escolha" (CA-LISTA-06) nunca acontece, porque não há agente na Escolha.
**Evidência:** builder.rb (origin/main) apply_result: `ensure_agent(token) if … any? role=='user' || knowledge_first_optin?`; builder.rb:971-975 (knowledge_first_optin? exige a chave `with_knowledge` no state); build_threads_controller.rb:create (202 assíncrono; agent_id nil na thread); AgentBuilderPage.vue:81 (o dropzone precisa de agentId); PRD:326, 133 e 499.
**Correção:** Decidir e registrar: (a) a Escolha manda `with_knowledge: true` explícito, o rascunho nasce na abertura e o front espera `agent_id` no polling antes de ir para `build/tell`; ou (b) a rota do Conte usa o id da thread (`agents/new/:threadId/tell`). Tirar "Escolha" de CA-LISTA-06 ou explicar quando ele aparece.

### R2-49 [alta] §7 BE-25 × D12 × CA-RES-04 × T06 (Enterprise)
**Problema:** O BE-25 manda filtrar "pelas caixas de que o usuário é membro". No Enterprise, o padrão do repo para custom role é `Conversations::PermissionFilterService`, que também aplica `conversation_manage`, `conversation_unassigned_manage` e `conversation_participating_manage`. Uma função só com `autonomia_view` ali não vê conversa nenhuma (`Conversation.none`). Filtrar só por caixa ainda expõe nome do contato e última mensagem a quem a função proíbe de ver conversas. A expectativa da spec de CA-RES-04 ("recebe as conversas das caixas de que é membro") vira um teste que aprova o vazamento.
**Evidência:** app/services/conversations/permission_filter_service.rb:12-22; enterprise/app/services/enterprise/conversations/permission_filter_service.rb:2-30 (custom role sem conversation_* → Conversation.none); app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb:15-33 (sem filtro hoje); PRD:298, 620-622 e 777.
**Correção:** BE-25: aplicar `Conversations::PermissionFilterService.new(scope, Current.user, Current.account).perform` no `outcome_scope` (o EE já entra por `prepend_mod_with`). Reescrever CA-RES-04 e T06: função só `autonomia_view` → 0 conversas; com `conversation_manage` → só as caixas de que é membro; administrador → todas. A spec fica em `spec/enterprise`.

### R2-50 [media] §10.1 dependências (B3 × B2)
**Problema:** O B3 (BE-03, publish com 422 `missing_test`) depende da etapa gravada pelo BE-08, que está no B2. Mas a tabela diz que o B3 depende só do B1. Se o B3 entrar antes do B2, o `publish` não tem de onde ler a etapa: ou recusa todo mundo ou a guarda D15 fica sem efeito.
**Evidência:** PRD:276 (BE-03: "sem etapa test registrada (BE-08) → 422 missing_test"); PRD:392-393 (B2 contém BE-08; B3 "Depende de: B1").
**Correção:** B3 passa a depender de B1 e B2.

### R2-51 [media] §10.1 (B6 × F3/F6)
**Problema:** O B6 junta o BE-17 (Agente de Cotação, risco Médio, "deploy isolado") com o BE-13 (WhatsApp novo, risco Baixo). Como o F3 depende do F6, e o F6 depende do B6, toda a criação (Teste, Ligue, Pronto) fica esperando o PR mais arriscado do projeto, que mexe no prompt da Lia. E um B6 com dois assuntos contradiz o próprio "deploy isolado".
**Evidência:** PRD:397 (B6 = BE-17 "deploy isolado" + BE-13); PRD:401 (F3 depende de F6); PRD:404 (F6 depende de B6 (BE-13)); PRD:290 (BE-17 risco Médio).
**Correção:** Separar em B6a (BE-13) e B6b (BE-17). F6 depende de B6a; F5/F7 dependem de B6b.

### R2-52 [media] §7 BE-12 (D17) × arquivo que executa o teste
**Problema:** O BE-12 cita só o `Playground`, mas o teste roda em job, por `Crm::Ai::InteractiveOperation#playground_result`. É lá que se conhece o `account_user`, e o `Playground.new` não recebe usuário nem permissão. Mudando só o `Playground`, a regra "quem só vê não executa ferramenta com método ≠ GET" não tem como ser aplicada.
**Evidência:** app/services/crm/ai/interactive_operation.rb:88-92 (authorize_agent! com @account_user) e :140-151 (Playground.new(agent:, **args) sem permissão); app/services/autonomia/agents/playground.rb:6-16; PRD:285.
**Correção:** No BE-12: `InteractiveOperation#playground_result` passa `pode_editar: @account_user.permission_granted?('autonomia_manage')` (ou `operador:`) ao Playground, que repassa ao Answerer. Spec com função só-ver e ferramenta POST: zero chamadas HTTP.

### R2-53 [media] §7 BE-12/BE-24 × CA-TES-03 × T08
**Problema:** O motivo da passagem no Testar sai cru do modelo. `handoff_reason` é string livre no schema, e o caminho de produção (trust_instruction) repassa o valor sem curar. Só o Analytics e o EventLogger reduzem o motivo à lista fechada. CA-TES-03 ("{motivo em pt-BR}"), T08 ("reason da lista ou nulo") e a nota do BE-24 ("motivo pt-BR do código") pressupõem um código, mas nenhum BE manda curar no Playground.
**Evidência:** app/services/autonomia/agents/prompt_builder.rb:21 (handoff_reason: string|null, sem enum); answerer.rb:150 (`reason: parsed['handoff_reason'].presence`); app/views/.../playground/test.json.jbuilder:4 (expõe cru); operate/event_logger.rb:15-16 e :93 (ALLOWED_REASONS e curadoria só no evento); analytics.rb:131-134.
**Correção:** No BE-12: o `test.json.jbuilder` (ou o Playground) devolve `reason` passado por `EventLogger.curate_code`. O BE-24 usa o mesmo código curado. Incluir `escolhas_incompletas` (já está em ALLOWED_REASONS) ou explicar por que fica fora da lista de rótulos de CA-RES-07.

### R2-54 [media] §7 BE-19 × NR-05 (spec citada)
**Problema:** Com a lista fechada e 422 para "qualquer outra chave", as specs de `external_agent_lifecycle_spec.rb:170-209` quebram por um motivo além de `temperature`. Elas mandam `with_knowledge` e `agente_de_cotacao` (chaves protegidas hoje descartadas em silêncio) e esperam 200. O PRD só manda trocar `temperature` por `response_window`, o que não basta. Também falta decidir se uma chave protegida enviada vira 422 ou continua descartada: é isso que define o novo comportamento das duas specs.
**Evidência:** spec/requests/api/v1/accounts/autonomia/journeys/external_agent_lifecycle_spec.rb:176-177 (envia `with_knowledge: true`) e :195-196 (envia `agente_de_cotacao`), ambos esperando `have_http_status(:success)`; agents_controller.rb:38-41 e :190-193 (PROTECTED_CONFIG_KEYS descartadas no merge); PRD:292 e 368.
**Correção:** No BE-19: dizer que chaves de PROTECTED_CONFIG_KEYS também respondem 422 `config_key_not_allowed`, e que as duas specs mudam para afirmar 422 com o `config` intacto (mudança justificada em NR-05).

### R2-55 [media] §7 BE-06 (validação do alvo "Uma pessoa")
**Problema:** A validação pede "membro da conta". O Chatwoot filtra as conversas de quem não é administrador pelas caixas de que a pessoa é membro. Uma conversa atribuída a um agente da conta que não está na caixa some das listas dele e fica parada. O `AssignmentService` aceita qualquer usuário da conta.
**Evidência:** app/services/conversations/assignment_service.rb:49-51 (`conversation.account.users.find_by`); app/services/conversations/permission_filter_service.rb:22 (`where(inbox: user.inboxes)`); PRD:279.
**Correção:** No HandoffRouter: `member` vale só se o usuário for membro da caixa da conversa (ou administrador); senão cai em `any` com o log `alvo_invalido`. Spec com membro da conta fora da caixa.

### R2-56 [media] §7 BE-06 × Crm::Ai::HandoffExecutor
**Problema:** Com "Um time", o BE-06 só faz `update!(team:)` e a conversa continua sem responsável. Nas contas com passagem por IA ligada no funil, o `Crm::Ai::HandoffExecutor` só se bloqueia quando já há responsável, e escolhe a pessoa sem olhar o time. Ele pode atribuir alguém de fora do time escolhido, desfazendo a configuração sem erro visível. O PRD não trata essa convivência.
**Evidência:** app/services/crm/ai/handoff_executor.rb:57-62 (blocked_reason: `already_assigned` só com assignee_id); grep por "team" em handoff_executor.rb e handoff_member_selector.rb sem resultado; agent.rb:73-74 ("o handoff para pessoa continua sendo o do CRM"); PRD:279.
**Correção:** No BE-06: dizer como `team` convive com o HandoffExecutor (por exemplo, o executor respeita `conversation.team` ao escolher, ou o router também atribui a um membro do time), com spec do caso "funil com passagem por IA ligada + alvo time".

### R2-57 [baixa] §11.8 T09
**Problema:** O T09 espera `200` no `POST test`, mas a v2 corrigiu o teste para assíncrono (202 + `poll_url`) em §6.2.3, §8, CA-TES-02 e T07.
**Evidência:** PRD:780 (T09: "200; continua draft"); PRD:778 e 573; playground_controller.rb:14 → defer_interactive_ai responde `status: :accepted` (concerns DeferInteractiveAi).
**Correção:** T09: "202 + poll_url; resultado em ai_requests/:id; agente continua draft".

### R2-58 [baixa] §12 Termos de aceite × §4 e §11.7
**Problema:** Os termos finais ficaram desatualizados depois das correções. Dizem "Decisões D1–D11", mas a §4 vai até D17. Dizem "validação Q1–Q11 sem desvio", mas a §11.7 roda Q1–Q14 e aborta por Q12/Q13. O T24 também confere só Q1–Q11.
**Evidência:** PRD:808 (D1–D11); PRD:823 (Q1–Q11); PRD:737 e 756 (Q1–Q14, aborto por Q12/Q13); PRD:795 (T24).
**Correção:** §12: "D1–D17" e "Q1–Q14 nas duas stacks"; T24: Q1–Q14 (Q12–Q14 iguais à foto).

### R2-59 [baixa] §14 Volta e §13 Riscos
**Problema:** O BE-24 (nota privada nos 3 pontos de passagem, risco Médio, caminho ao vivo) ficou fora da lista de "mudanças no caminho ao vivo" da volta e do risco de Clara/Lia.
**Evidência:** PRD:297 (BE-24 Médio, caminho ao vivo); PRD:852 (volta lista BE-06, BE-12, BE-17, BE-19); PRD:838 (risco lista BE-06, BE-12, BE-17).
**Correção:** Incluir o BE-24 nas duas listas (é revertido junto com o B5).

### R2-60 [baixa] §7 BE-23 (autor "Automático")
**Problema:** O BE-23 diz que `instruction_versions` passa a expor o autor e que "autor nulo = Automático". Mas a API já devolve `created_by_name` com o valor fixo `'Autonom.ia'` quando não há autor. O front nunca recebe nulo, a regra não dispara, e a marca "Autonom.ia" aparece para contas Hub2You.
**Evidência:** app/views/api/v1/accounts/autonomia/agents/instruction_versions/_instruction_version.json.jbuilder:4-5 (`created_by&.name || 'Autonom.ia'`); PRD:296.
**Correção:** No BE-23: expor `created_by_name` nulo (ou `automatic: true`) quando `created_by_id` é nulo, e regerar o formato do Guia.

### R2-61 [baixa] §7 BE-17 (parâmetro `business_hours`)
**Problema:** O PATCH `quote_choices` aceita `business_hours`, que vira a escolha `horario` (texto livre no prompt da Lia). Nenhuma tela grava esse campo: "Quando atende" da Lia é `response_window` com 3 opções (protótipo e §6.3). Fica um parâmetro sem controle, com nome que se confunde com o valor `business_hours` do `response_window`.
**Evidência:** app/services/autonomia/insurance/quote_agent/builder.rb:287-292 (VARIAVEIS: horario → $horarioAtendimento); quote_agent_controller.rb:57 (`horario: business_hours`); mockup screens-panel.js:tabAjustes (Lia: "Quando atende" = windows always/business_hours/outside_business_hours); PRD:290.
**Correção:** Tirar `business_hours` do PATCH ou criar o campo de texto do horário na seção da Lia e no CA-AJU-12. Usar o nome `horario` no parâmetro.

### R2-62 [baixa] §11.7 Q12 × BE-19
**Problema:** O Q12 (quem já tem gravadas as chaves que o BE-19 fecha) confere só 4 chaves. O BE-19 fecha também chaves que o Operate lê por agente e que hoje podem ter sido gravadas pelo PATCH: `humanize_delivery`, `operate_media`, `operate_reactions`, `voice_instructions`, `debounce_seconds`, `model`, `temperature`. Esses agentes não aparecem na foto de antes.
**Evidência:** app/services/autonomia/agents/config.rb:222, 239, 261, 275, 289 e 316 (leituras por agente de config['debounce_seconds'|'humanize_delivery'|'operate_media'|'operate_reactions'|'voice_reply'|'voice_instructions']); PRD:752 (Q12 com 4 chaves); PRD:292.
**Correção:** O Q12 lista todas as chaves de `config` fora da lista fechada do BE-19, exceto as gravadas pelo Builder e pelo model (com_knowledge, topic_map, knowledge_*, voice, guardrails, agente_de_cotacao, system_key, guide_*).

### R2-63 [baixa] §7 BE-10 (erros do WhatsApp)
**Problema:** A lista de códigos de `waha_inboxes#create` não inclui `account_token_missing`, que o provisionador também levanta. Esse erro chegaria à tela sem frase pt-BR.
**Evidência:** app/services/waha/inbox_provisioner.rb:43-45 (integration_not_configured, invalid_phone, account_token_missing) e :66 (remote_setup_failed); PRD:283.
**Correção:** Incluir `account_token_missing` nos códigos do BE-10 e em CA-CONECTAR-01.

