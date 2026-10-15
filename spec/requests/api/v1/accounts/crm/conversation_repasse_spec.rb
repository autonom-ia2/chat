require 'rails_helper'

# Decisão "a" (#1606): a sugestão "O assunto virou X" pela API dos assuntos da conversa. Só quem está com a conversa a
# recebe e responde.
RSpec.describe 'CRM conversation repasse API', type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Seguros') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia Agentes') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:seguros) { create_crm_pipeline(account: account, user: admin, name: 'Seguros') }
  let(:agentes) { create_crm_pipeline(account: account, user: admin, name: 'Agentes de IA') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open, assignee: ana).reload }
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}" }
  let(:card) { card_em(agentes) }

  before do
    allow(Crm::Access::AccountFlag).to receive(:any?).and_return(true)
    [ana, bia].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online', bia.id.to_s => 'online' })
    acesso(ana, seguros)
    acesso(bia, agentes)
    card_em(seguros, focused_at: 1.minute.ago)
    card
    Crm::Repasse.sugerir!(conversation.reload)
  end

  def acesso(user, funil)
    row = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    row.agent_pipelines.create!(account: account, pipeline: funil.first)
  end

  def card_em((pipeline, stage), focused_at: Time.current)
    novo = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: pipeline.name,
                                     primary_conversation: conversation, inbox: inbox)
    Crm::CardConversation.find_or_create_by!(account: account, card: novo, conversation: conversation).update!(focused_at: focused_at)
    novo
  end

  it 'mostra a sugestão só para quem está com a conversa' do
    get "#{base_url}/cards", headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['repasse']).to eq('card_id' => card.id, 'pipeline_name' => 'Agentes de IA')

    get "#{base_url}/cards", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['repasse']).to be_nil
  end

  it 'Ficar com a conversa apaga a sugestão' do
    post "#{base_url}/repasse/manter", params: { card_id: card.id }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(conversation.reload.additional_attributes[Crm::Repasse::CHAVE]).to be_nil
    expect(conversation.assignee).to eq(ana)
  end

  it 'Passar para a equipe tira a conversa dela; outra pessoa não responde pela dona' do
    post "#{base_url}/repasse", params: { card_id: card.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.conversation_cards.repasse_nao_e_seu')

    agentes.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    post "#{base_url}/repasse", params: { card_id: card.id }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(conversation.reload.assignee).to eq(bia)
    expect(Crm::Passagem.where(conversation_id: conversation.id, motivo: 'assunto').sole)
      .to have_attributes(de_id: ana.id, para_id: bia.id, pedida_por_id: ana.id)
  end
end
