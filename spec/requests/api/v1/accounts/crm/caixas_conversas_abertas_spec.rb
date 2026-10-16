require 'rails_helper'

# Canais de cada funil (#1140, decisão 7): a caixa aberta traz quantas conversas em aberto cada funil tem nela, para a
# tela avisar antes de tirar um funil.
RSpec.describe 'CRM Caixas no CRM: conversas abertas por funil', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp', members: [admin]) }
  let(:outra) { create_crm_inbox(account: account, name: 'Instagram', members: [admin]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:contact) { create(:contact, account: account) }

  before { account.enable_features!('crm_configurar_caixas') }

  def card!(funil, caixa: inbox, status: :open, card_status: :open)
    conversa = create(:conversation, account: account, inbox: caixa, contact: contact, status: status)
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, contact: contact, title: funil.first.name,
                              primary_conversation: conversa, inbox: caixa, status: card_status)
  end

  it 'counts open and pending conversations of this inbox held by an open card (main or linked), per funnel' do
    2.times { card!(pos_venda) }
    card!(pos_venda, status: :pending)
    card!(vendas)
    card!(pos_venda, status: :resolved)
    card!(pos_venda, card_status: :won)
    card!(pos_venda, caixa: outra)
    # Ligada a um card de outra caixa conta; a principal também ligada ao próprio card conta uma vez só.
    ligada = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)
    Crm::CardConversation.create!(account: account, card: card!(pos_venda, caixa: outra), conversation: ligada)
    dupla = card!(vendas)
    Crm::CardConversation.create!(account: account, card: dupla, conversation: dupla.primary_conversation)

    get "/api/v1/accounts/#{account.id}/crm/caixas/#{inbox.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'caixa', 'conversas_abertas'))
      .to eq(pos_venda.first.id.to_s => 4, vendas.first.id.to_s => 2)
  end

  it 'leaves the count out of the list of inboxes' do
    card!(pos_venda)

    get "/api/v1/accounts/#{account.id}/crm/caixas", headers: auth_headers(admin)

    caixa = response.parsed_body.dig('payload', 'caixas').find { |item| item.dig('inbox', 'id') == inbox.id }
    expect(caixa).not_to have_key('conversas_abertas')
  end
end
