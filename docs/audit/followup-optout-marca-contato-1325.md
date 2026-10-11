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

- **Ordem de locks: follow-up -> card -> contato.** É a ordem do caminho principal do DueProcessor (trava o follow-up) e do AutoFollowupRunner (trava o card depois, comentário de `apply_current_composition`). O `reset_auto_followup` abre uma transação, trava os toques `ai_followup` ativos do card (`FOR UPDATE`, por id), depois o card (`lock!`, que relê a marca), cancela, grava e libera o contato (`release_opt_out!` trava o contato). O `OptOutDecision` trava card -> contato. O `release_opt_out!` trava só o contato e lê os cards da prova sem lock. Nada neste PR trava contato antes de card.
  - *Correção da revisão final:* o runner não usa uma ordem só. No caminho de parada (`stop_cadence`/`stop_closure`/`skip` -> `cancel_pending_siblings`, `auto_followup_runner.rb:608-642`) ele faz card -> toques irmãos. O reset segue o caminho principal; o cruzamento com o caminho de parada pode dar deadlock, que o banco resolve abortando um dos lados, sem corromper dado. Já existia no runner e está no #1342.
  - *Correção da revisão final:* toque criado pelo planner logo depois da leitura do reset não é cancelado por ele (travá-lo depois do card inverteria a ordem) e pode ser enviado, porque o runner não lê `state['active']`. Janela estreita, já existente, registrada no #1342. (A versão anterior deste registro dizia que o estado zerado o tornava inofensivo; não é verdade.)
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

## Decisão sobre a recusa por pessoa (depois do commit 56a1854417)

- **Revertido** o item "Recusa da pessoa" da terceira revisão (`CardOptOut.same_person`/`person_marked?`, o uso em `source_for`/`possible_for?` e a liberação, no reset, dos contatos que herdaram). A prova volta a ser do contato marcado: `opt_out_contact_id` ou, em card antigo, `contact_for`, como no 169e471208. O resto da terceira revisão fica: ordem de locks follow-up -> card -> contato, spec do lock com mutação, `AutoFollowupTouchBuilder` revertido e predicado `'true'` exato.
- **A `follow_up_reply` é por contato.** Telefone e e-mail são únicos por conta (validação do contato; o e-mail também tem índice único no banco), então outro contato da mesma pessoa quase não existe, e a herança por pessoa trazia uma corrida residual.
- **Limitação conhecida:** se o contato marcado for apagado e nascer outro com o mesmo número, o novo não herda a recusa. Segue para o #1319.
- Central e textos da tela conferidos: nenhum promete herança por pessoa para essa origem. A 09.04 passou a dizer que a recusa do follow-up "fica só neste contato".

### Validação depois da reversão (11/10/2026, mesmo snapshot, RSpec e RuboCop no M2)

- RSpec, os mesmos 17 grupos: 1402 exemplos, 0 falhas, 3 pendentes (quarentena antiga). Uma rodada antes de regerar os formatos deu 1 falha, só no `formatos_spec` (números de linha do controller).
- `rails autonomia:guia:formatos` regerado; `autonomia:guia:formatos:check`: em dia.
- RuboCop nos 14 arquivos Ruby do PR: sem ocorrências.
- Vitest: 3 arquivos, 16 testes, todos passando. ESLint: sem ocorrências.
- `pnpm i18n:fork:check`: 16 catálogos cobertos. `pnpm central:check`: em dia (189 artigos; restam as 6 evidências antigas de `crm.json` na 10.09). `pnpm guia:check`: em dia.

## Merge com a main (depois do commit 6eed804b7e)

- `git merge origin/main` (c1187a627e), sem rebase. `cards_controller.rb` juntou sozinho: ficam o acesso por funil da main (#1148: `policy_scope`, `card_guard`, `multiple_pipelines?`) e o nosso `reset_auto_followup`. A 10.09 conflitou só numa evidência de linha, resolvida com a linha real. O `formatos-das-acoes.json` foi regerado com `rails autonomia:guia:formatos`, sem resolver à mão; a diferença para a main é só de números de linha. Evidências da Central acertadas com `pnpm central:check`.
- A main não mexeu em `db/`, `Gemfile` nem `package.json`; o snapshot existente recebeu os 98 arquivos que mudaram desde a base dele (`8f60c61457`), nos dois nós.

### Validação sobre o merge (11/10/2026, mesmo snapshot, RSpec e RuboCop no M2)

- RSpec, os mesmos 17 grupos: 1402 exemplos, 0 falhas, 3 pendentes (quarentena antiga).
- `autonomia:guia:formatos:check`: em dia. RuboCop nos 14 arquivos Ruby do PR: sem ocorrências.
- Vitest: 3 arquivos, 16 testes, todos passando. ESLint: sem ocorrências.
- `pnpm i18n:fork:check`: 16 catálogos cobertos. `pnpm central:check`: em dia (189 artigos; restam as 6 evidências antigas de `crm.json` na 10.09). `pnpm guia:check`: em dia.

## Revisão do PR #1343 (depois do merge bbbf2ee894)

- **Consentimento (MEDIUM).** A recusa do contato vale para a conta inteira, e o reset conferia só `CardPolicy#reset_auto_followup?` (IA do CRM no funil). Agora o reset só chama `release_opt_out!` se o usuário também passar em `ContactPolicy#update?` para aquele contato, o mesmo caminho do painel (`authorize_contact_update`), com o override do EE (`relationship_record_write?`: administrador, sem função personalizada, ou `contact_manage`). No OSS, `ContactPolicy#update?` é `true`. Sem a permissão, o reset limpa só o card e a recusa continua.
- **Resposta do reset:** campo `contact_opt_out` = `released` | `kept_other_cards` | `kept_other_source` | `kept_no_permission` | `none`. `kept_other_source` entrou além dos quatro pedidos: a recusa saiu da origem `follow_up_reply` mas continua por outra que a herança sustenta (e-mail descadastrado, lead recusado).
- **Drawer:** `CrmCardAutoFollowupStatus` usa o mesmo `useAlert` do reset, com as frases "Retorno reativado. A recusa do contato continua: outro card ainda a segura." / "...: só quem pode editar contatos pode removê-la." / "...continua por outra origem." (en + pt_BR).
- **Job:** `retry_on` só para erro transitório de banco (`ActiveRecord::Deadlocked`, `LockWaitTimeout`, `ConnectionNotEstablished`, `QueryCanceled`, todos existentes no Rails 7.2.3.1). `RecordInvalid`/`RecordNotFound` falham na hora, sem nova tentativa.
- Comentário de `Contacts::OptOutBackfill` atualizado (a `follow_up_reply` vem primeiro no `source_for`, e não entra no backfill).
- Specs: EE sem `contact_manage` (`kept_no_permission`, card resetado, recusa mantida); com `contact_manage` (`released`); card arquivado resetado (documenta o comportamento atual); `none`; `kept_other_cards`; erro não transitório sem nova tentativa; alerta do drawer por resultado.
- Fica para #1342/#1319: `Deadlocked` → 409 no reset, índice parcial, specs de `transfer_marks!` com card antigo e de `SegmentEligibility` com `opt_out_contact_id`.

### Validação da revisão do PR (11/10/2026, mesmo snapshot, RSpec e RuboCop no M2)

- RSpec, os mesmos 17 grupos mais o spec EE novo: 1407 exemplos, 0 falhas, 3 pendentes (quarentena antiga). A rodada anterior deu 2 falhas, corrigidas: `formatos_spec` (números de linha, regerado) e o spec de erro não transitório (o helper `perform_enqueued_jobs` embrulha a exceção; passou a usar `perform_now` e conferir que nada foi reenfileirado).
- `rails autonomia:guia:formatos` regerado; `autonomia:guia:formatos:check`: em dia.
- RuboCop nos 17 arquivos Ruby do PR (inclui o jbuilder e o spec EE): sem ocorrências.
- Vitest (tela do contato e drawer): 3 arquivos, 21 testes, todos passando.
- ESLint: 0 erros. Os avisos `no-missing-keys` de `CRM_KANBAN` são do mesmo tipo dos que o arquivo já tinha na main (25 lá); o aviso de chave dinâmica foi evitado com chamadas `t()` literais.
- `pnpm i18n:fork:check`: 16 catálogos, 24244 mensagens. `pnpm central:check`: em dia. `pnpm guia:check`: em dia.
