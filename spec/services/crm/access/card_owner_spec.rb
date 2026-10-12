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

    it 'passa para outra pessoa que tem o funil' do
      colega = create_crm_agent(account: account, name: 'Vendas 2').first
      inbox.add_members([colega.id])
      restrict(colega, vendas)

      set_owner(colega)

      expect(response).to have_http_status(:ok)
      expect(card.reload.owner_id).to eq(colega.id)
    end

    it 'o upsert por external_id também recusa' do
      card.update!(external_id: 'ext-1')

      post "/api/v1/accounts/#{account.id}/crm/cards",
           params: { external_id: 'ext-1', pipeline_id: vendas.first.id, stage_id: vendas.last.id, title: 'Vendas', owner_id: sinistro_agent.id },
           headers: vendas_agent.create_new_auth_token, as: :json

      expect(response.parsed_body['error']).to eq('crm.owner_without_funnel')
      expect(card.reload.owner_id).to eq(vendas_agent.id)
    end

    it 'o atendente sem o funil não vira dono pela conversa (sincronização e vínculo)' do
      conversa = create_crm_conversation(account: account, inbox: inbox, contact: card.contact, assignee: sinistro_agent)
      sem_dono = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Sem dono', inbox: inbox,
                                           contact: card.contact, primary_conversation: conversa)

      Crm::Conversations::CardSyncer.new(conversation: conversa).perform
      expect(sem_dono.reload.owner_id).to be_nil

      outro = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Outro', inbox: inbox, contact: card.contact)
      Crm::Cards::ConversationLinker.new(card: outro, conversation: conversa, actor: vendas_agent, primary: true).link
      expect(outro.reload.owner_id).to be_nil
    end

    it 'token de integração (n8n, MCP) escolhe qualquer pessoa, como o administrador; bot não' do
      robo = create_crm_agent(account: account, name: 'n8n').first
      AccountUser.find_by(account: account, user: robo).update!(integration: true)
      args = { inbox_id: inbox.id, pipeline_id: vendas.first.id }

      expect(Crm::Access::CardGuard.new(user: robo, account: account).owner_allowed?(sinistro_agent.id, **args)).to be(true)
      expect(Crm::Access::CardGuard.new(user: create(:agent_bot), account: account).owner_allowed?(sinistro_agent.id, **args)).to be(false)
    end

    it 'o administrador escolhe qualquer pessoa' do
      set_owner(sinistro_agent, as: admin)

      expect(response).to have_http_status(:ok)
      expect(card.reload.owner_id).to eq(sinistro_agent.id)
    end

    it 'card criado da conversa: atendente sem o funil não vira dono (fica quem criou)' do
      conversa = create_crm_conversation(account: account, inbox: inbox, contact: card.contact, assignee: sinistro_agent)

      novo = Crm::Cards::Creator.new(account: account, user: vendas_agent, conversation: conversa,
                                     params: { pipeline_id: vendas.first.id, stage_id: vendas.last.id, title: 'Novo' }).perform

      expect(novo.owner_id).to eq(vendas_agent.id)
    end

    it 'atendente com o funil, ou em "Só as suas", vira dono pela conversa' do
      colega = create_crm_agent(account: account, name: 'Só as suas').first
      inbox.add_members([colega.id])
      Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: colega, all_pipelines: false, triage: false, only_own: true)
      [vendas_agent, colega].each do |atendente|
        conversa = create_crm_conversation(account: account, inbox: inbox, contact: card.contact, assignee: atendente)
        sem_dono = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Sem dono', inbox: inbox,
                                             contact: card.contact, primary_conversation: conversa)

        Crm::Conversations::CardSyncer.new(conversation: conversa).perform

        expect(sem_dono.reload.owner_id).to eq(atendente.id)
      end
    end

    it 'o lote também recusa, card a card' do
      post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
           params: { ids: [card.id], action_name: 'assign', payload: { owner_id: sinistro_agent.id } },
           headers: vendas_agent.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'failed')).to contain_exactly({ 'id' => card.id, 'error' => 'crm.owner_without_funnel' })
      expect(card.reload.owner_id).to eq(vendas_agent.id)
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'o atendente vira dono pela conversa, como antes' do
      conversa = create_crm_conversation(account: account, inbox: inbox, contact: card.contact, assignee: sinistro_agent)
      sem_dono = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Sem dono', inbox: inbox,
                                           contact: card.contact, primary_conversation: conversa)

      Crm::Conversations::CardSyncer.new(conversation: conversa).perform

      expect(sem_dono.reload.owner_id).to eq(sinistro_agent.id)
    end

    it 'qualquer pessoa vira dona, como antes' do
      set_owner(sinistro_agent)

      expect(response).to have_http_status(:ok)
      expect(card.reload.owner_id).to eq(sinistro_agent.id)
    end
  end
end
