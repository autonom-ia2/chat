require 'rails_helper'

# Com quem fica o card da Prospecção nova (#2694, F2). Só quem gere funis (crm_manage_pipelines, crm_admin ou o
# administrador) escolhe outra pessoa; quem só tem crm_manage_cards manda e o card fica com ela. O dono escolhido
# precisa enxergar o funil: o card nasce sem caixa, e o CardGuard sozinho deixaria qualquer pessoa.
RSpec.describe 'Autonomia prospecting card owner', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:colleague) { create_crm_agent(account: account, name: 'Lucas Andrade').first }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def create_lead(index, owner: nil)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "place-owner-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-100#{index}", country: 'BR'
    )
    return lead if owner.nil?

    # O agente só age sobre os leads das próprias buscas (#732, item 6).
    search = Autonomia::Prospecting::Search.create!(account: account, user: owner, query: "busca #{index}", provider: 'mock',
                                                    status: 'completed', metadata: { 'lead_ids' => [lead.id] })
    lead.tap { |item| item.update!(search: search) }
  end

  def send_to_crm(user, lead_ids, **extra)
    post "#{base_url}/crm_cards", params: { lead_ids: lead_ids, pipeline_id: pipeline.id, stage_id: stage.id, **extra },
                                  headers: auth_headers(user), as: :json
  end

  # O funil fica ligado a uma caixa em que o colega não está, e o colega tem acesso por funil restrito noutra caixa.
  def restrict_colleague_out_of_pipeline
    Crm::PipelineInbox.create!(account: account, inbox: create_crm_inbox(account: account, name: 'Filial'), pipeline: pipeline)
    own_inbox = create_crm_inbox(account: account, name: 'Vendas', members: [colleague])
    other_pipeline = create_crm_pipeline(account: account, user: admin, name: 'Outro').first
    Crm::PipelineInbox.create!(account: account, inbox: own_inbox, pipeline: other_pipeline)
    access = Crm::InboxAgentAccess.create!(account: account, inbox: own_inbox, user: colleague, all_pipelines: false, triage: false,
                                           only_own: false)
    access.agent_pipelines.create!(account: account, pipeline: other_pipeline)
  end

  describe 'POST leads/crm_cards com owner_id' do
    it 'função só com crm_manage_cards não troca o dono (403) e nada é gravado' do
      agent = agent_with(%w[prospecting_manage crm_manage_cards])

      send_to_crm(agent, [create_lead(1, owner: agent).id], owner_id: colleague.id)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_forbidden')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.crm_send.errors.owner_forbidden'))
      expect(account.crm_cards.count).to eq(0)
    end

    it 'função só com crm_manage_cards mandando o próprio id segue o fluxo de hoje' do
      agent = agent_with(%w[prospecting_manage crm_manage_cards])

      send_to_crm(agent, [create_lead(1, owner: agent).id], owner_id: agent.id)

      expect(response).to have_http_status(:ok)
      expect(account.crm_cards.sole.owner_id).to eq(agent.id)
    end

    it 'administrador escolhe o dono, e o card fica com ele' do
      send_to_crm(admin, [create_lead(1).id, create_lead(2).id], owner_id: colleague.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'created').size).to eq(2)
      expect(account.crm_cards.pluck(:owner_id)).to eq([colleague.id, colleague.id])
    end

    it 'função com crm_manage_pipelines escolhe o dono' do
      agent = agent_with(%w[prospecting_manage crm_manage_cards crm_manage_pipelines])

      send_to_crm(agent, [create_lead(1, owner: agent).id], owner_id: colleague.id)

      expect(response).to have_http_status(:ok)
      expect(account.crm_cards.sole.owner_id).to eq(colleague.id)
    end

    it 'dono sem acesso ao funil é recusado (422), mesmo pelo administrador' do
      restrict_colleague_out_of_pipeline

      send_to_crm(admin, [create_lead(1).id], owner_id: colleague.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_not_allowed')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.crm_send.errors.owner_not_allowed'))
      expect(account.crm_cards.count).to eq(0)
    end

    it 'dono de outra conta é recusado (422)' do
      other = create(:account)
      stranger = create(:user, :administrator, account: other)

      send_to_crm(admin, [create_lead(1).id], owner_id: stranger.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_not_allowed')
      expect(account.crm_cards.count).to eq(0)
    end

    it 'função com crm_admin escolhe o dono' do
      agent = agent_with(%w[prospecting_manage crm_admin])

      send_to_crm(agent, [create_lead(1, owner: agent).id], owner_id: colleague.id)

      expect(response).to have_http_status(:ok)
      expect(account.crm_cards.sole.owner_id).to eq(colleague.id)
    end

    # O agente sem função não tem a Prospecção (prospecting_manage): para no portão do módulo (401), antes do dono. Nem
    # pela Prospecção nem pela chave de funis ele troca o dono.
    it 'agente sem função mandando owner_id é recusado e nada é gravado' do
      agent = create(:user, account: account, role: :agent)

      send_to_crm(agent, [create_lead(1, owner: agent).id], owner_id: colleague.id)

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Prospecting::CrmCardOwner.can_choose?(agent.account_users.find_by(account: account))).to be(false)
      expect(account.crm_cards.count).to eq(0)
    end

    it 'dono que não vê os cards do CRM (função sem crm_view) é recusado (422)' do
      sem_crm = agent_with(%w[prospecting_manage])

      send_to_crm(admin, [create_lead(1).id], owner_id: sem_crm.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_not_allowed')
      expect(account.crm_cards.count).to eq(0)
    end

    it 'sem owner_id, igual a hoje: o card fica com quem mandou' do
      send_to_crm(admin, [create_lead(1).id])

      expect(response).to have_http_status(:ok)
      expect(account.crm_cards.sole.owner_id).to eq(admin.id)
    end
  end

  # No envio individual o owner_id também vai na raiz, fora de crm_card: o mesmo contrato do lote.
  describe 'POST leads/:id/crm_card com owner_id (envio individual)' do
    def send_one(user, lead, owner_id)
      post "#{base_url}/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id }, owner_id: owner_id },
                                              headers: auth_headers(user), as: :json
    end

    it 'função só com crm_manage_cards não troca o dono (403)' do
      agent = agent_with(%w[prospecting_manage crm_manage_cards])

      send_one(agent, create_lead(1, owner: agent), colleague.id)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_forbidden')
      expect(account.crm_cards.count).to eq(0)
    end

    it 'dono sem acesso ao funil é recusado (422)' do
      restrict_colleague_out_of_pipeline

      send_one(admin, create_lead(1), colleague.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_not_allowed')
      expect(account.crm_cards.count).to eq(0)
    end

    it 'administrador escolhe o dono, e o card fica com ele' do
      send_one(admin, create_lead(1), colleague.id)

      expect(response).to have_http_status(:created)
      expect(account.crm_cards.sole.owner_id).to eq(colleague.id)
    end
  end

  describe 'GET leads/crm_owners' do
    def owners(user, pipeline_id: pipeline.id)
      get "#{base_url}/crm_owners", params: { pipeline_id: pipeline_id }, headers: auth_headers(user), as: :json
    end

    it 'lista as pessoas da conta que enxergam o funil, sem quem não o tem' do
      outsider = create_crm_agent(account: account, name: 'Paula Ribeiro').first
      restrict_colleague_out_of_pipeline

      owners(admin)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['payload'].pluck('id')
      expect(ids).to include(admin.id, outsider.id)
      expect(ids).not_to include(colleague.id)
      expect(response.parsed_body['payload'].first.keys).to contain_exactly('id', 'name')
    end

    it 'função só com crm_manage_cards não vê a lista (403)' do
      owners(agent_with(%w[prospecting_manage crm_manage_cards]))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.owner_forbidden')
    end

    it 'não lista quem não vê os cards do CRM (função sem crm_view)' do
      sem_crm = agent_with(%w[prospecting_manage])

      owners(admin)

      expect(response.parsed_body['payload'].pluck('id')).not_to include(sem_crm.id)
    end

    it 'quem tem a chave mas não vê o funil recebe 404' do
      manager = agent_with(%w[prospecting_manage crm_manage_cards crm_manage_pipelines])
      Crm::PipelineInbox.create!(account: account, inbox: create_crm_inbox(account: account, name: 'Filial'), pipeline: pipeline)
      own_inbox = create_crm_inbox(account: account, name: 'Vendas', members: [manager])
      access = Crm::InboxAgentAccess.create!(account: account, inbox: own_inbox, user: manager, all_pipelines: false, triage: false,
                                             only_own: false)
      access.agent_pipelines.create!(account: account, pipeline: create_crm_pipeline(account: account, user: admin, name: 'Outro').first)

      owners(manager)

      expect(response).to have_http_status(:not_found)
    end

    it 'funil de outra conta é 404' do
      other = create(:account)
      foreign = create_crm_pipeline(account: other, user: create(:user, :administrator, account: other)).first

      owners(admin, pipeline_id: foreign.id)

      expect(response).to have_http_status(:not_found)
    end
  end
end
