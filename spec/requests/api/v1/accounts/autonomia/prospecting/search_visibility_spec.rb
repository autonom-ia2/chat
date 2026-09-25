require 'rails_helper'

# Quem vê as buscas (#732, item 6; MOTOR-37, ACAO-33, CARD-59): o agente vê, exporta e exclui só as próprias buscas, e os
# leads delas. O administrador vê todas. A chave "Ver buscas de todos" (prospecting_view_all_searches) libera a visão
# completa para quem não é administrador.
RSpec.describe 'Autonomia prospecting search visibility', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { agent_with(%w[prospecting_manage]) }
  let(:other_agent) { agent_with(%w[prospecting_manage]) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }

  let!(:own_lead) { create_lead('proprio') }
  let!(:other_lead) { create_lead('do-outro') }
  let!(:own_search) { create_search(agent, 'dentista', [own_lead]) }
  let!(:other_search) { create_search(other_agent, 'padaria', [other_lead]) }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def agent_with(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def create_lead(slug)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/#{slug}", name: "Lead #{slug}")
  end

  # O lead nasce na busca (prospect_search_id) e a busca guarda a ordem em metadata['lead_ids'], como o SearchRunner faz.
  def create_search(user, query, leads)
    search = Autonomia::Prospecting::Search.create!(
      account: account, user: user, query: query, provider: 'mock', status: 'completed',
      metadata: { 'lead_ids' => leads.map(&:id) }
    )
    leads.each { |lead| lead.update!(search: search) }
    search
  end

  def listed_search_ids(user)
    get "#{base_path}/searches", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].pluck('id')
  end

  describe 'histórico' do
    it 'o agente vê só as próprias buscas, e o total da paginação conta só as dele' do
      expect(listed_search_ids(agent)).to eq([own_search.id])
      expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    end

    it 'o administrador vê as buscas de todos' do
      expect(listed_search_ids(admin)).to contain_exactly(own_search.id, other_search.id)
    end

    it 'quem tem "Ver buscas de todos" vê as buscas de todos sem ser administrador' do
      manager = agent_with(%w[prospecting_view prospecting_view_all_searches])

      expect(listed_search_ids(manager)).to contain_exactly(own_search.id, other_search.id)
    end
  end

  describe 'busca de outro agente da mesma conta' do
    it 'não abre (404)' do
      get "#{base_path}/searches/#{other_search.id}", headers: auth_headers(agent)

      expect(response).to have_http_status(:not_found)
    end

    it 'não exporta (404), e a própria exporta' do
      get "#{base_path}/searches/#{other_search.id}/export", params: { format: 'csv' }, headers: auth_headers(agent)
      expect(response).to have_http_status(:not_found)

      get "#{base_path}/searches/#{own_search.id}/export", params: { format: 'csv' }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Lead proprio')
    end

    it 'não exclui (404) e continua gravada' do
      delete "#{base_path}/searches/#{other_search.id}", headers: auth_headers(agent)

      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Prospecting::Search.exists?(other_search.id)).to be(true)
    end

    it 'não muda o funil padrão dela (404)' do
      patch "#{base_path}/searches/#{other_search.id}", params: { search: { crm_pipeline_id: '', crm_stage_id: '' } },
                                                        headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'o agente exclui a própria busca' do
      delete "#{base_path}/searches/#{own_search.id}", headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
      expect(Autonomia::Prospecting::Search.exists?(own_search.id)).to be(false)
    end

    it 'o administrador abre e exporta a busca de qualquer agente' do
      get "#{base_path}/searches/#{other_search.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'leads').pluck('id')).to eq([other_lead.id])

      get "#{base_path}/searches/#{other_search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'leads da busca de outro agente' do
    it 'o agente não abre o lead (404) nem o vê na lista de leads' do
      get "#{base_path}/leads/#{other_lead.id}", headers: auth_headers(agent)
      expect(response).to have_http_status(:not_found)

      get "#{base_path}/leads", headers: auth_headers(agent)
      expect(response.parsed_body['payload'].pluck('id')).to eq([own_lead.id])
    end

    it 'o agente não age sobre o lead de outro (404)' do
      patch "#{base_path}/leads/#{other_lead.id}", params: { lead: { status: 'qualified' } }, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_lead.reload.status).not_to eq('qualified')
    end

    it 'o lead que também voltou numa busca do agente fica visível para ele' do
      own_search.update!(metadata: { 'lead_ids' => [own_lead.id, other_lead.id] })

      get "#{base_path}/leads/#{other_lead.id}", headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
    end

    it 'o lead que está numa lista da conta fica visível, porque as listas são da conta' do
      list = Autonomia::Prospecting::List.create!(account: account, user: other_agent, name: 'Lista da equipe')
      list.list_leads.create!(account: account, lead: other_lead)

      get "#{base_path}/leads/#{other_lead.id}", headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
    end

    it 'o administrador vê os leads de todas as buscas' do
      get "#{base_path}/leads", headers: auth_headers(admin)

      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(own_lead.id, other_lead.id)
    end
  end

  it 'a busca nova fica com quem a fez' do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
    allow(Autonomia::Prospecting::LeadWorkQueue).to receive(:after_search)

    post "#{base_path}/searches",
         params: { search: { query: 'clinica', location: 'Curitiba, PR', requested_limit: 2,
                             metadata: { location_place_id: 'places/curitiba', location_latitude: -25.4, location_longitude: -49.2 } } },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:created)
    new_id = response.parsed_body.dig('payload', 'search', 'id')
    expect(listed_search_ids(agent)).to include(new_id)
    expect(listed_search_ids(other_agent)).not_to include(new_id)
  end
end
