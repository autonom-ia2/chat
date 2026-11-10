require 'rails_helper'
require Rails.root.join('db/migrate/20261109955500_create_autonomia_automacao_campanhas_da_vez.rb')

# #2823 G55 — o CREATE INDEX CONCURRENTLY interrompido deixa o índice inválido, e um IF NOT EXISTS o daria por pronto.
# A migration refaz o inválido e confere o resultado. Roda fora de transação: CREATE INDEX CONCURRENTLY não roda dentro
# de uma.
RSpec.describe CreateAutonomiaAutomacaoCampanhasDaVez do
  self.use_transactional_tests = false

  let(:migration) { described_class.new(described_class.name, 20_261_109_955_500) }
  let(:conexao) { ActiveRecord::Base.connection }

  def valido
    conexao.select_value(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{conexao.quote(described_class::INDICE)}
    SQL
  end

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    # Deixa o banco de teste como o schema.rb: a tabela e o índice, válido.
    migration.migrate(:down)
    migration.migrate(:up)
    ActiveRecord::Migration.verbose = verbose
  end

  it 'refaz o índice que sobrou inválido de uma rodada interrompida' do
    conexao.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{described_class::INDICE}'::regclass")
    expect(valido).to be(false)

    migration.migrate(:up)

    expect(valido).to be(true)
  end

  it 'desce e sobe de novo: a tabela e o índice válido', :aggregate_failures do
    migration.migrate(:down)
    expect([conexao.table_exists?(:autonomia_automacao_campanhas_da_vez), valido]).to eq([false, nil])

    migration.migrate(:up)

    expect([conexao.table_exists?(:autonomia_automacao_campanhas_da_vez), valido]).to eq([true, true])
  end

  it 'o lock_timeout e o statement_timeout da sessão voltam ao que eram' do
    antes = conexao.select_rows('SELECT current_setting(\'lock_timeout\'), current_setting(\'statement_timeout\')')
    migration.migrate(:down)
    migration.migrate(:up)

    expect(conexao.select_rows('SELECT current_setting(\'lock_timeout\'), current_setting(\'statement_timeout\')')).to eq(antes)
  end
end
