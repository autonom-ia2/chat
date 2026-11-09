require 'rails_helper'
require Rails.root.join('db/migrate/20261109999900_add_paralela_to_autonomia_automacao_execucoes.rb')

# #2414 G50: a troca do índice da execução aberta. Um CREATE UNIQUE INDEX CONCURRENTLY que cai no meio deixa o índice
# inválido; o IF NOT EXISTS o daria por pronto só pelo nome, e o índice velho sairia sem nenhum válido no lugar. A
# migration refaz o inválido, confere que ficou válido e só então tira o outro, na ida e na volta.
RSpec.describe AddParalelaToAutonomiaAutomacaoExecucoes do
  let(:migration) { described_class.new(described_class.name, 20_261_109_999_900) }
  let(:conexao) { ActiveRecord::Base.connection }
  let(:velho) { described_class::VELHO }
  let(:novo) { described_class::NOVO }

  # true = existe e é válido; false = existe e é inválido; nil = não existe.
  def valido(nome)
    conexao.select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{conexao.quote(nome)}")
  end

  def invalidar(nome)
    conexao.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = #{conexao.quote(nome)}::regclass")
  end

  def criar_invalido(nome)
    conexao.add_index(described_class::TABELA, described_class::CHAVE, unique: true, where: described_class::ONDE.fetch(nome), name: nome)
    invalidar(nome)
  end

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  context 'with os índices de verdade (fora de transação: CONCURRENTLY não roda dentro de uma)' do
    self.use_transactional_tests = false

    # Deixa o banco de teste como o schema.rb: a coluna e só o índice novo, válido.
    after { migration.migrate(:up) }

    it 'o CREATE do índice novo que cai no meio deixa o velho no lugar, e a nova rodada refaz o novo antes de tirar o velho',
       :aggregate_failures do
      migration.migrate(:down)
      allow(conexao).to receive(:add_index).and_wrap_original do |original, *args, **opcoes|
        original.call(*args, **opcoes)
        invalidar(novo)
        raise ActiveRecord::StatementInvalid, 'PG::LockNotAvailable simulado'
      end

      expect { migration.migrate(:up) }.to raise_error(ActiveRecord::StatementInvalid, /simulado/)
      expect([valido(novo), valido(velho)]).to eq([false, true])

      allow(conexao).to receive(:add_index).and_call_original
      migration.migrate(:up)

      expect([valido(novo), valido(velho)]).to eq([true, nil])
    end

    it 'o índice novo que sobrou inválido não passa por pronto: é refeito, e o velho só sai depois', :aggregate_failures do
      migration.migrate(:down)
      conexao.add_column(described_class::TABELA, :paralela, :boolean, null: false, default: false)
      criar_invalido(novo)

      migration.migrate(:up)

      expect([valido(novo), valido(velho)]).to eq([true, nil])
    end

    it 'na volta, o índice velho que sobrou inválido é refeito antes de o novo sair', :aggregate_failures do
      criar_invalido(velho)

      migration.migrate(:down)

      expect([valido(velho), valido(novo)]).to eq([true, nil])
      expect(conexao.column_exists?(described_class::TABELA, :paralela)).to be(false)
    end
  end

  # A conferência vem antes de qualquer CREATE/DROP INDEX: roda dentro da transação do teste.
  it 'a volta com uma execução paralela aberta para com a contagem, sem tocar em índice nenhum', :aggregate_failures do
    create(:autonomia_automacao_execucao, paralela: true)

    expect { migration.migrate(:down) }.to raise_error(RuntimeError, /1 execução\(ões\) paralela\(s\) aberta\(s\)/)
    expect([valido(novo), valido(velho)]).to eq([true, nil])
    expect(conexao.column_exists?(described_class::TABELA, :paralela)).to be(true)
  end
end
