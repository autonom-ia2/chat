require 'rails_helper'

# #1140 (correção 3): a tela de Atribuição avisa quando a pessoa fixa de uma regra não pode receber numa caixa do funil.
# Quem pode receber vem daqui, pela regra do motor de entrega (Crm::Entrega::QuemCuida).
RSpec.describe 'CRM AI settings API: quem recebe por caixa', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:ana) { create_crm_agent(account: account, name: 'Ana Ribeiro').first }
  let(:bruno) { create_crm_agent(account: account, name: 'Bruno Lima').first }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:whatsapp) { create_crm_inbox(account: account, name: 'WhatsApp', members: [ana, bruno]) }
  let(:instagram) { create_crm_inbox(account: account, name: 'Instagram', members: [ana, bruno]) }
  let(:contact) { create(:contact, account: account) }

  before do
    [whatsapp, instagram].each { |inbox| account.crm_pipeline_inboxes.create!(inbox: inbox, pipeline: pos_venda.first) }
    # No WhatsApp, Bruno só vê as dele; no Instagram, cuida de tudo.
    Crm::InboxAgentAccess.create!(account: account, inbox: whatsapp, user: bruno, all_pipelines: true, triage: true, only_own: true)
  end

  def recebem
    get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pos_venda.first.id}/ai_settings", params: { quem_recebe: 1 }, headers: auth_headers(admin)
    response.parsed_body.dig('payload', 'recebem_por_caixa')
  end

  it 'lists, per inbox of the funnel, who can receive a conversation from it' do
    expect(recebem).to eq([
                            { 'inbox_id' => instagram.id, 'name' => 'Instagram', 'user_ids' => [ana.id, bruno.id] },
                            { 'inbox_id' => whatsapp.id, 'name' => 'WhatsApp', 'user_ids' => [ana.id] }
                          ])
  end

  it 'is what the delivery engine decides for a conversation of the funnel in that inbox' do
    conversa = create(:conversation, account: account, inbox: whatsapp, contact: contact, status: :open).reload
    card = account.crm_cards.create!(pipeline: pos_venda.first, stage: pos_venda.last, contact: contact, title: 'Pós',
                                     primary_conversation: conversa, inbox: whatsapp)

    motor = Crm::Entrega::QuemCuida.new(conversation: conversa, card: card).pessoas.map(&:id)

    expect(recebem.find { |caixa| caixa['inbox_id'] == whatsapp.id }['user_ids']).to eq(motor)
  end

  it 'leaves the list out unless the screen asks for it (the list of funnels reads every funnel)' do
    get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pos_venda.first.id}/ai_settings", headers: auth_headers(admin)

    expect(response.parsed_body['payload']).not_to have_key('recebem_por_caixa')
  end
end
