# Issue 436 — PR1: guards após carga de schema

Data: 2026-09-16. Implementação local; validação PostgreSQL pendente do processo pai.

## Problema e decisão

A migração `20260916121200` criava funções e triggers que o dump Ruby não representa. O CI em `.github/workflows/testes.yml:167` executa `bundle exec rake db:schema:load`, deixando de aplicar essas invariantes mesmo com a versão da migração registrada.

A migração agora delega ao instalador `EmailCampaigns::ReputationSchemaGuards`, com conexão explícita. O arquivo Rake registra um wrapper de `ActiveRecord::Tasks::DatabaseTasks.load_schema` ao executar `db:load_config`, depois da inicialização Rails. O wrapper instala os guards após a carga, ainda na conexão de migração escolhida pelo Rails. Não há inicializador nem DDL no boot normal, no carregamento das tarefas ou em requisições/jobs.

O instalador usa `CREATE OR REPLACE FUNCTION` e substitui os triggers próprios em uma transação. Isso permite instalação inicial, repetição, recuperação de trigger ausente/desabilitado e recarga de schema quando a função anterior sobreviveu. As regras SQL permanecem as da migração original:

- Auditoria permite inserção e rejeita `UPDATE`/`DELETE` por linha.
- `triggered_at` e `trigger_snapshot` ficam imutáveis depois da captura inicial.
- A transição de `blocked = false` para `true` permite registrar novo incidente.
- Alterações de métricas e liberação sem apagar a evidência continuam permitidas.

Tabelas e funções são qualificadas pelo namespace da relação resolvida no `search_path`, em vez de presumir `public` ou `current_schema()`. Schemas com tabelas homônimas mantêm funções independentes. O instalador não troca a conexão recebida. O wrapper usa `migration_connection`, dentro do mesmo ciclo de seleção usado pelo carregador Rails, sem iterar novamente pelos bancos.

O hook só instala quando existem as duas tabelas e as colunas usadas pelo trigger de estado (`blocked`, `triggered_at`, `trigger_snapshot`). Isso permite carregar dumps antigos ou bancos de outra finalidade. A migração chama `install!` diretamente, que falha se os pré-requisitos faltarem. Erros de instalação não são resgatados nem convertidos em sucesso. Nenhum spec de invariante depende dessa verificação de aplicabilidade para pular testes.

`down` remove somente os dois triggers e as duas funções, nos schemas das respectivas tabelas, com `IF EXISTS` e sem `CASCADE`. Não remove tabelas, dados, chaves ou guards de terceiros. Se uma tabela já não existir, não tenta adivinhar onde uma função órfã estaria; o rollback normal ocorre antes da migração que criou as tabelas. Nenhuma FK foi adicionada à auditoria; a exclusão de contas e atores continua sob os testes de retenção existentes.

## Ciclo de vida conferido no Rails instalado

Fontes lidas diretamente no gem `activerecord-7.2.3.1`, conforme `Gemfile.lock`:

- `lib/active_record/tasks/database_tasks.rb`: `load_schema`, `load_schema_current`, `prepare_all`, `with_temporary_connection`, `with_temporary_pool`, `migration_connection`, `schema_up_to_date?` e `reconstruct_from_schema`.
- `lib/active_record/railties/databases.rake`: dependência de `db:load_config`, variantes por banco e tarefas de preparação de teste.
- `lib/active_record/migration.rb`: `maintain_test_schema!`, `load_schema_if_pending!` e `any_schema_needs_update?`.
- `lib/active_record/test_databases.rb`: reconstrução direta dos bancos de workers paralelos.

Caminhos cobertos pelo registro nas tarefas, sempre que efetivamente carregam schema:

| Comando/caminho | Integração |
| --- | --- |
| `rake db:schema:load` | `load_schema_current` chama o wrapper uma vez por banco alvo. |
| `rake db:schema:load:<nome>` | O wrapper executa dentro do pool temporário do banco nomeado. |
| `rake db:test:load_schema`, `db:test:prepare` e variantes `:<nome>` | Passam por `db:load_config` e pelo mesmo carregador. |
| `rake db:setup`, `db:reset`, `db:prepare` | Cobertos quando essas tarefas efetivamente carregam o dump. |
| `rake db:chatwoot_prepare` | Sua chamada existente a `load_schema_current` passa pelo wrapper. |
| `rake db:migrate` | A migração chama o instalador diretamente; nenhuma versão é alterada pelo wrapper. |

`SCHEMA`, `SCHEMA_FORMAT`, seleção de ambiente/bancos e proteção contra ambiente de produção continuam sob o Rails. O hook não muda `schema_format`. Não foi feita execução para comprovar variantes reais com múltiplos bancos; os specs adicionados cobrem schemas PostgreSQL separados e o contrato de conexão por chamada.

Limites que não devem ser confundidos com reparo automático:

1. `maintain_test_schema!` verifica o hash do dump e versões pendentes, não a existência dos triggers. Quando o schema está desatualizado, ele chama `bin/rails db:test:prepare` em subprocesso, que passa pelo hook. Com hash atual, não reinstala guards ausentes. `db:prepare` também não repara um banco já preparado e sem migração pendente.
2. `load 'db/schema.rb'` direto, console/runner e chamadas diretas a `DatabaseTasks` sem execução de `db:load_config` não registram o hook. Carregar apenas as definições Rake não equivale a executar essa tarefa.
3. A paralelização nativa do Rails chama `reconstruct_from_schema` diretamente. Não se promete cobertura de workers que não executaram `db:load_config`; a ramificação que apenas trunca tabelas também não chama `load_schema`. O CI/RSpec deste caso deve preparar explicitamente o banco pelo comando Rake suportado.
4. A carga padrão do Rails não é uma transação única com os guards. Uma falha do instalador interrompe a tarefa, mas o Rails pode já ter gravado metadados do dump. É necessário corrigir a falha e repetir a carga no banco descartável, em vez de confiar em `maintain_test_schema!` para repará-la.
5. `db:schema:load` substitui tabelas; o procedimento abaixo é exclusivamente para banco de teste descartável. Não é uma proposta de reparo de produção.

## Specs adicionados, ainda não executados

- `spec/lib/email_campaigns/reputation_schema_guards_spec.rb`: instalação inicial/repetida, restauração de trigger ausente/desabilitado, `up/down` da migração, preservação de guard alheio, resolução de namespace, schemas homônimos independentes, duas cargas Ruby reais pelo carregador, pré-requisitos incompletos e propagação de falha.
- `spec/lib/email_campaigns/reputation_schema_guards_invariants_spec.rb`: exige guards previamente instalados; não chama o instalador no setup. Exercita SQL direto de alteração/exclusão de auditoria, alteração/limpeza do timestamp e snapshot, liberação, métricas, captura inicial e novo incidente. Savepoints isolam os erros SQL esperados.
- `spec/lib/email_campaigns/reputation_schema_guards/schema_load_hook_spec.rb`: contrato do wrapper com dois alvos sequenciais, preservação do retorno do loader e ausência de dump. Usa doubles; não comprova conexões reais com dois bancos.

`retention_spec.rb` e demais specs existentes não foram alterados. Não há skip, teste condicional ou gate desabilitado. Os testes do instalador usam schemas temporários próprios; suas remoções com `CASCADE` ficam restritas a esses schemas de teste, sem relação com o `down` da migração.

## Validação executada

Somente verificações estáticas. Comandos finais exatos, executados a partir da raiz deste worktree:

```sh
eval "$(rbenv init -)"
ruby -c db/migrate/20260916121200_protect_email_reputation_history.rb
ruby -c lib/email_campaigns/reputation_schema_guards.rb
ruby -c lib/tasks/email_reputation_schema.rake
ruby -c spec/lib/email_campaigns/reputation_schema_guards_spec.rb
ruby -c spec/lib/email_campaigns/reputation_schema_guards_invariants_spec.rb
ruby -c spec/lib/email_campaigns/reputation_schema_guards/schema_load_hook_spec.rb
bundle exec rubocop --cache false db/migrate/20260916121200_protect_email_reputation_history.rb lib/email_campaigns/reputation_schema_guards.rb lib/tasks/email_reputation_schema.rake spec/lib/email_campaigns/reputation_schema_guards_spec.rb spec/lib/email_campaigns/reputation_schema_guards_invariants_spec.rb spec/lib/email_campaigns/reputation_schema_guards/schema_load_hook_spec.rb
```

Resultado: seis `Syntax OK`; RuboCop `6 files inspected, no offenses detected`, saída 0. As rodadas anteriores apontaram convenções de heredoc SQL, alinhamento e organização de specs; foram corrigidas, incluindo autocorreção restrita aos arquivos autorizados. Nenhum Rails, RSpec, migração ou SQL foi executado nesta tarefa. Nenhuma instalação, rede, SSH/AWS/SMTP, leitura de `.env`, edição de `schema.rb` ou escrita Git.

## Validação obrigatória pelo processo pai

Preparar um PostgreSQL **novo, descartável, em localhost**, com seleção explícita de banco e ambiente. O dump usado deve já conter a migração de criação das tabelas/colunas e versões correspondentes; este trabalho não alterou `db/schema.rb`. Usar o isolamento de ambiente local do pai, sem carregar configuração real. A variável `ISSUE436_TEST_DATABASE_URL` abaixo é apenas um placeholder para a conexão local previamente conferida pelo pai; não foi definida nem utilizada aqui.

```sh
eval "$(rbenv init -)"
RAILS_ENV=test DATABASE_URL="${ISSUE436_TEST_DATABASE_URL:?Defina a URL do banco localhost descartavel}" bundle exec rake db:schema:load
RAILS_ENV=test DATABASE_URL="${ISSUE436_TEST_DATABASE_URL:?Defina a URL do banco localhost descartavel}" bundle exec rspec spec/lib/email_campaigns/reputation_schema_guards_invariants_spec.rb spec/services/email_campaigns/reputation/retention_spec.rb spec/models/email_suppression_state_retention_spec.rb
RAILS_ENV=test DATABASE_URL="${ISSUE436_TEST_DATABASE_URL:?Defina a URL do banco localhost descartavel}" bundle exec rspec spec/lib/email_campaigns/reputation_schema_guards_spec.rb spec/lib/email_campaigns/reputation_schema_guards/schema_load_hook_spec.rb spec/services/email_campaigns/reputation
```

A primeira execução de RSpec deliberadamente verifica invariantes e retenção antes dos specs que chamam o instalador. Exigir sucesso sem reinstalação manual intermediária e registrar os resultados. A suíte de reputação inclui os testes existentes de snapshot, SQL direto, novo incidente, entrega e concorrência. O pai deve também incluir quaisquer outros testes de retenção existentes no escopo integrado de PR1.

Para validar especificamente `maintain_test_schema!` com schema desatualizado, usar outro banco descartável e confirmar que o subprocesso `db:test:prepare` deixa os guards presentes. Para atestar múltiplos bancos reais, executar também a variante nomeada com configurações locais isoladas e verificar que o banco não selecionado permanece intacto. Essas execuções continuam pendentes; esta entrega não declara aprovação de integração, merge ou deploy.
