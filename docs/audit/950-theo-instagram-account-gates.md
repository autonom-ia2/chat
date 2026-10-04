# #950 — fechamento de flag, reautorização e UI por conta

Branch `feat/950-instagram-admin-panel`, base `11b41b1030`, 2026-10-04.
Brief lido: `tmp/950-integration/brief.md`. Trabalho anterior preservado.

## Entrega

- Feature `instagram_assisted_onboarding` permanece no último bit de `feature_flags_ext_1`, default ON. Nenhuma migration, coluna ou bit antigo alterado. O teste com Account real exercita o sync normal de ConfigLoader: nova entrada ON para novas contas, nenhum rewrite de flags das existentes. ConfigLoader continua preservando defaults já cadastrados; não forçar sync.
- OFF conserva OAuth direto e não consulta o tester. ON exige seleção aceita, sem fallback, tanto no criador de inbox quanto no onboarding (`InboxSetup.vue`, diálogo de canais e `useChannelConnect`). O fluxo assistido compartilhado leva `return_to=onboarding` até o OAuth. Canal negado e restrição Meta bloqueiam o início; ativar a feature não concede `channel_instagram`.
- Reautorização: `inbox_id` Integer positivo explícito, mesma conta, canal Instagram e `inbox_manage`. `return_to=inbox` sozinho não desvia o gate. O state assina inbox e ID de usuário do Instagram. Após os requests ao provider, o callback abre transação, trava conta/membership/inbox/canal e compara os IDs assinados antes de substituir credenciais. Remoção, transferência de inbox ou mudança de identidade durante os requests aborta a gravação. Nenhuma alteração em auth global.
- EE usa AccountFeaturesField/all_features existente, uma única checkbox. Corrigida a leitura de valores `true`/`false` dos checkboxes: contar somente as chaves também contava hidden fields OFF. OSS usa um campo específico no AccountDashboard com checkbox nativa. Atualização administrativa salva flag e marcador de rollout no mesmo lock/transação, inclusive OFF antes da primeira tarefa. Edições sem o controle não criam marcador.
- Copy em `config/locales/instagram_account_feature.en.yml` e `.pt_BR.yml`; não editados `en.yml`, `pt_BR.yml`, metadata, controller de automação ou `config/routes.rb` nesta frente.
- Task Rhea mantida: dry-run padrão, confirmação exata, rechecagem dentro de lock, marcador idempotente. Specs do service substituídos por Account/ActiveRecord reais, incluindo rollback. Specs da task continuam validando parsing/delegação sem banco.

## Rota para o parent

Nenhuma rota nova necessária: o campo OSS e o formulário EE usam a action update existente. Trecho já existente em `config/routes.rb`, dentro de `namespace :super_admin`:

```ruby
resources :accounts, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
  # member actions existentes permanecem aqui
end
```

Contrato usado: `PATCH /super_admin/accounts/:id` → `SuperAdmin::AccountsController#update`.
Não duplicar rota nem adicionar endpoint de toggle à mesma feature.

## Evidência local

- Vitest: **6 arquivos, 107 testes, 0 falhas**. Log `tmp/950-integration/theo-final-vitest.log`.
- RuboCop: **18 arquivos, 0 offenses**. Log `tmp/950-integration/theo-final-rubocop.log`.
- ESLint: **0 erros, 47 avisos** de i18n (catálogos/dynamic keys). Log `tmp/950-integration/theo-final-eslint.log`.
- `node scripts/check-fork-i18n.mjs`: **10 catálogos, 17422 mensagens**, en/pt_BR e parâmetros cobertos. Log `tmp/950-integration/theo-final-i18n.log`.
- `git diff --check` focado aprovado.
- Prettier aplicado somente aos arquivos frontend focados, diff relido, Vitest repetido após as correções.

## Rails pendente — coordinator executa serialmente

Nenhum teste Rails/DB executado nesta finalização, por instrução do brief e do Rodrigo. Não reutilizar o resultado anterior de 13 specs offline como prova dos novos specs ActiveRecord.

Após ativar o Ruby correto, usar exclusivamente o wrapper e serviços de teste do coordinator:

```bash
tmp/950-integration/run-local.sh bundle exec rspec \
  spec/models/concerns/featurable_spec.rb \
  spec/services/instagram/automation/account_rollout_spec.rb \
  spec/lib/tasks/rake/task_instagram_account_rollout_spec.rb \
  spec/requests/super_admin/instagram_account_feature_spec.rb \
  spec/controllers/super_admin/accounts_controller_spec.rb \
  spec/requests/api/v1/accounts/instagram/tester_authorization_spec.rb \
  spec/requests/api/v1/accounts/instagram/testers_spec.rb \
  spec/controllers/instagram/callbacks_controller_spec.rb \
  spec/services/instagram/testers/oauth_binding_spec.rb \
  spec/services/instagram/testers/configuration_spec.rb \
  spec/helpers/instagram/integration_helper_spec.rb --format progress
```

Rodar os requests da UI em EE e também em um boot OSS com `DISABLE_ENTERPRISE=true` no ambiente de teste isolado. AccountDashboard define os campos no carregamento; stub tardio de enterprise? não prova a edição OSS. Novos testes: default real via ConfigLoader, rollout/rollback/idempotência real, OFF administrativo antes/entre rollouts, save inválido sem marcador persistido, isolamento do entitlement e requests OAuth/reauth.

Guia: parent deve gerar/checkar formatos após este controller gate/params, conforme processo do repo. Não editados gerados à mão. PR/Project, review e integração final permanecem com parent; sem commit, push, merge, deploy ou operação real.

## Operação e rollback (não executados)

Bit 0 antigo SEM marcador continua ambíguo: ausência histórica da feature e OFF manual antigo são indistinguíveis. Rollout aplicado a essas contas requer operação revisada/aprovada; decisões OFF feitas pelo novo formulário recebem marcador e são preservadas desde antes da primeira execução. Não inferir consentimento apenas a partir do bit.

Preview: `bundle exec rake instagram:rollout_assisted_onboarding`.
Aplicação, somente com aprovação do Rodrigo para o ambiente: `DRY_RUN=false INSTAGRAM_ROLLOUT_CONFIRM=instagram_assisted_onboarding bundle exec rake instagram:rollout_assisted_onboarding`.
Rollback: OFF pelo SuperAdmin, mantendo marcador; reexecução não religa. Nenhum rollout, sync ou rollback foi executado.

## Correção residual round2 — fixtures e contrato, sem mudança de produto

Revisado `rails-integration-round2.log` (557 exemplos, 10 falhas). Alterados somente os quatro specs focados: `spec/controllers/api/v1/accounts/instagram/authorizations_controller_spec.rb`, `spec/enterprise/services/instagram/testers/oauth_binding_spec.rb`, `spec/requests/api/v1/accounts/instagram/tester_authorization_spec.rb` e `spec/services/instagram/testers/configuration_spec.rb`. Fixtures de OAuth direto agora habilitam explicitamente `channel_instagram` e desligam `instagram_assisted_onboarding`; o caso de hint legado desliga a flag real da conta. Adicionados negativos para canal negado no request legado, no binding Enterprise e na configuração.

O 401 de agente foi confirmado como negação de permissão, não falha de autenticação: `OauthAuthorizationController#check_authorization` chama `check_permission_granted!`, e `RequestExceptionHandler` transforma `Pundit::NotAuthorizedError` em 401 com mensagem própria. O teste verifica membership real sem `inbox_manage`, resposta exata e ausência de preparo tester. Guards mantidos.

Configuration mantém snapshot de metadata por operação: ao mudar ENV, o novo leitor fica indisponível; o leitor já inicializado continua disponível com doc ID anterior, verificado explicitamente.

Slot serial confirmado livre após término de `local-status-control.log`, sem outro RSpec no processo local. Rodados somente esses quatro specs pelo `tmp/950-integration/run-local.sh`, loopback de teste 59510/59511. Resultado: **42 exemplos, 0 falhas** (9,05 s de execução). Receipt: `tmp/950-integration/theo-round2-focus.log`; RuboCop focal: `tmp/950-integration/theo-round2-lint.log`, 4 arquivos sem offenses. `git diff --check` focado aprovado. Sem produto, LocalStatus, cache, framework, CI, produção, APIs reais ou secrets alterados.

## Checkbox EE acessível — caso browser 14

Alteração exclusiva no ramo regular de `enterprise/app/views/fields/account_features_field/_form.html.erb`: somente `feature_key == 'instagram_assisted_onboarding'` troca span por Rails `label('enabled_features', "feature_#{feature_key}", display_name, ...)`, usando o mesmo object/method do checkbox para gerar `for` correspondente ao id. Typography original mantida; `flex min-h-11 min-w-11 flex-1 items-center cursor-pointer` dá ao label alvo mínimo de 44 px. Demais features e regras premium intactas. OSS já tinha `f.label` associado e não mudou.

`spec/requests/super_admin/instagram_account_feature_spec.rb`: quatro exemplos adicionais verificam DOM em en/pt_BR, label[for] → checkbox[id], nome legível, checkbox única e OFF + marcador persistido. O mesmo spec cobre EE ou OSS conforme boot real; asserts anteriores permanecem. Parent deve executar esse arquivo depois do browser QA em ambos os boots; nenhum request/DB foi executado neste slot com Vega ativo.

Verificação local: ERB compilado por RubyVM sem Rails/DB, syntax OK; RuboCop focal registrado em `tmp/950-integration/theo-label-lint.log`; git diff --check focal aprovado. Harness e produto fora desse label não alterados.
