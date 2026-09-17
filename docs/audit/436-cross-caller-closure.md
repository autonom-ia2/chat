# #436 — fechamento local dos chamadores de locks

Data: 2026-09-16. Revisão/edição local, sem Git writes, Rails/RSpec, banco, rede, AWS, SSH, SMTP, instalação ou env real. Execução PostgreSQL e integração final pertencem ao parent. **Não é declaração de pronto para merge/deploy nem resultado de concorrência executada.**

## Manifesto exato desta rodada

| Arquivo | Mudança |
| --- | --- |
| `app/models/email_campaign.rb` | Contadores: coleta e escrita aguardam o commit externo via `ActiveRecord.after_all_transactions_commit`. Enqueue de resume também aguarda esse commit. Transições do parent preservadas. |
| `app/models/email_campaign_import.rb` | Captura a transição completed no `after_update` e registra enqueue para depois do commit externo. Um reload posterior não apaga a decisão via dirty tracking; rollback descarta o callback. |
| `app/controllers/email_campaigns/unsubscribe_controller.rb` | Entra por Admission antes de recipient/registry/evento/status. |
| `app/controllers/api/v1/accounts/email_campaigns/recipients_controller.rb` | Upload/retry entram em `with_delivery_lock`, antes de campanha/import. |
| `app/services/email_campaigns/suppression_registry.rb` | Escritor avulso trava conta antes de suppression state/legacy/FKs. Chamadores compostos já possuem essa conta. |
| `app/services/email_campaigns/recipient_importer.rb` | Separa prepare/parsing do perform; reserva `campaign FOR KEY SHARE` antes dos filhos; mantém insert_all em lotes de 500 e transação atômica. |
| `app/jobs/email_campaigns/recipient_import_job.rb` | Parsing/download fora do lock do import. Na gravação, reserva a FK da campanha antes de import NOWAIT; recipients/issues/completed permanecem atômicos. |
| `app/services/email_campaigns/tracking/event_recorder.rb` | Open/click relê e atualiza recipient sob lock, evitando que instância antiga sobrescreva unsubscribe. Contadores depois do bloco. |
| `app/services/email_campaigns/preflight_lease.rb` | Acquire/claim/advance/resultado entram em conta → estado → campanha; summary coletado antes do lock. Recheck durável e incremental sem reset em massa. Escrita apenas dos campos técnicos da lease sem validar conteúdo legado. |
| `app/jobs/email_campaigns/recipient_preflight_job.rb` | Publica cada resultado sob holder/token/expiry/import/status e CAS do recipient. Enqueues aguardam commit externo. DNS e classificação seguem fora desses locks. |
| `app/services/email_campaigns/preflight_decision.rb` | Ajuste necessário para tornar o recheck incremental seguro: `preflight_summary.rechecking` invalida evidência antiga em enforce, tanto no claim quanto no gate de campanha. Não altera `pause!` nem a correção de isolamento que pertence ao PR0. |
| `app/jobs/email_campaigns/direct_inbox/tick_job.rb` | Preserva promoção condicional do agente SNS e adia construção/execução do engine até commit externo. |
| `app/services/email_campaigns/scheduler.rb` | Preserva entrada ordenada e rescue do parent; enqueue após commit externo. |
| `spec/services/email_campaigns/cross_caller_lock_concurrency_spec.rb` | Novo: nove regressões de fronteiras concorrentes e commit/rollback. |
| `spec/jobs/email_campaigns/preflight_lock_closure_spec.rb` | Novo: oito regressões de lease/recheck/SQL/commit/dirty tracking/scheduler. |
| `spec/jobs/email_campaigns/direct_inbox/tick_transition_spec.rb` | Acrescenta dois casos de transação externa: engine após commit, nunca após rollback. Casos anteriores mantidos. |
| `docs/audit/436-cross-caller-closure.md` | Este registro. |

Total: **13 arquivos de aplicação, três specs e um audit**. Não houve edição de Account, evaluator ou seu spec, SNS/EmailEvent, schema/migrações, UI, reports, CI, import-issue encoding, configuração operacional ou artefatos do PR0 separado.

## Protocolos e revisão de todos os chamadores

Foram lidos AGENTS, `436-pr1-integration.md`, `436-feedback-integration.md` e buscados todos os `with_delivery_lock`, `with_delivery_locks`, `refresh_counters!`, escritores de EmailEvent e SuppressionRegistry em app/lib/enterprise. A busca não encontrou overlay Enterprise correspondente.

- **Admissão, transições, scheduler, tick, upload/retry e preflight:** conta → estado existente → campanha → recipient quando necessário. SNS nocivo conserva seu wrapper que cria/trava estado antes do recipient; a invalidação da geração continua no before_save, na mesma transação do feedback. Nenhuma proteção foi movida exclusivamente para after_commit.
- **Unsubscribe:** conta → estado existente → campanha → recipient → registry/state de supressão/legado. A nova entrada do registry relê/trava a mesma conta já possuída pelo chamador; não introduz espera por um novo pai após o recipient. Evento, supressão permanente e estado unsubscribed são atômicos. Precedência forte e dedup mantidos.
- **Registry avulso:** conta → suppression state → legado; não toma recipient/campaign depois. Evita que um escritor avulso segure suppression state enquanto espera a FK da conta que SNS/admission já possuem.
- **Import atômico:** primeiro o job marca processing em transação curta só do import. Parsing/download ocorrem sem transação. O bloco de escrita reserva `campaign FOR KEY SHARE` → import NOWAIT → novos recipients/issues (lotes de 500). Esse ramo não escreve campanha nem adquire conta/estado. O importer direto também reserva a FK da campanha antes dos filhos. O lock da FK é compatível com a finalidade de inserção; nenhum lock da admissão foi enfraquecido. Contadores e enqueue só podem procurar conta/estado depois de liberar a transação externa inteira.
- **Contadores:** o ponto compartilhado registra a coleta e persistência para depois de todas as transações externas. Assim, o import, SNS Delivery e tracking não podem conservar filhos enquanto buscam a conta. Fora de transação, continua síncrono. Rollback não publica nada. Os contadores continuam um snapshot, sem autorizar envio.
- **Preflight:** DNS/classificação fora dos locks; cada resultado usa bloco curto conta → estado → campanha e update condicional de um recipient ainda pending, com checked_at esperado. A lease precisa continuar válida e própria, sem import ativo e campanha terminal. Advance coleta summary fora do bloco, readquire na ordem e revalida token/expiry antes de publicar. Não há reset de 50 mil recipients sob conta.
- **Recheck explícito:** publica `preflight_summary.rechecking=true` atomicamente com token/cursor/ceiling. Isso invalida os resultados anteriores para admissão em enforce sem escrever a lista inteira. O job percorre todos os pending até o ceiling em lotes de até 100 e orçamento de domínio/tempo existente. O marcador sobrevive a crash/expiry; recuperação usa o cursor durável. Só o holder atual conclui o passe e substitui o marcador pelo summary. Shadow/warning mantêm seu comportamento de não bloquear.
- **Recuperação de campanha legado-inválida:** lease/cursor/ceiling/summary usam update_columns dentro dos locks, sem tentar validar subject/body/sender antigos. Não se alteram status, conteúdo ou gates de envio. Expiry e manutenção continuam recuperando o passe.
- **Tracking e SNS Delivery:** podem usar apenas recipient porque não adquirem novos pais nesse bloco. Tracking agora relê status, preservando opt-out concorrente; ambos chegam ao lock de conta dos contadores apenas após commit.
- **Recibos SES/DirectInbox e falhas:** revisados, mantêm entrada ordenada existente e só a instância dona do claim trata falha. Recibo grava os campos de aceite e conserva unsubscribed. Delivered direto não regride opt-out.
- **Cancelamento/finalização:** preservados os lotes e o fence de estado do parent; o ponto compartilhado dos contadores agora também protege chamadas sob transação externa. Controller continua `cancel! == false`, schedule continua `schedule!`, destroy continua `with_delivery_lock`.
- **Manutenção/falha de import:** blocos só do import não passam a adquirir pais. A recuperação já enfileirava depois de liberar seu lock. Nenhum callback genérico de save/lock/reload foi introduzido.
- **Disposal:** nenhum novo dependent/FK/audit mutável foi criado. As referências lógicas dos audits e cascades existentes permanecem; teardown dos novos testes também exercita exclusão de conta com supressão/reputação. A prova específica continua incluindo o spec de retention existente na execução do parent.

## Regressões preparadas — não executadas

Os novos specs têm fixtures transacionais desativadas. Concorrência usa conexões com PIDs distintos, Queue, `pg_blocking_pids`, lock_timeout e join limitados. Não substituem locks por mocks. Testes do endpoint usam token assinado e sessão HTTP interna do Rails. O único substituto de classificação no caso concorrente evita DNS real e registra que a chamada ocorreu sem transação.

- Link atrás de admission, no mesmo recipient; endpoint conclui opt-out e recibo posterior conserva status permanente.
- Link ganha o lock antes de complaint; feedback invalida versão e não rebaixa unsubscribe; outro envio ao mesmo endereço é recusado.
- Registry avulso concorrente com SNS sobre suppression state já existente, sem ciclo entre locks de filhos diferentes.
- Import ativo inserindo enquanto claim espera a FK da campanha; conclusão atômica libera os filhos antes de contadores/admission disputarem conta. Parsing é observado fora da transação.
- Import processing ainda no parsing recusa claim, sem precisar de lock de filho.
- Commit de evidência de preflight antes de claim concorrente que espera a conta.
- Contadores aguardam commit externo e são descartados no rollback.
- Tracking com recipient previamente carregado não apaga opt-out do endpoint.
- Recheck de 101 recipients: bloqueio imediato da evidência antiga, 100 processados por job, evidência antiga restante ainda recusada, recuperação no cursor após expiry.
- Resultado e summary de token antigo não substituem o holder atual.
- Sequência SQL de acquire/claim/persist/advance é conta → estado → campanha; agregação fora da transação.
- Campanha com subject/body inválidos mantém recuperação técnica limitada.
- Enqueue de preflight após commit externo, nunca após rollback.
- Completed seguido de reload ainda enfileira apenas após commit; rollback não enfileira.
- Scheduler e Tick respeitam commit externo; Tick não constrói/chama engine no rollback.

São **19 exemplos novos**, ainda sem resultado Rails. Nenhum exemplo anterior foi removido, marcado pending/skip ou teve assertion reduzida.

## Validação efetivamente executada

Com Ruby inicializado por `eval "$(rbenv init -)"`:

1. `ruby -c` em cada um dos 16 arquivos Ruby do manifesto: **16 Syntax OK**.
2. `bundle exec rubocop --cache false` nesses mesmos 16 arquivos: **16 files inspected, no offenses detected**. Rodadas anteriores corrigiram formatação, exists? e diretivas locais de complexidade/assertions nos novos casos de fronteira. Autocorreção limitada aos arquivos do manifesto.
3. Revisão estática dos locks/FKs/callbacks/callers e busca de marcadores nos arquivos novos de preflight/specs: nenhum conflito encontrado. Leitura da implementação local do Rails 7.2 de `after_all_transactions_commit` confirmou adiamento ao commit externo e descarte no rollback, sem carregar Rails.

Não foram executados testes puros, Rails/RSpec, banco/migração, serviços/provedores, chamadas externas, instalação, Git ou mudanças de env real.

## Handoff e limitações restantes

- **A evidência de runtime está pendente:** parent deve executar os 247+ anteriores, concorrência e bounded admission no PostgreSQL isolado, incluindo os dois specs novos e o tick atualizado. Sintaxe/lint não provam ausência de deadlock.
- O ajuste de `preflight_decision.rb` é necessário para a invalidação imediata com recheck incremental; preservar esse gate ao integrar as três correções do PR0 separado. `pause!` e encoding de issues não foram editados aqui.
- O import continua uma transação atômica longa para recipients/issues/completed. Não segura conta/estado, mas seu `FOR KEY SHARE` de campanha pode fazer um chamador que requer `FOR UPDATE` esperar o commit; enquanto espera, esse chamador pode reter sua conta. Não há aquisição inversa pelo import para fechar ciclo. Não foi introduzido staging/chunk commit ou relaxado o contrato atômico para eliminar essa espera; medir duração no teste real se necessário.
- Contadores agora são derivados pós-commit: falha nessa publicação não desfaz recipients/completion/opt-out. Eles podem ficar desatualizados até nova atualização. Autorizações dependem das linhas/fences atuais, não dos contadores. Lease/outbox durável conserva recuperação de enqueue perdido.
- O summary é um retrato, não uma leitura serializável dos recipients; o token impede publicação por holder antigo. A autorização sempre consulta os gates atuais.
- Transporte já admitido não é recolhido por um opt-out posterior; seu recibo deve continuar preservando unsubscribed.
- A revisão estática não encontrou outro ciclo concreto nos caminhos implementados acima. Não abrange novos chamadores futuros que entrem por um lock de filho antes dos wrappers. Não se carregou preview/backfill de PR posterior e não se alterou infraestrutura.

Comando adicional para o parent, além do conjunto integrado já sob sua responsabilidade:

```sh
bundle exec rspec spec/services/email_campaigns/cross_caller_lock_concurrency_spec.rb spec/jobs/email_campaigns/preflight_lock_closure_spec.rb spec/jobs/email_campaigns/direct_inbox/tick_transition_spec.rb spec/jobs/email_campaigns/recipient_import_job_spec.rb spec/jobs/email_campaigns/recipient_preflight_commit_spec.rb spec/jobs/email_campaigns/recipient_preflight_lease_spec.rb spec/services/email_campaigns/feedback_integration_concurrency_spec.rb spec/services/email_campaigns/reputation/retention_spec.rb
```

Este comando é handoff, não uma execução realizada nesta rodada. Aguardar resultados reais para correções focadas; sem alegação de readiness.
