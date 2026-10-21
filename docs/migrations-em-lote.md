# Migrations em lote

Desde o #2024, várias migrations sobem no mesmo deploy. O que tornava perigoso subir mais de uma nunca foi a
quantidade. Era a classe de cada migration, e agora a CI confere essa classe antes do merge e o deploy confere de
novo contra o commit que está no ar.

O que a CI e o deploy conferem é a **estrutura** do banco. Nenhum dos dois é barreira contra perda de dados: um
UPDATE ou um backfill errado passa por todos os testes daqui. Migration que mexe em dados sai marcada no relatório e
depende da revisão humana.

## Por que o risco é a classe, não a quantidade

- A green roda o `db:migrate` **antes** da troca de tráfego (`rails db:chatwoot_prepare` no `deploy.sh` do user data
  dos dois workflows de deploy). A blue continua servindo durante e depois. Se a green falha, ou se há rollback, o
  código anterior roda no schema novo. Uma migration que o código anterior não aguenta quebra a produção, sozinha ou
  em lote.
- O Rails roda cada migration numa transação própria. Se um lote falha no meio, as primeiras ficam aplicadas, a green
  não sobe e a blue segue. Isso só é seguro se **cada uma** for compatível com o código anterior.
- O rollback blue-green não roda `down`. Ele volta o tráfego para a instância anterior, que roda no schema novo.

## O que barra o quê

| Risco | Onde é barrado |
|---|---|
| Remover ou renomear coluna ou tabela, trocar tipo, tornar NOT NULL uma coluna existente, criar coluna NOT NULL sem default em tabela existente, remover view, extensão ou valor de enum | Job **Migrations do lote** (`MigrationsSeguras::Compatibilidade`), comparando a estrutura do banco antes e depois |
| A blue estar vários PRs atrás da `main` (a fila não espera o deploy, e o deploy pula SHA superado) | Deploy, passo **Check the schema against the blue**, antes de existir green: a mesma `Compatibilidade` compara o `schema.rb` da blue com o deste commit, com o `db/retiradas.yml` **da blue** (`scripts/deploy/schema-contra-a-blue.sh`, leitura do `schema.rb` pela árvore do Ruby em `MigrationsSeguras::SchemaRb`) |
| Migration que mexe em dados (model, `update_all` e afins, `connection.execute`/`exec_query`, SQL bruto) | **Revisão humana.** O job só marca no relatório (coluna "Mexe em dados", lida pela árvore do Ruby em `MigrationsSeguras::Dados`) |
| Trava longa: índice sem `CONCURRENTLY`, chave estrangeira validada na hora, `change_column`, NOT NULL direto, `execute` sem revisão | `strong_migrations`, na CI e na própria green |
| Fila de leitura e escrita atrás de um ALTER | `lock_timeout` de 5 s em toda migration, com 3 tentativas (`config/initializers/strong_migrations.rb`) |
| `down` quebrado | Job: `down` de cada migration nova, da última para a primeira, tem de devolver a estrutura da base; `up` de novo tem de chegar ao mesmo lugar |
| `schema.rb` que não bate com as migrations | Job: o `schema.rb` do PR é carregado e comparado com o banco migrado |
| Versão repetida entre PRs | Job na fila de merge: a rodada junta as migrations de todos os PRs do lote, e o Rails recusa versão repetida |
| Falha no meio do lote | Job: as migrations sobem uma por vez, e a compatibilidade é conferida no estado depois de **cada** uma, porque um lote que para no meio deixa a blue naquele estado |
| Migration já na `main` editada, apagada ou renomeada | Job: falha. Ela já rodou em produção; correção vai numa migration nova |

Índice único, chave estrangeira e restrição CHECK novos numa tabela que já existe, e índice removido, **não bloqueiam**:
saem como aviso no relatório, para a revisão conferir se o código anterior não grava algo que a regra nova recusa.
Também é aviso o tipo que só ganhou espaço (`varchar(50)` para `varchar(100)` ou sem limite, `integer` para `bigint`,
`numeric` com mais precisão e a mesma escala), e a função ou gatilho com o corpo mudado (o retrato guarda o md5 de
`pg_get_functiondef` e `pg_get_triggerdef`).

O job roda no PostgreSQL 18, a mesma major da produção (18.3 nas duas stacks), e o strong_migrations decide pela 18
(`target_postgresql_version`). O RSpec comum segue no 16.

O strong_migrations ignora as migrations até `StrongMigrations.start_after` (a última da `main` quando a gem entrou).
No job ele checa **toda** migration nova do lote, mesmo com versão menor que essa.

O job roda no PR e na fila de merge. Na fila, a base é a `main` e o lote é a soma dos PRs da rodada: é o teste do lote
inteiro, na ordem das versões. Ele faz parte do check obrigatório **RSpec**.

Sem migration nova, o job só confere que o `schema.rb` do PR continua igual à estrutura da base. O PR que só muda o
`define(version:)` passa.

## Como escrever uma migration que passa

- Só acrescente: tabela nova, coluna nula ou com default, índice com `algorithm: :concurrently` (e
  `disable_ddl_transaction!`).
- Não escreva `execute "SET LOCAL lock_timeout ..."`: o `lock_timeout` já vem do strong_migrations. `execute` só dentro
  de `safety_assured { }`, com o motivo num comentário, e a revisão lê o SQL.
- Migration de dados (ligar flag, preencher coluna) vai separada da de schema, para o `down` de cada uma ser simples.
- Migration irreversível (`down` levanta `ActiveRecord::IrreversibleMigration`) passa, mas sai marcada no relatório:
  a volta do banco dela é o snapshot.
- O statement_timeout das migrations é o do `database.yml` (14 s). Índice `CONCURRENTLY` em tabela grande precisa
  subir esse limite dentro da migration, em `safety_assured`.

## Remover ou renomear (expand/contract)

1. PR 1: `self.ignored_columns += %w[coluna]` no model e a coluna em `db/retiradas.yml`. Ele sobe e fica no ar.
2. PR 2, depois do "ok, SHA" do PR 1: a migration que remove (`safety_assured { remove_column ... }`).

O job lê `db/retiradas.yml` **como estava na base**. Por isso a remoção nunca passa no mesmo PR, nem na mesma rodada
da fila, que a anuncia. Renomear é acrescentar a coluna nova, copiar os dados, passar o código para ela e depois
remover a antiga por este caminho.

O PR 2 é a migration que não é só aditiva. Ele sobe sozinho e com OK do Rodrigo (`processo-de-release.md`).

O deploy confere o mesmo de novo contra a **blue**: se o PR 1 entrou na `main` mas não chegou a subir, e o PR 2 vem no
mesmo deploy, o passo **Check the schema against the blue** para o deploy antes de lançar a green, e nada é mexido.
A saída é subir o PR 1 sozinho (reverter o PR 2 na `main`, deploy, e voltar o PR 2 depois do "ok, SHA").

Esse passo roda em todo deploy e é fechado por padrão: se não der para saber o commit da blue (tag `Name` da
instância ou API do GitHub, com três tentativas), o deploy para ali, antes de existir green, e é só disparar de novo.
É o mesmo pré-requisito do rollback (`check-rollback-target.sh`). Lido sem banco, o `schema.rb` mostra tabelas,
colunas, índices, restrições e chaves; funções e gatilhos (os `execute` do hairtrigger) entram pelo texto do SQL e,
como no job, só geram aviso.

## Quando um lote para no meio

Cada migration roda na sua transação. Se uma esgota o `lock_timeout` (5 s, 3 tentativas) ou falha por outro motivo, as
anteriores do lote **ficam aplicadas**, a green não sobe e a blue segue no ar, no schema dessas anteriores. Como o job
conferiu a compatibilidade depois de cada migration, a blue aguenta esse estado. O próximo deploy roda só as que
faltam. Não é preciso desfazer nada; se a falha foi trava, basta disparar o deploy de novo fora do pico.

## Rollback

- **App:** o rollback blue-green de sempre (`action=rollback`, `esperado_sha`). Funciona com as migrations do lote
  aplicadas, porque todas são compatíveis com o código anterior. Na prática, o banco fica como está.
- **Banco, uma versão:** `bundle exec rails db:migrate:down VERSION=<versão>`, da última para a primeira. O `down` de
  cada uma foi testado no job, que mostra no relatório quais são irreversíveis. Rodar na produção é escrita em banco
  de produção: precisa do OK do Rodrigo, uma operação por vez.
- **Banco inteiro:** restaurar o snapshot tirado antes do deploy. Restaurar cria uma instância nova do RDS, então é
  decisão do Rodrigo.

## Snapshot automático no deploy

Os dois workflows de deploy pedem um snapshot manual do RDS quando o commit traz migration que o da blue não tem
(`scripts/deploy/rds-snapshot-antes-da-migration.sh`). O pedido sai cedo no job, e o deploy espera o snapshot ficar
`available` antes de lançar a green, que é quem roda o `db:migrate` (num rerun a imagem já está no ECR e a green
começaria na hora). O `aws rds wait` desiste em 30 min: snapshot mais demorado falha o deploy antes de existir green.
Na dúvida (commit da blue desconhecido, fetch ou comparação que falha), o snapshot é tirado do mesmo jeito.

Fica **desligado** até o Rodrigo ligar. Para ligar, por stack:

1. Dar ao papel `chatwoot-autonomia-prod-github-actions-deploy` da conta da stack as ações abaixo, restritas à
   instância do RDS e a snapshots `chatwoot-antes-da-migration-*`:
   - `rds:CreateDBSnapshot`, na instância e no snapshot;
   - `rds:AddTagsToResource`, no snapshot (o pedido sai com as tags `CriadoPor` e `Commit`);
   - `rds:DescribeDBSnapshots`, que o `aws rds wait db-snapshot-available` usa.
2. Criar o **secret** do repositório com o identificador da instância: `RDS_SNAPSHOT_DB_INSTANCE_HUB2YOU` ou
   `RDS_SNAPSHOT_DB_INSTANCE_AUTONOMIA`. Secret, não variável: o valor de uma variável aparece no log público.

Erro da AWS sai no log só com o código (`AccessDenied` e afins), porque a mensagem completa traz a conta e o ARN, e o
repositório é público.

Pré-requisitos para ligar (decisão do Rodrigo):

- **Cota.** Snapshot manual não expira, e a conta tem cota de snapshots manuais por região (100 no padrão da AWS).
  Cada deploy com migration cria um. O deploy **não apaga** nenhum: apagar backup é decisão do Rodrigo. Sem uma rotina
  de limpeza, a cota acaba e o `create-db-snapshot` passa a falhar, o que para o deploy com migration. Também custa
  armazenamento;
- **Single-AZ.** Numa instância Single-AZ o snapshot suspende o I/O por alguns segundos a minutos (documentação da
  AWS), com a blue servindo. Multi-AZ tira da standby e não suspende. Conferir o modo de cada RDS antes de ligar;
- se o RDS tem backup automático com retenção maior que zero, a restauração para um ponto no tempo já cobre o
  minuto antes do deploy. O snapshot é a cópia nomeada e fácil de achar;
