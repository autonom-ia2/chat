require 'rails_helper'

# Acesso por funil (#1148) e Arquivados (#2095): quem vê o card arquivado (é o dono) mas não tem o funil dele não o
# restaura por nenhum caminho; a linha diz isso (`can_restore: false`) e o lote o pula como `forbidden`.
RSpec.describe 'Restaurar card visível sem o funil dele', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agente]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let!(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Vendas', inbox: inbox, owner: agente,
                              contact: create(:contact, account: account))
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/cards" }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!(:crm_arquivados)
    acesso = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agente, all_pipelines: false, triage: false)
    acesso.agent_pipelines.create!(account: account, pipeline: sinistro.first)
    Crm::Cards::Archiver.new(card: card, actor: admin).perform
  end

  it 'vê a linha, sem poder restaurar' do
    # Sem o funil na lista de funis da pessoa, a linha aparece na busca em todos os funis.
    get "#{base}/archived", headers: agente.create_new_auth_token

    expect(response).to have_http_status(:ok)
    linha = response.parsed_body['payload'].find { |item| item['id'] == card.id }
    expect(linha).to include('can_restore' => false)
  end

  it 'o lote pula o card como forbidden, e o card único é recusado' do
    post "#{base}/restore", params: { ids: [card.id] }, headers: agente.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq('restored' => [], 'skipped' => [{ 'id' => card.id, 'error' => 'forbidden' }])

    post "#{base}/#{card.id}/restore", headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    expect(card.reload).to be_archived
  end
end
