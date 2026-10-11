require 'rails_helper'

# Revisão de segurança da parte C (#1148): os caminhos de escalada achados viram regressão. Agente restrito ao funil
# Vendas tenta ganhar a conversa de Sinistro.
RSpec.describe 'Acesso por funil: escaladas pelo card', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:sinistro_agent) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent, sinistro_agent]) }
  let(:instagram) { create_crm_inbox(account: account, name: 'Instagram', members: [vendas_agent, sinistro_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:contact) { create(:contact, account: account) }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [[vendas_agent, vendas], [sinistro_agent, sinistro]].each do |user, (pipeline, _stage)|
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: pipeline)
    end
  end

  def sees?(user)
    Crm::Access::ConversationScope.new(user: user, account: account).allows?(conversa.reload)
  end

  def move(card, stage)
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/move",
         params: { stage_id: stage.id }, headers: vendas_agent.create_new_auth_token, as: :json
  end

  it 'card de outra caixa vinculado à conversa: mover para Vendas não abre a conversa' do
    card = account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'IG', inbox: instagram, contact: contact)
    Crm::CardConversation.create!(account: account, card: card, conversation: conversa)

    move(card, vendas.last)

    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    expect(sees?(vendas_agent)).to be(false)
  end

  it 'ser só dona do card de Sinistro não deixa movê-lo para Vendas' do
    card = account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'S', inbox: inbox, contact: contact,
                                     primary_conversation: conversa, owner: vendas_agent)

    move(card, vendas.last)

    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    expect(sees?(vendas_agent)).to be(false)
  end

  it 'criar card com conversa num funil que a pessoa não tem é recusado' do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'V', inbox: inbox, contact: contact,
                              primary_conversation: conversa)

    expect do
      post "/api/v1/accounts/#{account.id}/crm/cards",
           params: { conversation_id: conversa.id, pipeline_id: sinistro.first.id, stage_id: sinistro.last.id, title: 'x',
                     new_subject: true },
           headers: vendas_agent.create_new_auth_token, as: :json
    end.not_to change(Crm::Card, :count)
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end

  it 'o vínculo feito pelo linker sincroniza a conversa (o reload zerava saved_changes)' do
    card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'V', inbox: inbox, contact: contact)

    expect { Crm::Cards::ConversationLinker.new(card: card, conversation: conversa, actor: admin, primary: true).link }
      .to have_enqueued_job(Crm::Access::VisibilitySyncJob).with(array_including(conversa.id)).at_least(:once)
  end

  it 'a partir da conversa, o assunto atual de outro funil não é devolvido a quem não o vê' do
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'S', inbox: inbox, contact: contact,
                              primary_conversation: conversa)
    vendas_card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'V', inbox: inbox, contact: contact)
    Crm::CardConversation.create!(account: account, card: vendas_card, conversation: conversa)

    handler = Crm::Cards::FromConversationHandler.new(account: account, user: vendas_agent, conversation: conversa,
                                                      requested_params: {})

    expect(handler.perform { nil }.card).to eq(vendas_card)
  end
end
