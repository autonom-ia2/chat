require 'rails_helper'

# Dono do card (#1148, decisão do Rodrigo em 11/10): só vira dono quem tem o funil do card na caixa dele; o
# administrador escolhe qualquer pessoa. Sem acesso por funil, nada muda.
RSpec.describe 'Acesso por funil: dono do card', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:sinistro_agent) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:livre_agent) { create_crm_agent(account: account, name: 'Sem restrição').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent, sinistro_agent, livre_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Vendas', inbox: inbox, owner: vendas_agent,
                              contact: create(:contact, account: account))
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def restrict(user, (pipeline, _stage))
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  def set_owner(owner, as: vendas_agent)
    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { owner_id: owner.id } }, headers: as.create_new_auth_token, as: :json
  end

  describe 'com acesso por funil' do
    before do
      restrict(vendas_agent, vendas)
      restrict(sinistro_agent, sinistro)
    end

    it 'não passa o card para quem não tem o funil dele' do
      set_owner(sinistro_agent)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.owner_without_funnel')
      expect(card.reload.owner_id).to eq(vendas_agent.id)
    end

    it 'passa para quem tem o funil ou não tem restrição na caixa' do
      set_owner(livre_agent)

      expect(response).to have_http_status(:ok)
      expect(card.reload.owner_id).to eq(livre_agent.id)
    end

    it 'o administrador escolhe qualquer pessoa' do
      set_owner(sinistro_agent, as: admin)

      expect(response).to have_http_status(:ok)
      expect(card.reload.owner_id).to eq(sinistro_agent.id)
    end

    # Criar não precisa da regra: sem conversa, quem não é administrador só cria card com si mesmo de dono
    # (Crm::Cards::CreateAuthorizer); da conversa, o dono é o atendente dela (Crm::Cards::Creator).

    it 'o lote também recusa, card a card' do
      post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
           params: { ids: [card.id], action_name: 'assign', payload: { owner_id: sinistro_agent.id } },
           headers: vendas_agent.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'failed')).to contain_exactly({ 'id' => card.id, 'error' => 'crm.owner_without_funnel' })
      expect(card.reload.owner_id).to eq(vendas_agent.id)
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'qualquer pessoa vira dona, como antes' do
      set_owner(sinistro_agent)

      expect(response).to have_http_status(:ok)
      expect(card.reload.owner_id).to eq(sinistro_agent.id)
    end
  end
end
