require 'rails_helper'

# Permissões do envio ao CRM pela prospecção (#680): quem só tem a prospecção não cria card. O envio passa pela
# permissão do módulo que ele altera, como no próprio CRM. O Público de Campanhas tem a dele (lead_audience_spec.rb).
RSpec.describe 'Autonomia prospecting send permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }

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

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "place-perm-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-000#{index}", country: 'BR',
      metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => "+55 31 99999-000#{index}" } }
    )
  end

  # O agente só age sobre os leads das próprias buscas (#732, item 6): o lead nasce numa busca dele.
  def own_lead(agent, index)
    create_lead(index).tap do |lead|
      search = Autonomia::Prospecting::Search.create!(account: account, user: agent, query: "busca #{index}", provider: 'mock',
                                                      status: 'completed', metadata: { 'lead_ids' => [lead.id] })
      lead.update!(search: search)
    end
  end

  describe 'envio ao CRM' do
    it 'papel só com a prospecção não cria card em lote (403) e nada é gravado' do
      post "#{base_url}/leads/crm_cards", params: { lead_ids: [create_lead(1).id], pipeline_id: pipeline.id, stage_id: stage.id },
                                          headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.forbidden')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.crm_send.errors.forbidden'))
      expect(account.crm_cards.count).to eq(0)
    end

    it 'papel só com a prospecção não cria card individual (403)' do
      lead = create_lead(1)

      post "#{base_url}/leads/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
                                                    headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(account.crm_cards.count).to eq(0)
      expect(lead.reload.contact_id).to be_nil
    end

    it 'papel com a prospecção e com crm_manage_cards envia' do
      agent = agent_with(%w[prospecting_manage crm_manage_cards])
      post "#{base_url}/leads/crm_cards", params: { lead_ids: [own_lead(agent, 1).id], pipeline_id: pipeline.id, stage_id: stage.id },
                                          headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'created').size).to eq(1)
    end
  end
end
