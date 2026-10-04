# Issue #950 — rollout explícito de contas existentes (Rhea)

> Atualização da integração final (2026-10-04): o formulário SuperAdmin agora persiste o marcador junto da decisão ON/OFF, sob lock/transação, protegendo também OFF manual anterior à primeira tarefa. Bit 0 histórico sem marcador continua ambíguo e exige operação aprovada. Os specs offline do service descritos abaixo foram substituídos por specs com Account/ActiveRecord real, ainda pendentes de execução pelo coordinator. Os 13 exemplos abaixo são apenas evidência histórica, não validação da versão final. Ver `docs/audit/950-theo-instagram-account-gates.md`.

## Decisão

Um único ponto operacional: `instagram:rollout_assisted_onboarding`, delegando a
`Instagram::Automation::AccountRollout`. Sem migration, callbacks de ativação,
mudanças de UI, Redis ou runtime. Branch existente: `feat/950-instagram-admin-panel`.
Nenhum commit, push, PR, merge ou deploy realizado por esta implementação.

A conta é elegível quando `Account#feature_enabled?('channel_instagram')` é verdadeiro.
Essa flag representa o direito de usar o canal e é reconciliada pelos planos no
Enterprise. Exigir uma inbox existente excluiria contas que precisam justamente
do primeiro onboarding. O rollout não concede `channel_instagram`, não muda plano
e não altera o gate global de automação.

## Idempotência e desligamento posterior

Cada conta elegível recebe o marcador interno
`internal_attributes['instagram_assisted_onboarding_rollout'] = true`. A presença
da chave impede qualquer nova ativação pela tarefa. Contas já habilitadas também
recebem o marcador na aplicação inicial, protegendo um desligamento posterior.
Contas inelegíveis não são marcadas; podem entrar em uma aplicação explícita futura
se adquirirem o direito ao canal.

Na aplicação, `Account#with_lock` recarrega a conta e abre a transação. Elegibilidade
e marcador são lidos dentro do lock. A tarefa usa `Account#enable_features` e um
único `save!` para persistir feature e marcador juntos, preservando as demais flags
e atributos internos. Falha de persistência interrompe a execução; a transação da
conta falha é revertida. Contas anteriormente persistidas ficam marcadas e são
ignoradas na retomada. O marcador não deve ser removido no rollback.

O estado false anterior ao primeiro rollout não distingue ausência da nova feature
de um desligamento manual anterior: não existe histórico específico no schema.
A proteção de desligamento vale após a primeira aplicação/marcação da conta.

## Operação futura — comandos documentados, NÃO executados

Preview, sem escrita nem marcador:

```bash
bundle exec rake instagram:rollout_assisted_onboarding
```

Aplicação exige as duas variáveis e aprovação explícita do Rodrigo para produção:

```bash
DRY_RUN=false INSTAGRAM_ROLLOUT_CONFIRM=instagram_assisted_onboarding \
  bundle exec rake instagram:rollout_assisted_onboarding
```

`DRY_RUN` aceita somente `true` ou `false`; o padrão é `true`. A confirmação exata
é validada no service antes de consultar contas. O relatório contém somente contagens
(`would_enable`, `enabled`, `already_enabled`, `processed`, `ineligible`), sem IDs ou
dados de clientes. Não há lista fixa de contas.

Rollback: desligar a feature pelo mecanismo administrativo existente, mantendo o
marcador. Reexecutar o rollout não religará contas marcadas. Nenhum rollback foi
executado nesta implementação.

## Contas novas

`config/features.yml` já define `instagram_assisted_onboarding` com `enabled: true`
em `feature_flags_ext_1`. Após o sync do `ConfigLoader` para
`ACCOUNT_LEVEL_FEATURE_DEFAULTS`, `Featurable#enable_default_features` aplica esse
default em `before_create` de novas contas. Esse sync não altera flags das contas
existentes; para elas, o mecanismo explícito acima é necessário.

Se uma instalação já tiver essa entrada de default cadastrada como false, o sync
padrão (`reconcile_only_new: true`) preserva o valor existente; o YAML sozinho não
sobrescreve essa configuração. Não executar sync forçado para contornar isso sem
revisar seu escopo e obter autorização. Nenhum sync foi executado aqui.

## Validação isolada

Os specs usam doubles, não carregam `rails_helper`, não inicializam Rails, não abrem
banco e não acessam Redis. A Rake task é invocada apenas dentro de um
`Rake::Application` isolado, com prerequisite `environment` vazio e service double.
Não houve execução operacional da tarefa, nem mesmo dry-run em banco real.

Comandos locais, após `eval "$(rbenv init -)"`:

```bash
env -i HOME="$HOME" PATH="$PATH" RAILS_ENV=test BUNDLE_FROZEN=true \
  bundle exec rspec spec/services/instagram/automation/account_rollout_spec.rb \
  spec/lib/tasks/rake/task_instagram_account_rollout_spec.rb --format progress

env -i HOME="$HOME" PATH="$PATH" RAILS_ENV=test BUNDLE_FROZEN=true \
  RUBOCOP_CACHE_ROOT=/private/tmp/950-rhea-rubocop bundle exec rubocop --no-server \
  app/services/instagram/automation/account_rollout.rb \
  lib/tasks/instagram_account_rollout.rake \
  spec/services/instagram/automation/account_rollout_spec.rb \
  spec/lib/tasks/rake/task_instagram_account_rollout_spec.rb --format simple
```

RSpec: **13 exemplos, 0 falhas**. Cobertura de dry-run, confirmação exata, input
inválido, elegibilidade, preservação de atributos/flags, marcador de contas já
habilitadas, desligamento posterior, rechecagem sob lock e propagação de falhas.
Os testes unitários verificam a delegação ao lock e ao save; a transação real de
ActiveRecord não foi exercitada com banco.

RuboCop: **4 arquivos, 0 apontamentos**. `git diff --check`: aprovado.

MacCluster: nó local `m4`. O planner recusou ambos os nós (`m2=offline`,
`m4=bundle-deps-missing`). Usado Ruby local 3.4.4, com dependências confirmadas por
`bundle check`, para testes sem serviços. RuboCop inicialmente tentou escrever
cache fora do sandbox; cache redirecionado para `/private/tmp`, sem alterar runtime.
