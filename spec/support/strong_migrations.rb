# Specs que rodam uma migration (spec/db/migrate e os de backfill) a criam com `described_class.new`, sem versão. Sem
# versão o strong_migrations não sabe que ela é anterior ao StrongMigrations.start_after e barra `execute`,
# `remove_column` e afins. Esses specs testam o que a migration faz com os dados; os bloqueios do strong_migrations
# rodam onde a migration tem versão: no job "Migrations do lote" do CI e na green do deploy (#2024).
# `safety_assured` é o bloco documentado da gem. Pela ENV (SAFETY_ASSURED com with_modified_env) todo exemplo rodava
# dentro do ClimateControl, e os specs que fazem stub de Process.clock_gettime falhavam
# (spec/services/crm/ai/responses_client_rodadas_spec.rb).
RSpec.configure do |config|
  # Spec que testa o bloqueio da própria gem marca `strong_migrations: true` e roda sem a liberação.
  config.around do |example|
    next example.run if example.metadata[:strong_migrations]

    StrongMigrations::Checker.safety_assured { example.run }
  end
end
