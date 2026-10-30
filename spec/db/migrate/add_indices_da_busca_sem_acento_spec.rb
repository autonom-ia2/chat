require 'rails_helper'
require Rails.root.join('db/migrate/20261108520000_add_indices_da_busca_sem_acento.rb')

# #2211 — CREATE INDEX CONCURRENTLY espera quem escreve na tabela. Com o lock_timeout do StrongMigrations, a espera
# estourava, o índice ficava inválido, e a nova tentativa da gem (IF NOT EXISTS) via que ele existia e registrava a
# versão com indisvalid = false. A migration zera o lock_timeout durante o CREATE INDEX, refaz o inválido e confere o
# resultado. Roda fora de transação: CREATE INDEX CONCURRENTLY não roda dentro de uma.
RSpec.describe AddIndicesDaBuscaSemAcento do
  self.use_transactional_tests = false

  let(:migration) { described_class.new(described_class.name, 20_261_108_520_000) }
  let(:conexao) { ActiveRecord::Base.connection }

  def validos
    conexao.select_rows(<<~SQL.squish).to_h
      SELECT c.relname, i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname IN (#{described_class::INDICES.map { |*, nome| conexao.quote(nome) }.join(', ')})
    SQL
  end

  # Outra conexão com uma transação aberta que escreve em crm_cards, solta depois de `segundos`.
  def escrita_aberta_em_crm_cards(segundos)
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
                       password: config[:password].presence)
    outra.exec('BEGIN')
    outra.exec('LOCK TABLE crm_cards IN ROW EXCLUSIVE MODE')
    Thread.new do
      sleep segundos
      outra.exec('COMMIT')
      outra.close
    end
  end

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    # Deixa o banco de teste como o schema.rb: os quatro índices, válidos.
    migration.migrate(:down)
    migration.migrate(:up)
    ActiveRecord::Migration.verbose = verbose
  end

  it 'com uma escrita aberta mais longa que o lock_timeout, espera e termina com os quatro índices válidos' do
    allow(StrongMigrations).to receive_messages(lock_timeout: 1.second, lock_timeout_retries: 1, lock_timeout_retry_delay: 3)
    migration.migrate(:down)
    soltar = escrita_aberta_em_crm_cards(2)
    migration.migrate(:up)
    soltar.join

    expect(validos.values).to eq([true] * 4)
    expect(validos.keys).to match_array(described_class::INDICES.map(&:last))
  end

  # Vale enquanto esta for a última migration da lista. No dia em que a lista mudar, com uma migration nova, troque este
  # teste para comparar a migration nova com o código.
  it 'a lista congelada na migration é a mesma do código' do
    expect(described_class::ACENTOS_COMBINANTES).to eq(SearchService::SemAcento::ACENTOS_COMBINANTES)
  end

  it 'refaz o índice que sobrou inválido de uma rodada interrompida' do
    conexao.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'idx_crm_cards_titulo_sem_acento_trgm'::regclass")
    migration.migrate(:up)

    expect(validos['idx_crm_cards_titulo_sem_acento_trgm']).to be(true)
  end

  it 'o lock_timeout e o statement_timeout da sessão voltam ao que eram' do
    antes = conexao.select_rows('SELECT current_setting(\'lock_timeout\'), current_setting(\'statement_timeout\')')
    migration.migrate(:down)
    migration.migrate(:up)

    depois = conexao.select_rows('SELECT current_setting(\'lock_timeout\'), current_setting(\'statement_timeout\')')
    expect(depois).to eq(antes)
  end
end
