require 'rails_helper'

# #2084: com a flag contato_relacao ligada, card de contato fora do funil (parceiro do mercado, não é negócio) sai dos
# Números, das metas e dos relatórios do CRM, por um critério só (Crm::Relacao.cards_do_funil / condicao_sql).
RSpec.describe 'Crm::Relacao nos Números' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [user]) }
  let(:sale) { create_crm_pipeline(account: account, user: user) }
  let(:interessado) { create(:contact, account: account) }
  let(:parceiro) { create(:contact, account: account, relacao: :parceiro) }
  let!(:do_interessado) { card(interessado) }
  let!(:do_parceiro) { card(parceiro) }

  def card(contact, status: :open)
    pipeline, stage = sale
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, primary_conversation: conversation, contact: contact,
                                     owner: user, title: "Assunto #{SecureRandom.hex(3)}", currency: 'BRL', value_cents: 100)
    card.update!(status: status) unless status == :open
    card
  end

  def resumo
    Crm::Reports::Summary.new(account: account, params: { pipeline_id: sale.first.id }).perform
  end

  def abertos_da_equipe
    Crm::Numeros::CardsDaEquipe.new(account: account, pipelines: account.crm_pipelines.active).abertos(:venda)
  end

  before do
    card(interessado, status: :won)
    card(parceiro, status: :won)
  end

  it 'com a flag desligada, tudo conta como antes' do
    expect(resumo).to include(open_count: 2, won_count: 2)
    expect(abertos_da_equipe).to contain_exactly(do_interessado, do_parceiro)
    expect(Crm::Relacao.condicao_sql(account)).to be_nil
  end

  it 'com a flag ligada, o card do parceiro sai do relatório e dos Números da equipe' do
    account.enable_features!('contato_relacao')

    expect(resumo).to include(open_count: 1, won_count: 1)
    expect(abertos_da_equipe).to contain_exactly(do_interessado)
  end

  it 'com a flag ligada, a venda do parceiro sai do crédito do mês e das metas' do
    mes = 1.day.ago..1.day.from_now
    credito = -> { Crm::Numeros::Credito.new(account: account, user: user, range: mes).perform }
    vendido = -> { Crm::Metas::Vendido.new(account: account, range: mes).por_pessoa.values.sum }
    expect([credito.call[:vendas], vendido.call]).to eq([2, 200])

    account.enable_features!('contato_relacao')

    expect([credito.call[:vendas], vendido.call]).to eq([1, 100])
  end

  it 'com a flag ligada, card sem contato continua contando' do
    account.enable_features!('contato_relacao')
    do_parceiro.update_columns(contact_id: nil) # rubocop:disable Rails/SkipsModelValidations

    expect(Crm::Relacao.cards_do_funil(account)).to include(do_parceiro)
  end

  it 'a condição em SQL é a mesma regra do escopo' do
    account.enable_features!('contato_relacao')

    pelo_sql = account.crm_cards.where(Crm::Relacao.condicao_sql(account))
    expect(pelo_sql).to match_array(Crm::Relacao.cards_do_funil(account))
    expect(pelo_sql).not_to include(do_parceiro)
  end
end
