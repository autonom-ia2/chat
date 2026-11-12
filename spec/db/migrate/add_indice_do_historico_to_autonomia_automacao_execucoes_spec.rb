require 'rails_helper'
require Rails.root.join('db/migrate/20261112100000_add_indice_do_historico_to_autonomia_automacao_execucoes.rb')

# #2507 — o índice (automacao_id, created_at) do histórico entra concurrently. O CREATE INDEX CONCURRENTLY interrompido
# deixa o índice inválido, e um IF NOT EXISTS o daria por pronto: a migration refaz o inválido e confere o resultado.
# Roda fora de transação: CREATE INDEX CONCURRENTLY não roda dentro de uma.
RSpec.describe AddIndiceDoHistoricoToAutonomiaAutomacaoExecucoes do
  self.use_transactional_tests = false

  let(:migration) { described_class.new(described_class.name, 20_261_112_100_000) }
  let(:conexao) { ActiveRecord::Base.connection }

  def valido
    conexao.select_value(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{conexao.quote(described_class::INDICE)}
    SQL
  end

  def colunas
    conexao.indexes(:autonomia_automacao_execucoes).find { |indice| indice.name == described_class::INDICE }&.columns
  end

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    # Deixa o banco de teste como o schema.rb: o índice, válido.
    migration.migrate(:up)
    ActiveRecord::Migration.verbose = verbose
  end

  it 'o índice do schema.rb existe, válido, em (automacao_id, created_at)', :aggregate_failures do
    expect(valido).to be(true)
    expect(colunas).to eq(%w[automacao_id created_at])
  end

  it 'refaz o índice que sobrou inválido de uma rodada interrompida' do
    conexao.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{described_class::INDICE}'::regclass")
    expect(valido).to be(false)

    migration.migrate(:up)

    expect(valido).to be(true)
  end

  it 'desce e sobe de novo: some e volta válido', :aggregate_failures do
    migration.migrate(:down)
    expect(valido).to be_nil

    migration.migrate(:up)

    expect(valido).to be(true)
  end

  it 'o lock_timeout e o statement_timeout da sessão voltam ao que eram' do
    antes = conexao.select_rows('SELECT current_setting(\'lock_timeout\'), current_setting(\'statement_timeout\')')
    migration.migrate(:down)
    migration.migrate(:up)

    expect(conexao.select_rows('SELECT current_setting(\'lock_timeout\'), current_setting(\'statement_timeout\')')).to eq(antes)
  end
end
