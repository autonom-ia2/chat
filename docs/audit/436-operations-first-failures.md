# #436 — correções das falhas de operations-first

Data: 2026-09-17. Correções locais de specs; **rerun Rails/RSpec pelo parent pendente**. Nenhuma declaração de suíte verde, PR pronto ou autorização de merge/deploy.

## Evidência recebida e diagnóstico

Lidos `AGENTS.md`, fontes/specs de operações, padrões de requests autenticados do repositório e os dois artefatos reais `tmp/email436/operations-first.json` e `tmp/email436/operations-first.log`. O JSON registra **108 exemplos, 9 falhas, 0 pendências e 0 erros fora de exemplos**. Esses números pertencem à execução anterior do parent, não ao código corrigido.

| Falhas do log | Causa observada | Correção local |
| --- | --- | --- |
| 1, HistoricalProtectionBackfill, linha original 121 | Segunda campanha na mesma conta criava outra identidade com o mesmo domínio da factory | Passar `campaign.sender_identity` à segunda campanha; preservar reimportação e precedência unsubscribe |
| 2–3, Start, linhas originais 35 e 46 | Fixture lazy do ator produzia jobs de usuário dentro da janela que deveria observar apenas Start | Materializar ator/conta com `let!` e limpar a fila antes do exemplo; manter fila vazia dentro da transação e após rollback; exigir exatamente um job do run após commit |
| 4, Start, linha original 65 | `delete_all` do vínculo seguido de recriação deixava a configuração de notificação existente e colidia com `by_account_user` | Testar conta suspensa com vínculo existente, reativar a conta e revogar com `destroy!`; não recriar vínculo nem alterar callbacks/regras de limpeza |
| 5–9, MaintenanceController | `sign_in` no harness de controller não autenticava a API; resposta real era 401 antes da autorização/validação | Manter os oito casos no mesmo arquivo, mudar para `type: :request`, rotas HTTP reais e `create_new_auth_token`, padrão já usado pelos requests que passaram |

Negativas HTTP agora verificam controle positivo: administrador comum acessa a própria conta com 200 antes da negação; a resposta 401 precisa conter a mensagem real de Pundit. O caso de run estrangeiro cria/lê o run próprio antes de esperar 404. Outro SuperAdmin lê o run com 200 antes de receber `actor_mismatch` no retry. O caso sem autenticação continua sem cabeçalhos. Não há stub de autenticação/autorização.

## Correção e cobertura mantida

- Nenhum exemplo removido, novo skip, pending ou expectativa desativada. Os casos de aceitação e request boundary recebidos permanecem intactos.
- Matriz existente de nove bounces agora executa preview antes de apply, exige zero registros nas três tabelas de proteção no preview e compara contagens de classificação: elegíveis, temporários e desconhecidos. Contagens de gravação/proteção já existente têm semântica distinta em apply e não são forçadas a coincidir.
- Preview existente também proíbe construção de `Mail` e `EmailCampaigns::Ses::Client`. Não introduz consulta/envio ao provedor.
- Fontes de operações revisadas e preservadas: confirmação exata, flag, tipo persistido SuperAdmin e acesso atual à conta ativa; cursor/horizonte/batch/lease, publicação após commit e limites de três tentativas/retries. Registry e prioridade continuam compartilhados, sem escrita alternativa.
- `ComplaintClassifier` final está presente neste worktree e foi lido; Evidence usa seu contrato real para PREVENTED. Sem fallback ou mock substituto. Unknown bounce continua sem inventar mailbox inválida; Complaint PREVENTED continua provider_suppression, sem criar spam. Idempotência, rollback atômico e retomada de cursor mantêm os casos existentes.
- Parent informou schema isolado atualizado com `retry_count`; banco não foi acessado nesta rodada. A antiga pendência de integração do helper em `436-operations-integration.md` é histórica e não é tratada como bloqueio atual.

## Manifesto exato desta rodada — quatro arquivos

1. `spec/services/email_campaigns/maintenance/start_spec.rb`
2. `spec/services/email_campaigns/maintenance/historical_protection_backfill_spec.rb`
3. `spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb`
4. `docs/audit/436-operations-first-failures.md` — novo registro.

Nenhuma edição em fontes de produção, auth central, factories globais, reputação, delivery, UI, migrations/schema, flags, README, outros worktrees ou documentos históricos. Sem Git, Rails/RSpec, banco, rede, secrets, instalação ou operações de produção.

## Validação estática executada

RuboCop sem autocorreção, exit 0: **25 files inspected, no offenses detected**.

```sh
eval "$(rbenv init - zsh)"
RBENV_VERSION=3.4.4 RUBOCOP_CACHE_ROOT=/private/tmp/email436-operations-failures-rubocop bundle exec rubocop \
  app/services/email_campaigns/maintenance \
  app/models/email_protection_maintenance_run.rb \
  app/jobs/email_campaigns/protection_backfill_job.rb \
  app/jobs/email_campaigns/protection_backfill_reconcile_job.rb \
  app/controllers/api/v1/accounts/email_campaigns/maintenance_controller.rb \
  app/policies/email_protection_maintenance_policy.rb \
  spec/services/email_campaigns/maintenance \
  spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_acceptance_spec.rb --format simple
```

Compilação estática com `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby -rdigest -` via STDIN: expandir os diretórios do comando acima em `**/*.rb`, ordenar os 25 arquivos e chamar `RubyVM::InstructionSequence.compile_file` em cada um. **25 Ruby files compiled without execution**, exit 0. Nenhum boot Rails ou execução de specs.

SHA256 do conjunto ordenado, `files.map { |path| "#{path}\0#{File.binread(path)}" }.join("\0")`: `623757e3a47896098678704028065f94dc1c7c1d38cacce27900c1c49abea7a1`.

| Spec editado | SHA256 |
| --- | --- |
| start_spec.rb | `b457c71f1e4334b44b9e4e453918126678565e139b5bdda1db1665618389124b` |
| historical_protection_backfill_spec.rb | `4d9f2446c992a31a6eebf7c8036068ce88a29688c169eb1c17664c23bb36ff35` |
| maintenance_controller_spec.rb | `bf2e19637dfc9d361162c54b90e1d1472cbe461818ecb06f15a726a7a77f81c7` |

## Handoff

Parent deve repetir a suíte original completa no harness isolado já preparado, incluindo os nove casos que falharam e a matriz ampliada. O arquivo sob `spec/controllers/` continua na seleção original, embora use agora o harness `type: :request`, como outros specs HTTP do repositório. Lint/compilação não comprovam autenticação, callbacks, concorrência ou persistência; o fechamento das nove falhas depende do próximo resultado runtime.
