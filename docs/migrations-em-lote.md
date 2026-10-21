# Migrations em lote

Desde o #2024, várias migrations sobem no mesmo deploy. O que tornava perigoso subir mais de uma nunca foi a
quantidade. Era a classe de cada migration, e agora a CI confere essa classe antes do merge.

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
| Trava longa: índice sem `CONCURRENTLY`, chave estrangeira validada na hora, `change_column`, NOT NULL direto, `execute` sem revisão | `strong_migrations`, na CI e na própria green |
| Fila de leitura e escrita atrás de um ALTER | `lock_timeout` de 5 s em toda migration, com 3 tentativas (`config/initializers/strong_migrations.rb`) |
| `down` quebrado | Job: `down` de cada migration nova, da última para a primeira, tem de devolver a estrutura da base; `up` de novo tem de chegar ao mesmo lugar |
| `schema.rb` que não bate com as migrations | Job: o `schema.rb` do PR é carregado e comparado com o banco migrado |
| Versão repetida entre PRs | Job na fila de merge: a rodada junta as migrations de todos os PRs do lote, e o Rails recusa versão repetida |
| Falha no meio do lote | Coberta pela compatibilidade: cada migration é aditiva, então qualquer prefixo do lote deixa a blue de pé |

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
(`scripts/deploy/rds-snapshot-antes-da-migration.sh`). O pedido sai cedo no job, e o build espera o snapshot ficar
`available`, porque a green só roda o `db:migrate` quando a imagem chega ao ECR. Sem saber o commit da blue, o
snapshot é tirado do mesmo jeito.

Fica **desligado** até o Rodrigo ligar. Para ligar, por stack:

1. Dar ao papel `chatwoot-autonomia-prod-github-actions-deploy` da conta da stack as ações abaixo, restritas à
   instância do RDS e a snapshots `chatwoot-antes-da-migration-*`:
   - `rds:CreateDBSnapshot`, na instância e no snapshot;
   - `rds:AddTagsToResource`, no snapshot (o pedido sai com as tags `CriadoPor` e `Commit`);
   - `rds:DescribeDBSnapshots`, que o `aws rds wait db-snapshot-available` usa.
2. Criar a variável do repositório com o identificador da instância: `RDS_SNAPSHOT_DB_INSTANCE_HUB2YOU` ou
   `RDS_SNAPSHOT_DB_INSTANCE_AUTONOMIA`.

Erro da AWS sai no log só com o código (`AccessDenied` e afins), porque a mensagem completa traz a conta e o ARN, e o
repositório é público.

Pontos de atenção:

- snapshot manual não expira, e cada um custa armazenamento. A limpeza (`rds:DeleteDBSnapshot`) ficou de fora de
  propósito: apagar backup é decisão do Rodrigo;
- numa instância Single-AZ o snapshot suspende o I/O por alguns segundos ou minutos (documentação da AWS). Multi-AZ
  tira da standby e não suspende;
- se o RDS tem backup automático com retenção maior que zero, a restauração para um ponto no tempo já cobre o
  minuto antes do deploy. O snapshot é a cópia nomeada e fácil de achar;
- rerun de um deploy cuja imagem já está no ECR: a green pode começar a migration antes do snapshot. Nesse caso as
  migrations quase sempre já rodaram na primeira tentativa.
