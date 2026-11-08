require 'rails_helper'

# #2133 (revisão de banco, P1-1): apagar card dispara a cascata em crm_memoria_fatos.card_id. Sem índice que comece pela
# coluna, o Postgres lê a tabela inteira a cada card, e um lote de 5.000 cards estourava o statement_timeout de
# produção (14 s, config/database.yml) com 200 mil fatos de outras contas na tabela.
RSpec.describe Autonomia::ExclusaoDaConta do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:outra) { create(:account) }

  def executar(sql)
    ActiveRecord::Base.connection.execute(sql)
  end

  # 5.000 cards na conta que sai, copiados de um card de verdade.
  def criar_cards
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    modelo = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido')
    colunas = (Crm::Card.column_names - ['id']).join(', ')
    executar("INSERT INTO crm_cards (#{colunas}) SELECT #{colunas} FROM crm_cards, generate_series(1, 4999) WHERE id = #{modelo.id}")
  end

  # 200 mil fatos de outra conta, sem card: a cascata não apaga nenhum, mas lê todos se não houver índice.
  def criar_fatos_de_outra_conta
    contato = outra.contacts.create!(name: 'Cliente de outra conta')
    executar(<<~SQL.squish)
      INSERT INTO crm_memoria_fatos (account_id, contact_id, escopo, tipo, chave, fonte, status, situacao, valido_desde,
                                     registrado_em, gerado_por, created_at, updated_at)
      SELECT #{outra.id}, #{contato.id}, 'contato', 'fato', 'chave-' || g, 'sistema', 'confirmado', 'expirado', now(), now(),
             'spec', now(), now()
      FROM generate_series(1, 200000) g
    SQL
    executar('ANALYZE crm_memoria_fatos')
  end

  it 'apaga 5.000 cards com 200 mil fatos de outra conta na memória dentro do statement_timeout de produção' do
    criar_cards
    criar_fatos_de_outra_conta
    executar("SET LOCAL statement_timeout = '14s'")

    # Comando que passar de 14 s levanta ActiveRecord::QueryCanceled e o exemplo falha.
    described_class.new(account).perform

    expect(Crm::Card.where(account_id: account.id).count).to eq(0)
    expect(Crm::MemoriaFato.where(account_id: outra.id).count).to eq(200_000)
  end
end
