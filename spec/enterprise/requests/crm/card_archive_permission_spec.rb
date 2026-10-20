require 'rails_helper'

# Funções personalizadas, lote 6 (#1874). Arquivar card tem chave própria (`crm_delete_cards`, decisão 7.4-2), e a ação
# em massa passa pela mesma regra da ação de um card só (brecha A3): sem a chave da ação, todo card volta `forbidden` e
# nada muda; a recusa por funil continua card a card. Sincronizar reunião grava e pede o mesmo que mexer no card.
RSpec.describe 'Arquivar cards e ação em massa do CRM', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact,
                              primary_conversation: conversation, inbox: inbox, owner: agent, title: 'Renovação')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true' do
      example.run
    end
  end

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def bulk(action, payload = {})
    post "#{base}/cards/bulk", params: { ids: [card.id], action_name: action, payload: payload },
                               headers: agent.create_new_auth_token, as: :json
    response.parsed_body['payload']
  end

  def archive!
    delete "#{base}/cards/#{card.id}", headers: agent.create_new_auth_token, as: :json
  end

  def forbidden_result
    { 'updated' => [], 'failed' => [{ 'id' => card.id, 'error' => 'forbidden' }] }
  end

  describe 'só com Ver CRM' do
    before { give_role(%w[crm_view conversation_participating_manage]) }

    it 'nenhuma ação em massa muda o card' do
      expect(bulk('move', stage_id: pipeline_and_stage.last.id)).to eq(forbidden_result)
      expect(bulk('assign', owner_id: admin.id)).to eq(forbidden_result)
      expect(bulk('status', result: 'won')).to eq(forbidden_result)
      expect(bulk('delete')).to eq(forbidden_result)

      card.reload
      expect([card.status, card.owner_id]).to eq(['open', agent.id])
    end

    it 'não arquiva um card' do
      archive!

      expect(response).to have_http_status(:unauthorized)
      expect(card.reload.status).to eq('open')
    end
  end

  describe 'com Pode mexer, sem Arquivar' do
    before { give_role(%w[crm_view crm_manage_cards conversation_participating_manage]) }

    it 'troca o dono e fecha em massa, mas não arquiva' do
      expect(bulk('assign', owner_id: admin.id)).to eq('updated' => [card.id], 'failed' => [])
      expect(bulk('status', result: 'won')).to eq('updated' => [card.id], 'failed' => [])
      expect(bulk('delete')).to eq(forbidden_result)
      expect(card.reload.status).to eq('won')
    end

    it 'não arquiva um card' do
      archive!

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'só com Mover cards move em massa e não troca o dono' do
    give_role(%w[crm_view crm_move_cards conversation_participating_manage])

    expect(bulk('move', stage_id: pipeline_and_stage.last.id)).to eq('updated' => [card.id], 'failed' => [])
    expect(bulk('assign', owner_id: admin.id)).to eq(forbidden_result)
  end

  it 'com Arquivar cards arquiva um card e vários' do
    give_role(%w[crm_view crm_delete_cards conversation_participating_manage])
    other = account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, inbox: inbox,
                                      contact: contact, primary_conversation: conversation, owner: agent, title: 'Outro')

    archive!
    expect(response).to have_http_status(:ok)
    post "#{base}/cards/bulk", params: { ids: [other.id], action_name: 'delete' }, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload']).to eq('updated' => [other.id], 'failed' => [])
    expect([card.reload.status, other.reload.status]).to eq(%w[archived archived])
  end

  it 'Administrador do CRM arquiva' do
    give_role(%w[crm_admin conversation_participating_manage])

    expect(bulk('delete')).to eq('updated' => [card.id], 'failed' => [])
  end

  it 'agente sem função continua arquivando' do
    archive!

    expect(response).to have_http_status(:ok)
    expect(card.reload.status).to eq('archived')
  end

  describe 'sincronizar reunião' do
    # A agenda da caixa e os convidados não importam aqui: a sincronização é trocada por um dublê.
    let(:meeting) do
      account.crm_meetings.new(card: card, inbox: inbox, created_by: admin, title: 'Visita', provider: :google,
                               starts_at: 1.day.from_now, ends_at: 1.day.from_now + 30.minutes).tap { |m| m.save!(validate: false) }
    end

    before { allow(Crm::Meetings::SyncService).to receive(:new).and_return(instance_double(Crm::Meetings::SyncService, perform: true)) }

    it 'só com Ver CRM é recusado' do
      give_role(%w[crm_view conversation_participating_manage])
      post "#{base}/meetings/#{meeting.id}/sync", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Crm::Meetings::SyncService).not_to have_received(:new)
    end

    it 'com Pode mexer sincroniza' do
      give_role(%w[crm_view crm_manage_cards conversation_participating_manage])
      post "#{base}/meetings/#{meeting.id}/sync", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  # Robôs (n8n) com token de integração do CRM: o escopo do token vira o cargo gerenciado dele, e o token enxerga o card
  # avulso que ele mesmo criou (dono = usuário do token).
  describe 'token de integração do CRM' do
    def token_card(scopes)
      token = Crm::IntegrationToken.create!(account: account, created_by: admin, name: 'n8n', scopes: scopes)
      card = account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Pelo site',
                                       owner: token.account_user.user)
      [card, { api_access_token: token.access_token.token }]
    end

    it 'arquiva com o escopo Arquivar cards e não só com Pode mexer' do
      card, headers = token_card(%w[crm_view crm_manage_cards])
      delete "#{base}/cards/#{card.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      card, headers = token_card(%w[crm_view crm_delete_cards])
      delete "#{base}/cards/#{card.id}", headers: headers, as: :json
      expect(card.reload.status).to eq('archived')
    end

    it 'continua editando e movendo como antes' do
      card, headers = token_card(%w[crm_view crm_manage_cards])
      patch "#{base}/cards/#{card.id}", params: { card: { title: 'Pelo n8n' } }, headers: headers, as: :json
      expect(card.reload.title).to eq('Pelo n8n')

      card, headers = token_card(%w[crm_view crm_move_cards])
      post "#{base}/cards/#{card.id}/move", params: { stage_id: pipeline_and_stage.last.id }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
