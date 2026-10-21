# Specs que rodam uma migration (spec/db/migrate e os de backfill) a criam com `described_class.new`, sem versão. Sem
# versão o strong_migrations não sabe que ela é anterior ao StrongMigrations.start_after e barra `execute`,
# `remove_column` e afins. Esses specs testam o que a migration faz com os dados; os bloqueios do strong_migrations
# rodam onde a migration tem versão: no job "Migrations do lote" do CI e na green do deploy (#2024).
# SAFETY_ASSURED é a chave documentada da gem.
RSpec.configure do |config|
  config.around do |example|
    with_modified_env(SAFETY_ASSURED: '1') { example.run }
  end
end
