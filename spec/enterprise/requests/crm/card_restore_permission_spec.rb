require 'rails_helper'

# Funções personalizadas e Arquivados (#2095). Restaurar usa a chave de arquivar (`crm_delete_cards`): antes, desfazer
# o arquivamento passava pelo reabrir (`close?`, chave `crm_manage_cards`), e a função só com "Arquivar cards"
# arquivava sem conseguir desfazer. Restaurar funil é de quem gerencia funis (`crm_manage_pipelines`).
RSpec.describe 'Restaurar arquivados com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, inbox: inbox, owner: agent,
                              title: 'Renovação')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  # O reabrir antigo (/close e o lote) só segue a regra do restaurar com a flag das telas novas.
  before { account.enable_features!(:crm_arquivados) }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def archive_and_restore!
    delete "#{base}/cards/#{card.id}", headers: agent.create_new_auth_token, as: :json
    expect(card.reload.status).to eq('archived')
    post "#{base}/cards/#{card.id}/restore", headers: agent.create_new_auth_token, as: :json
  end

  it 'só com Arquivar cards, arquiva e restaura um card' do
    give_role(%w[crm_view crm_delete_cards conversation_participating_manage])

    archive_and_restore!

    expect(response).to have_http_status(:ok)
    expect(card.reload.status).to eq('open')
  end

  it 'só com Arquivar cards, restaura vários' do
    give_role(%w[crm_view crm_delete_cards conversation_participating_manage])
    card.update!(status: :archived)

    post "#{base}/cards/restore", params: { ids: [card.id] }, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload']).to eq('restored' => [card.id], 'skipped' => [])
  end

  it 'com Pode mexer, sem Arquivar, não restaura (nem um, nem vários) e a lista diz que não pode' do
    give_role(%w[crm_view crm_manage_cards conversation_participating_manage])
    card.update!(status: :archived)

    post "#{base}/cards/#{card.id}/restore", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "#{base}/cards/restore", params: { ids: [card.id] }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq('restored' => [], 'skipped' => [{ 'id' => card.id, 'error' => 'forbidden' }])

    get "#{base}/cards/archived", params: { pipeline_id: card.pipeline_id }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].map { |row| row.slice('id', 'can_restore') }).to eq([{ 'id' => card.id, 'can_restore' => false }])
    expect(card.reload.status).to eq('archived')
  end

  it 'com Pode mexer, sem Arquivar, também não restaura pelo reabrir antigo (/close e lote)' do
    give_role(%w[crm_view crm_manage_cards conversation_participating_manage])
    card.update!(status: :archived)

    post "#{base}/cards/#{card.id}/close", params: { result: 'reopen' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "#{base}/cards/bulk", params: { ids: [card.id], bulk_action: 'status', payload: { result: 'open' } },
                               headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('payload', 'failed')).to eq([{ 'id' => card.id, 'error' => 'forbidden' }])
    expect(card.reload.status).to eq('archived')
  end

  it 'sem a flag, Pode mexer reabre pelo /close como antes' do
    account.disable_features!(:crm_arquivados)
    give_role(%w[crm_view crm_manage_cards conversation_participating_manage])
    card.update!(status: :archived)

    post "#{base}/cards/#{card.id}/close", params: { result: 'reopen' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(card.reload.status).to eq('open')
  end

  it 'só com Arquivar cards, restaura pelo reabrir antigo (/close)' do
    give_role(%w[crm_view crm_delete_cards conversation_participating_manage])
    card.update!(status: :archived)

    post "#{base}/cards/#{card.id}/close", params: { result: 'reopen' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(card.reload.status).to eq('open')
  end

  it 'sem Valor de venda, a lista de arquivados esconde o valor do card de outra pessoa' do
    give_role(%w[crm_view crm_delete_cards conversation_participating_manage])
    card.update!(status: :archived, owner: admin, value_cents: 150_000)

    get "#{base}/cards/archived", params: { pipeline_id: card.pipeline_id }, headers: agent.create_new_auth_token

    expect(response.parsed_body['payload'].first).to include('value_cents' => nil, 'value_hidden' => true)
  end

  describe 'funil' do
    let(:pipeline) { pipeline_and_stage.first }

    before do
      create_crm_pipeline(account: account, user: admin, name: 'Outro')
      pipeline.archived!
    end

    it 'com Gerenciar funis, lista os arquivados e restaura' do
      give_role(%w[crm_view crm_manage_pipelines])

      get "#{base}/pipelines", params: { status: 'archived' }, headers: agent.create_new_auth_token
      expect(response.parsed_body['payload'].pluck('id')).to eq([pipeline.id])

      post "#{base}/pipelines/#{pipeline.id}/restore", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(pipeline.reload).to be_active
    end

    it 'só com Ver CRM não restaura nem vê a prévia do arquivamento' do
      give_role(%w[crm_view])

      post "#{base}/pipelines/#{pipeline.id}/restore", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/pipelines/#{pipeline.id}/archive_preview", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(pipeline.reload).to be_archived
    end
  end
end
