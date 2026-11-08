# Testa as migrations novas do lote contra a base (#2024). Quem chama é o job "Migrations do lote" do testes.yml, que
# tira da base, pelo git, o schema.rb, a lista de arquivos de db/migrate e o db/retiradas.yml. Apaga e recria o banco
# configurado: o nome dele vai repetido em MIGRATIONS_SEGURAS_BANCO. Regras: docs/migrations-em-lote.md.
namespace :migrations_seguras do
  desc 'Testa as migrations novas do lote: compatibilidade com o código anterior, up/down/up e schema.rb'
  task verificar: 'db:load_config' do
    retiradas_da_base = ENV.fetch('MIGRATIONS_SEGURAS_BASE_RETIRADAS', '')
    resultado = MigrationsSeguras::Lote.new(
      base_schema: ENV.fetch('MIGRATIONS_SEGURAS_BASE_SCHEMA'),
      base_migrations: File.readlines(ENV.fetch('MIGRATIONS_SEGURAS_BASE_MIGRATIONS'), chomp: true).compact_blank,
      retiradas: File.file?(retiradas_da_base) ? YAML.safe_load_file(retiradas_da_base) || {} : {},
      banco: ENV.fetch('MIGRATIONS_SEGURAS_BANCO')
    ).executar

    relatorio = resultado.markdown
    puts relatorio
    destino = ENV.fetch('MIGRATIONS_SEGURAS_RELATORIO', '')
    File.write(destino, relatorio) if destino.present?
    abort('Migrations do lote: bloqueado. Ver o relatório acima.') unless resultado.ok?
  end
end
