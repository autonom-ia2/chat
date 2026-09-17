# #436 / PR1 — correções dos dois P1s, 2026-09-17

Correções implementadas localmente; **runtime Rails/SQL e CI pós-correção ainda pendentes do parent**. Não declarar pronto para merge/deploy. Escopo limitado ao review `tmp/email436/pr1-final-review.md`, fontes locais e semântica AWS fornecida pelo parent. Nenhum teste anterior foi removido ou substituído.

## Evidência de partida

Lido `tmp/email436/rebased-clean-rspec.json`: **461 exemplos, zero falhas, um pending**, zero erros fora dos exemplos. Pending: `Account has_many autonomia_account_links`, `spec/models/account_spec.rb`, quarentena preexistente. Essa execução ocorreu após limpeza das fixtures sintéticas e **substitui** o JSON anterior de banco sujo mencionado no review. Não comprova estas novas alterações.

Lidos AGENTS.md, review, `EmailReputationState`, `EmailEvent`, Observation/Queue/Evaluator/Metrics/Policy, SNS EventProcessor, SuppressionRegistry, Admission, campaign/recipient e specs relacionados. Busca em `app` e `enterprise` não encontrou overlay equivalente nem outro escritor de bounce/complaint de produção além do SNS neste escopo.

## P1 — Complaint de prevenção não é reclamação nova

- `OnAccountSuppressionList` e `OnTenantSuppressionList` em `complaintSubType` passam a ser prevenção, conforme `notification-contents` e `sending-email-suppression-list`, verificados pelo parent em 17/09 e fornecidos na tarefa. Não houve verificação de rede nesta rodada.
- Um classificador público define o conjunto e os predicados Ruby/SQL. Metrics usa o mesmo SQL para `complaints` e fingerprint nocivo. `provider_prevented` passa a incluir prevenção de bounce **ou** complaint, deduplicada por destinatário na mesma coorte. `sent` conserva o aceite local como denominador.
- SNS conserva `EmailEvent` bruto e enum atual; grava a razão forte existente `provider_suppression` no registro e espelho duráveis, bloqueando nova admissão. Status passa a `suppressed`, sem substituir `unsubscribed`/`complained` nem reduzir a prioridade de supressões existentes. A atualização de status usa a mesma estratégia sem validação de campos legados dos demais outcomes SNS.
- Missing/null/unknown continuam reclamação real. O filtro não foi aplicado a subtipos de bounce por analogia: `Permanent/Suppressed` permanece nocivo; `NoEmail` e `General` continuam falhas permanentes genéricas.
- Sem alteração de enum, API AWS, Policy, limiares, gate global ou deduplicação existente por dispatch/tipo. Sem novo alerta, pausa ou revogação por prevenção; a versão de feedback ainda avança atomicamente para uma nova evidência aceita.

### Contrato exato para o parent, relatórios e backfill

Arquivo novo: `app/services/email_campaigns/complaint_classifier.rb`, classe `EmailCampaigns::ComplaintClassifier`.

| Nome público | Contrato |
| --- | --- |
| `PREVENTED_SUBTYPES` | Array congelado: `OnAccountSuppressionList`, `OnTenantSuppressionList` |
| `.provider_prevented?(complaint)` | Recebe objeto complaint com chaves string ou nil; true somente nos dois subtipos |
| `.real_complaint?(complaint)` | Complemento do anterior; chamar somente para eventos Complaint |
| `PREVENTED_SUBTYPE_SQL` | `COALESCE(payload #>> '{complaint,complaintSubType}', '') IN ('OnAccountSuppressionList', 'OnTenantSuppressionList')` |
| `PROVIDER_PREVENTED_SQL` | `event_type = 4 AND (<PREVENTED_SUBTYPE_SQL>)` |
| `REAL_COMPLAINT_SQL` | `event_type = 4 AND NOT (<PREVENTED_SUBTYPE_SQL>)` |

Ruby recebe o objeto interno, **não** o envelope SNS. SQL usa as colunas `payload` e `event_type` de `email_events` sem qualificação: aplicar em relação sem nomes ambíguos. SQL preserva missing/null via COALESCE. As strings SQL são geradas a partir do único array de subtipos; não copiar listas para os consumidores.

`EmailCampaigns::Reputation::Metrics::COUNT_FILTERS[:complaints]` referencia `REAL_COMPLAINT_SQL`; `#harmful_feedback_fingerprint` aplica o mesmo predicado no conjunto nocivo de todo o histórico aceito. `COUNT_FILTERS[:provider_prevented]` agrega as duas famílias de prevenção, mantendo as outras chaves e as regras de bounce.

**Pendência de integração identificada:** o `EmailCampaign#event_counters` desta worktree ainda calcula `complained` via contagem bruta do enum, usada por `#counter_attributes`/`#refresh_counters!` para persistir `complained_count`. Está fora do ownership autorizado. O parent deve propagar `REAL_COMPLAINT_SQL` para esse contador e para os relatórios em `436-reports-integration`, preservando a deduplicação própria de cada relatório e separando prevenção. Sem isso, esse contador ainda pode apresentar prevenção como nova reclamação. Não foi alterada outra worktree nem executado backfill.

## P1 — primeira criação de estado sem ciclo Account/FK/chave única

`EmailReputationState.for_account(account_id)` conserva `find_by` rápido para estado existente. Na ausência, executa `Account.find(account_id).with_lock { create_or_find_by!(account_id: account_id) }`. O INSERT/chave única/FK só ocorre depois do lock da conta. A restrição única continua arbitrando a existência de uma única linha.

Chamadores inspecionados:

- `Observation#collect`: primeira criação antes do lock de estado; reserva geração em transação curta e coleta métricas/fingerprint depois da liberação. A publicação posterior é Account → state, sem manter lock da coleta.
- `EvaluationQueue.invalidate/request`: nenhum filho previamente travado nos caminhos avulsos; trava/atualiza somente estado quando ele já existe. `request` agenda depois do bloco de estado; `finish` não cria estado e não adquire Account.
- `EmailEvent`/SNS: escritor composto entra por `with_recipient_feedback_locks`, Account → state → campaign → recipient. Estado já existe quando o callback de feedback roda. Criação avulsa invalida em `before_save`, antes do INSERT e FK do evento. Tracking/opt-out/DirectInbox não criam estado de reputação por esse callback.
- Não foi encontrado chamador de produção criando feedback dentro de lock de filho fora do wrapper composto. Um novo chamador desse tipo deverá usar o wrapper antes do filho; não se autoriza inversão pelo novo caminho de criação.

Invalidação permanece **dentro da transação, antes da gravação**. Não houve deslocamento para somente after_commit, coleta pesada sob Account/state, rescue global, resposta 200 nova ou descarte silencioso.

## Regressões adicionadas, aguardando runtime do parent

- SQL/Policy: os dois subtipos, contagem separada, duplicatas, fingerprint estável, ausência de falso limiar de 0,1%, alerta/pausa nos três modos; complaint real a 0,1% continua bloqueando.
- Fingerprint de histórico: prevenção tardia não revoga override nem altera snapshot; reclamação real tardia revoga. Missing/objeto null/subtipo null/desconhecido contam e duplicatas estabilizam o hash.
- SNS: preservação do payload, uma ocorrência/versão em replays, supressão durável mesmo com campo legado inválido, precedência de descadastro/reclamação, bloqueio da próxima admissão e zero HTTP.
- Concorrência determinística: reutiliza helpers com duas conexões/PIDs reais, `pg_blocking_pids`, `pg_stat_activity`, lock_timeout e joins limitados. Sessão A segura Account sem estado; sessão B avalia e bloqueia; A processa SNS antes de liberar. O original esperaria no INSERT enquanto A tentaria a mesma chave única; o corrigido espera em `SELECT ... accounts ... FOR UPDATE`. Verifica linha única, evento, feedback_version, observation_generation, evaluated_feedback_version e snapshot publicado. Casos equivalentes cobrem Queue.invalidate/request. O teste anterior de criação avulsa de EmailEvent foi mantido integralmente.

## Validação executada nesta rodada

Antes dos comandos Ruby/Bundler: `eval "$(rbenv init -)"`. Sem Rails boot, RSpec, banco ou rede.

1. `ruby -c` nos oito arquivos Ruby do manifesto: **oito Syntax OK**. A primeira invocação do loop falhou no shell (`ruby` não encontrado por colisão da variável `path` do zsh); corrigido o nome da variável para `ruby_file`, execução completa aprovada.
2. `bundle exec ruby spec/pure/email_campaigns/complaint_reputation_test.rb`: **5 runs, 30 assertions, 0 failures, 0 errors, 0 skips**, execução final seed 5183. Testa classificadores reais, Policy e LegacyDecision, sem Rails nem clientes externos.
3. `RUBOCOP_CACHE_ROOT=/private/tmp/email436-pr1-rubocop bundle exec rubocop` com os oito arquivos Ruby abaixo e `--format simple`: **8 files inspected, no offenses detected**. Quatro apontamentos iniciais de estilo/spec foram resolvidos; nenhuma configuração global de lint alterada.
4. Leitura do JSON limpo para confirmar resumo e pending preexistente; `git --no-optional-locks diff` apenas para revisão de leitura dos três arquivos de produção já rastreados.

Não executados: git writes, Rails/RSpec/DB, migrações, SSH/AWS/SMTP/HTTP, instalações, leitura de env real, merge ou deploy. Asserções SQL e WebMock nos specs são cobertura **escrita**, não resultado de runtime desta rodada. Parent deve executar o conjunto preservado mais regressões novas no ambiente isolado, propagar o contrato de reports/contadores e obter CI/review antes de aprovação.

## Manifesto exato desta rodada — 10 arquivos

```text
app/models/email_reputation_state.rb
app/services/email_campaigns/complaint_classifier.rb
app/services/email_campaigns/reputation/metrics.rb
app/services/email_campaigns/sns/event_processor.rb
spec/pure/email_campaigns/complaint_reputation_test.rb
spec/services/email_campaigns/feedback_integration_concurrency_spec.rb
spec/services/email_campaigns/reputation/complaint_metrics_spec.rb
spec/services/email_campaigns/sns/event_processor_spec.rb
docs/audit/436-pr1-review-fixes.md
docs/email-campaigns/reputation.md
```

Nenhuma atualização de Issue/PR/Project nesta rodada restrita a arquivos locais. Parent conduz a etapa seguinte do fluxo de entrega. Não há migração nova nem operação de dados para desfazer; eventual rollback de aplicação não deve apagar eventos, supressões ou auditorias. Retornar ao código anterior reintroduz os dois P1s e exige plano operacional aprovado.

## Gate final do integrador — 17/09/2026

Schema reconstruído exclusivamente no PostgreSQL sintético loopback15436, Redis loopback16436 e ambiente isolado sem credenciais herdadas. O carregador padrão restaurou os guards SQL. O conjunto cumulativo higiene + reputação + concorrência + retenção + baseline executou **488 exemplos RSpec, zero falhas**, com **um pending preexistente** em `Account has_many autonomia_account_links`. Nenhum teste novo foi ignorado. Fonte reproduzível: seletor `.github/scripts/email-protection-files.py rspec`; relatório local `tmp/email436/pr1-closed-rspec.json`.

Sete suítes puras separadas: **38 testes, 50.733 asserções, zero falhas/erros/skips**. Dois doubles offline antigos foram alinhados aos contratos introduzidos (marcador de recheck e bloco FOR KEY SHARE), mantendo simulação atômica e todas as verificações originais. Isso não altera o produto nem substitui os testes PostgreSQL. Log: `tmp/email436/pr1-closed-pure.log`.

RuboCop cumulativo: **121 arquivos, nenhuma infração**; os dois testes puros alterados depois também passaram em lint. O contador persistido de reclamações da campanha agora usa `ComplaintClassifier::REAL_COMPLAINT_SQL`, com teste de prevenção mantendo contador e taxa zero. Relatórios/backfill devem reutilizar o mesmo classificador nas próximas PRs.

Sem acesso à produção, envio real, alteração operacional de flags, merge ou deploy. CI remoto e revisão de fechamento são gates separados, a conferir no SHA publicado.
