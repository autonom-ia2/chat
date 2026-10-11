# Pedido de parar no follow-up de IA também marca o contato (#1325)

## Contexto

Desde o #1318 (#1317), o modelo decide se a resposta ao follow-up de IA foi pedido para parar, e o "sim" gravava `opted_out` só no card. Campanhas, avisos do agendamento e broadcast perguntam pelo contato (`Contact#opted_out?`, #713/#737) e não viam esse pedido. Decisão do Rodrigo em 11/10/2026 (registro em #1322): o contrato de toda frente é `contact.opted_out?`.

## Decisões

- **Origem nova `follow_up_reply`** em `ContactOptOut::OPT_OUT_SOURCES`, uma origem por linha, para a próxima (`contact_import`, da Base de Clientes) entrar ao lado.
- **A marca no card é a prova da recusa.** `Crm::FollowUps::CardOptOut` reúne a regra: `contact_for(card)` (conversa primária, senão o contato do card, a mesma ordem do planner e do runner) e `contact_marked?(contact)` (algum card da conta com `auto_followup_state.opted_out = true` cujo contato, pela mesma ordem, é aquele). Sem coluna nova.
- **"Sim" grava no contato.** `Crm::FollowUps::OptOutDecision` chama `opt_out!(source: 'follow_up_reply')` no contato do card, dentro do mesmo `with_lock` do card. Idempotente: contato que já recusou, por qualquer origem, fica como está.
- **Falha explícita.** Erro de banco (`ActiveRecord::ActiveRecordError`) desfaz card e contato juntos; o job tenta de novo com o mesmo teto do provedor (5 tentativas) e, esgotado, grava `opt_out_decision: falhou` e loga a classe do erro. Cada nova tentativa chama o modelo de novo.
- **Cada origem desfaz só o que é dela.** `release_opt_out!(source:, by:)` generaliza o `release_manual_opt_out!`. Se a mesma origem ainda se sustenta, nada muda; se outra sustenta, a recusa passa para ela.
- **Reset do follow-up** (`CardsController#reset_auto_followup`): cancelamento dos toques, estado do card e recusa do contato numa transação só. Libera a `follow_up_reply` só se o próprio card estava marcado antes do reset e nenhum outro card do contato continua marcado. Recusa de outra origem não sai.
- **Herança** (`Contacts::OptOutInheritance#source_for`): passa a enxergar a `follow_up_reply` derivada de card marcado, primeiro da lista (mesma ordem da fusão). Por isso a fusão não perde a recusa: os cards do absorvido passam para o que fica, e desfazer a manual devolve a `follow_up_reply`.
- **Fusão** (`ContactMergeAction::OPT_OUT_PRECEDENCE`): `manual`, `follow_up_reply`, `email_unsubscribe`, `prospecting`.
- **Painel do contato:** o "Desfazer recusa" continua só para a manual. A `follow_up_reply` aparece com o rótulo "Pediu para parar no follow-up" / "Asked to stop in a follow-up reply", sem botão, com a dica de onde sai.
- **`SegmentEligibility#card_opted_out?`** continua conferindo o card (agora pela mesma regra), que é a prova e cobre cards marcados antes do #1325.

## Efeito colateral aceito

- Card marcado antes do #1325 cujo contato não tem recusa: se a herança rodar para esse contato (contato que muda de telefone ou e-mail, quando a conta tem lead recusado ou e-mail descadastrado), ele ganha a `follow_up_reply`. É a mesma regra (o card é a prova), aplicada tarde.

## Fora deste PR

- Sem backfill dos cards antigos para o contato.
- Contrato final a escrever no #1322.

## Validação (11/10/2026, snapshot `20261011-134422-8f60c614-dcb22e20b6-e3ff9284`, RSpec e RuboCop no M2)

- RSpec: `spec/jobs/crm/follow_ups`, `spec/models/contact_spec.rb`, `spec/actions/contact_merge_action_spec.rb`, `opt_outs_controller_spec`, `auto_followup_reset_flow_spec`, `spec/services/crm/follow_ups`, `spec/services/autonomia/prospecting`, `spec/services/contacts`, `spec/jobs/contacts`, `lead_opt_out_contacts_spec`, `unsubscribe_controller_spec`, `backfill_contact_opt_out_job_spec`, `booking_pages_notices_spec`, `legacy_ui_action_permissions_spec`, `formatos_spec` e `spec/requests/api/v1/accounts/crm/cards*_spec.rb`. Resultado: 1399 exemplos, 1 falha e 3 pendentes. A falha era o `formatos_spec` (só números de linha do controller); regerado com `rails autonomia:guia:formatos`, `autonomia:guia:formatos:check` diz "em dia" e o `formatos_spec` rodado de novo deu 23 exemplos, 0 falhas. As 3 pendências são quarentena antiga (`QUARANTINE: pre-existing legacy failure`).
- RuboCop nos 14 arquivos Ruby tocados: sem ocorrências.
- Vitest (`ContactOptOut/` e `CrmCardAutoFollowupStatus.spec.js`): 3 arquivos, 16 testes, todos passando.
- ESLint em `ContactOptOut/`: sem ocorrências.
- `pnpm i18n:fork:check`: 16 catálogos, chaves e parâmetros en/pt_BR cobertos.
- `pnpm central:check`: em dia (189 artigos). `pnpm guia:check`: em dia.
- Revisão independente (`caveman:cavecrew-reviewer`): 2 graves e 8 riscos, todos tratados nesta versão (reset de outro card, fusão perdendo a recusa, contato divergente, transação do reset, falha no job, comentário da elegibilidade, specs e este registro).

## Segunda revisão (commit 84b520273b)

- **Reset com o card travado.** `reset_auto_followup` roda dentro de `@card.with_lock`: a leitura da marca, a gravação do card e a liberação do contato acontecem com o card travado, o mesmo lock da decisão do modelo.
- **Liberação com o contato travado.** `release_opt_out!` pega o lock do contato e só então confere a prova (`source_for`). O "sim" grava o card e depois trava o contato (`opt_out!` trava sempre, mesmo quando não muda nada), então um "sim" concorrente noutro card ou já está visível, ou grava a recusa de novo depois.
- **Contato marcado guardado no card.** No "sim", o estado guarda `opt_out_contact_id`. A prova (`CardOptOut.marked_cards_for`) e o reset usam esse contato; card antigo sem a chave usa `contact_for`. Trocar o contato ou a conversa do card não deixa recusa sem prova. Na fusão, `CardOptOut.transfer_marks!` passa a chave do absorvido para o que fica. O texto da tela do contato diz isso.
- **Nova tentativa sem chamar o modelo de novo.** O resultado do classificador fica em `Rails.cache` por mensagem (`crm:opt_out_decision:<id>`, 1 hora). Com erro de banco, o modelo é chamado uma vez e as 5 tentativas só regravam.
- **Resolvedor único.** `AutoFollowupTouchBuilder#contact_id` passa a usar `CardOptOut.contact_for` (antes: contato do card primeiro, conversa depois).
- **Predicado único.** `CardOptOut.card_opted_out?` usa `Crm::Ai::Config::BOOLEAN.cast`, como o planner.
- **Central 10.09:** a evidência `crm.json:1012 "Reativar follow-up"` passou para a chave real `CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.REACTIVATE` (`crm.json:1447`, "Reativar retorno automático").

### Card arquivado pode ser resetado?

Sim, pela API. Lido no código, sem mudar política: `CardsController#fetch_card` busca em `policy_scope(::Crm::Card)` (`Crm::Cards::VisibleScopeQuery`, sem filtro de status), `Crm::CardPolicy#reset_auto_followup?` é `update?` → `show?` (visibilidade) e, no EE, `crm_permission?('crm_manage_ai') && show?`; nenhum dos dois olha `status`. `reset_auto_followup` também não. O planner só re-arma card `open?`, então o reset de um card arquivado zera o estado e libera a recusa `follow_up_reply` (se for o último card marcado), mas não volta a enviar. Enquanto não é resetado, o card arquivado marcado continua sustentando a recusa do contato.

### Validação da segunda revisão (11/10/2026, mesmo snapshot, RSpec e RuboCop no M2)

- RSpec, os mesmos 17 grupos: 1402 exemplos, 0 falhas, 3 pendentes (quarentena antiga). Uma rodada anterior, antes de regerar os formatos, deu 1402 exemplos, 1 falha (`formatos_spec`, só números de linha).
- `rails autonomia:guia:formatos` regerado; `autonomia:guia:formatos:check`: em dia.
- RuboCop nos 15 arquivos Ruby do PR: sem ocorrências (uma de alinhamento de hash no spec foi corrigida à mão e rodada de novo).
- Vitest: 3 arquivos, 16 testes, todos passando. ESLint: sem ocorrências.
- `pnpm i18n:fork:check`: 16 catálogos cobertos. `pnpm central:check`: em dia (189 artigos); restam 6 evidências antigas de `crm.json` na 10.09, anteriores a este PR. `pnpm guia:check`: em dia.
- Specs novos: reset lê a marca com o card travado; card que mudou de contato libera o contato marcado; liberação com prova concorrente não apaga a recusa; `contact_for` diferente de `card.contact` (marca e toque usam o contato da conversa); erro de banco chama o modelo uma vez.

## Terceira revisão (commit 169e471208)

- **Ordem de locks: follow-up -> card -> contato.** É a ordem do DueProcessor (trava o follow-up) e do AutoFollowupRunner (trava o card depois, `auto_followup_runner.rb`, comentário de `apply_current_composition`). O `reset_auto_followup` agora abre uma transação, trava os toques `ai_followup` ativos do card (`FOR UPDATE`, por id), depois o card (`lock!`, que relê a marca), cancela, grava e libera os contatos (cada `release_opt_out!` trava um contato, por id). O `OptOutDecision` trava card -> contato. O `release_opt_out!` trava só o contato e lê os cards da prova sem lock. Nada neste PR trava contato antes de card. Toque criado depois da primeira leitura não é cancelado pelo reset: travá-lo depois do card inverteria a ordem, e o estado zerado já o torna inofensivo.
- **Inversão pré-existente, anotada e não corrigida aqui:** `ContactMergeAction#merge_and_remove_mergee_contact` trava os dois contatos (`lock!`, por id) e depois chama `@mergee_contact.destroy!`, cujo `has_many :crm_cards, dependent: :nullify` (`contact.rb:68`) escreve em `crm_cards` depois do lock dos contatos: contato -> card, o inverso da ordem acima. Na prática os cards do absorvido já passaram para o que fica (`merge_crm_cards`) antes, então o nullify costuma não achar linha, mas a ordem existe. Não muda neste PR.
- **Spec do lock prova o lock.** O stub fica no `Crm::Card#lock!` e faz o "sim" chegar logo antes de o lock valer. O spec confere que o stub rodou e que o contato estava recusado (`follow_up_reply`) antes do reset. Mutação conferida de fato no snapshot do M2: tirando o `@card.lock!` (só a transação), o spec falha com `expected {ran: true, contact_opted_out: "follow_up_reply"}, got {ran: false, contact_opted_out: nil}`; o arquivo foi restaurado depois.
- **Revertido:** a troca do `AutoFollowupTouchBuilder#contact_id` da segunda revisão. Ela mistura chaves entre toques pendentes e novos e mexe em relatório e no teto do runner; fica fora deste PR. O `CardOptOut.contact_for` segue como o resolvedor do opt-out.
- **Predicado:** `CardOptOut.card_opted_out?` volta a comparar com `'true'` exato, igual ao `OPTED_OUT_SQL`. O planner aceita mais formas de verdadeiro de propósito (fail closed).
- **Recusa da pessoa:** `source_for` e `possible_for?` reconhecem a prova de qualquer contato da mesma conta com o mesmo telefone ou e-mail (`CardOptOut.same_person`/`person_marked?`), como as outras origens. O reset do último card marcado libera o contato marcado e os que herdaram a recusa pela mesma pessoa.
  - Limite encontrado: a validação do contato não deixa repetir telefone nem e-mail na conta (e o e-mail tem índice único no banco). Então "outro contato com o mesmo telefone" só existe em dado gravado sem validar (cadastro antigo, importação ou API); o spec cria o contato assim. Um contato novo que nasce depois de o marcado ser apagado não herda, porque a prova aponta para um contato que não existe mais. Para isso, o "sim" teria de guardar o telefone e o e-mail no card. Fica como pergunta de produto.
  - Corrida residual: um "sim" trava só o contato marcado. Se o reset de outro card liberar, ao mesmo tempo, um contato que herdou a recusa pela mesma pessoa, esse contato pode perder a recusa até a próxima herança.

### Validação da terceira revisão (11/10/2026, mesmo snapshot, RSpec e RuboCop no M2)

- RSpec, os mesmos 17 grupos: 1403 exemplos, 0 falhas, 3 pendentes (quarentena antiga).
- `rails autonomia:guia:formatos` regerado; `autonomia:guia:formatos:check`: em dia.
- RuboCop nos 14 arquivos Ruby do PR: sem ocorrências.
- Vitest: 3 arquivos, 16 testes, todos passando. ESLint: sem ocorrências.
- `pnpm i18n:fork:check`: 16 catálogos cobertos. `pnpm central:check`: em dia (189 artigos; restam as 6 evidências antigas de `crm.json` na 10.09). `pnpm guia:check`: em dia.
- Mutação do lock: falha como esperado (acima).
