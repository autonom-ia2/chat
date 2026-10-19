require 'rails_helper'

# Funções personalizadas, lote 5b (#1849, decisão D7): sem "Ver contatos", o card do CRM leva só nome, telefone e e-mail
# do contato, sem empresa, campos nem etiquetas do contato. Vincular um contato ao card devolve os dados dele, então só
# vincula quem vê esse contato (a base, ou o contato de uma conversa que a pessoa vê).
RSpec.describe 'Card do CRM e Ver contatos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:contact) do
    create(:contact, account: account, name: 'Marcos Prado', email: 'marcos@example.test', phone_number: '+5511987650042',
                     custom_attributes: { 'cpf' => '123' })
  end
  let(:outro) { create(:contact, account: account, name: 'Outro da base', email: 'outro@example.test') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact,
                              primary_conversation: conversation, inbox: inbox, owner: agent, title: 'Renovação')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  describe 'sem Ver contatos' do
    before { give_role(%w[crm_view crm_manage_cards conversation_participating_manage]) }

    it 'o card leva só nome, telefone e e-mail do contato' do
      get "#{base}/cards/#{card.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload['contact'].keys).to match_array(%w[id name phone_number email])
      expect(payload).not_to have_key('company')
      expect(payload['contact_labels']).to eq([])
    end

    it 'o quadro leva só nome e telefone do contato' do
      card
      get "#{base}/kanban", params: { pipeline_id: pipeline_and_stage.first.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      cards = response.parsed_body['payload']['stages'].flat_map { |stage| stage['cards'] }
      expect(cards.first['contact'].keys).to match_array(%w[id name phone_number])
      expect(cards.first['company']).to be_nil
    end

    it 'não vincula contato da base, nem pelo vínculo nem na criação' do
      post "#{base}/cards/#{card.id}/link_contact", params: { contact_id: outro.id }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(card.reload.contact_id).to eq(contact.id)

      params = { card: { pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id, title: 'Novo',
                         contact_id: outro.id } }
      post "#{base}/cards", params: params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'o lembrete não traz a empresa' do
      account.enable_features!(:companies)
      company = create(:company, account: account, name: 'Prado Seguros')
      account.crm_follow_ups.create!(card: card, contact: contact, company: company, created_by: admin, title: 'Ligar',
                                     follow_up_type: :task, automation_mode: :reminder_only, due_at: 1.day.from_now, timezone: 'UTC')

      get "#{base}/follow_ups", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      lembrete = response.parsed_body['payload'].first
      expect(lembrete['title']).to eq('Ligar')
      expect(lembrete).not_to have_key('company')
    end

    it 'vincula o contato de uma conversa que vê' do
      card.update!(contact: outro)
      post "#{base}/cards/#{card.id}/link_contact", params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(card.reload.contact_id).to eq(contact.id)
    end
  end

  it 'com Ver contatos o card leva o contato completo' do
    give_role(%w[crm_view crm_manage_cards conversation_participating_manage contact_view])
    get "#{base}/cards/#{card.id}", headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('payload', 'contact', 'custom_attributes')).to eq('cpf' => '123')
  end

  it 'o agente sem função continua vinculando qualquer contato' do
    avulso = account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, owner: agent, title: 'Avulso')
    post "#{base}/cards/#{avulso.id}/link_contact", params: { contact_id: outro.id }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end
end
