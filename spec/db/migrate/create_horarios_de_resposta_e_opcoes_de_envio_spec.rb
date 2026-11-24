require 'rails_helper'
require Rails.root.join('db/migrate/20261123212000_create_horarios_de_resposta_e_opcoes_de_envio.rb')

# #3101: as duas tabelas novas do melhor horário e das opções de envio da campanha (já com as colunas do reenvio). O
# down tira as duas e o up as devolve iguais ao db/schema.rb; apagar o contato apaga a hora dele.
RSpec.describe CreateHorariosDeRespostaEOpcoesDeEnvio do
  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  let(:connection) { ActiveRecord::Base.connection }
  let(:tabelas) { %w[horarios_de_resposta campanha_opcoes_de_envio] }

  def colunas(tabela) = connection.columns(tabela).to_h { |coluna| [coluna.name, [coluna.sql_type, coluna.null, coluna.default]] }
  def indices(tabela) = connection.indexes(tabela).to_h { |indice| [indice.name, [indice.columns, indice.unique]] }
  def chaves(tabela) = connection.foreign_keys(tabela).map { |chave| [chave.to_table, chave.on_delete] }.sort_by(&:first)

  it 'o down tira as duas tabelas e o up as devolve como o schema.rb', :aggregate_failures do
    do_schema = tabelas.index_with { |tabela| [colunas(tabela), indices(tabela), chaves(tabela)] }

    described_class.new.migrate(:down)
    expect(tabelas.none? { |tabela| connection.table_exists?(tabela) }).to be(true)

    described_class.new.migrate(:up)
    expect(tabelas.index_with { |tabela| [colunas(tabela), indices(tabela), chaves(tabela)] }).to eq(do_schema)
  end

  it 'cria as colunas do melhor horário e do reenvio, com a conta sem cascata e o contato em cascata', :aggregate_failures do
    expect(colunas('horarios_de_resposta').keys).to eq(%w[id account_id contact_id por_hora respostas hora calculado_em])
    # O adaptador do Postgres devolve o tipo do elemento em sql_type ('integer') e marca o vetor em array?.
    por_hora = connection.columns('horarios_de_resposta').find { |coluna| coluna.name == 'por_hora' }
    expect([por_hora.sql_type, por_hora.array?]).to eq(['integer', true])
    expect(colunas('horarios_de_resposta')['hora'].first).to eq('smallint')
    expect(indices('horarios_de_resposta')['idx_horarios_de_resposta_contato']).to eq([%w[account_id contact_id], true])
    expect(chaves('horarios_de_resposta')).to eq([['accounts', nil], ['contacts', :cascade]])

    expect(colunas('campanha_opcoes_de_envio').keys).to include(
      'campanha_type', 'campanha_id', 'melhor_horario', 'reenvio_quem', 'reenvio_dias', 'reenvio_mensagem', 'reenvio_status',
      'reenvio_em', 'reenvio_campanha_type', 'reenvio_campanha_id'
    )
    expect(colunas('campanha_opcoes_de_envio')['melhor_horario']).to eq(['boolean', false, 'false'])
    expect(indices('campanha_opcoes_de_envio')['idx_campanha_opcoes_de_envio_campanha']).to eq([%w[campanha_type campanha_id], true])
    expect(indices('campanha_opcoes_de_envio')['idx_campanha_opcoes_de_envio_reenvio']).to eq([%w[reenvio_status reenvio_em], false])
    expect(chaves('campanha_opcoes_de_envio')).to eq([['accounts', nil]])
  end

  it 'apagar o contato apaga a hora dele' do
    contato = create(:contact)
    Autonomia::HorarioDeResposta.create!(account: contato.account, contact: contato, por_hora: Array.new(24, 0),
                                         calculado_em: Time.current)

    contato.delete

    expect(Autonomia::HorarioDeResposta.count).to eq(0)
  end
end
