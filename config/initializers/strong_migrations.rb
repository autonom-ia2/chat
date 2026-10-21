# strong_migrations (#2024): barra, na hora de rodar, a migration que trava tabela por muito tempo ou que o código
# anterior não aguenta (remover coluna sem ignored_columns, renomear, trocar tipo, NOT NULL em coluna existente). Vale
# em todo ambiente, inclusive na green do deploy: é a última barreira depois do job "Migrations do lote" do CI.
# Guia de cada bloqueio e do jeito seguro: https://github.com/ankane/strong_migrations#checks
# Regras do fork: docs/migrations-em-lote.md.

# As migrations até esta versão (a última da main quando a gem entrou) já rodaram em produção e não passam pelos
# bloqueios; o lock_timeout abaixo vale para todas. Migration nova com versão menor que esta (gerada com a data do dia,
# por exemplo) também escaparia aqui, por isso o job "Migrations do lote" zera o start_after e checa toda migration
# nova do lote, qualquer que seja a versão.
StrongMigrations.start_after = 20_261_108_230_000

# ALTER TABLE pede trava exclusiva. Atrás de uma transação longa ele espera, e toda leitura e escrita da tabela espera
# atrás dele. Com 5 s a migration desiste e é tentada de novo; esgotadas as tentativas, o deploy falha antes do
# tráfego e a blue segue no ar. O statement_timeout fica o do database.yml (14 s): migration longa falha em vez de
# segurar a green.
StrongMigrations.lock_timeout = 5.seconds
StrongMigrations.lock_timeout_retries = 3
StrongMigrations.lock_timeout_retry_delay = 10

# Índice novo sem estatística pode piorar as consultas que já existem.
StrongMigrations.auto_analyze = true

# CREATE INDEX CONCURRENTLY que falhou deixa um índice inválido, e rodar de novo daria "já existe".
StrongMigrations.remove_invalid_indexes = true
