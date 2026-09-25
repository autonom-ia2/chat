require 'rails_helper'

# Detalhe técnico da nota (#732, item 9; MODO-51, PLAT-05): componentes, pesos, motor e fatores negativos só vão para o
# administrador da conta. O agente recebe a faixa (nota e prioridade) e a frase (human_insight), em todo lugar que
# devolve o lead: a busca, o lead, a lista e o evento ao vivo.
RSpec.describe 'Autonomia prospecting score details visibility', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { agent_with(%w[prospecting_manage prospecting_view_all_searches]) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:breakdown) do
    { 'rating' => { 'signal' => 90, 'weight' => 0.4, 'weighted_score' => 36 }, '_engine' => 'orth', '_mode' => 'gbp',
      '_effective_weights' => { 'rating' => 0.4 } }
  end
  let!(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/nota', name: 'Clinica Nota', score: 71.5,
      priority_score: 80, priority_position: 1, human_insight: 'Sem site e com boa reputação: ligar primeiro.',
      score_breakdown: breakdown, negative_factors: ['inactive_gbp']
    )
  end
  let!(:search) do
    Autonomia::Prospecting::Search.create!(
      account: account, user: admin, query: 'dentista', provider: 'mock', status: 'completed',
      metadata: { 'lead_ids' => [lead.id],
                  'lead_scoring' => { lead.id.to_s => { 'score' => 70, 'priority_score' => 81, 'priority_position' => 1,
                                                        'score_breakdown' => breakdown } } }
    ).tap { |created| lead.update!(search: created) }
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def agent_with(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def lead_from(user, path)
    get path, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    yield response.parsed_body
  end

  it 'o lead: o administrador recebe o bloco técnico, o agente só a faixa e a frase' do
    lead_from(admin, "#{base_path}/leads/#{lead.id}") do |body|
      expect(body['payload']).to include('score_breakdown' => breakdown, 'negative_factors' => ['inactive_gbp'])
    end

    lead_from(agent, "#{base_path}/leads/#{lead.id}") do |body|
      expect(body['payload']).not_to include('score_breakdown', 'negative_factors')
      expect(body['payload']).to include('score' => '71.5', 'priority_score' => '80.0', 'human_insight' => lead.human_insight)
    end
  end

  it 'a busca aberta: a nota da busca vai para o agente sem os componentes' do
    lead_from(admin, "#{base_path}/searches/#{search.id}") do |body|
      expect(body.dig('payload', 'leads', 0, 'score_breakdown')).to eq(breakdown)
    end

    lead_from(agent, "#{base_path}/searches/#{search.id}") do |body|
      api_lead = body.dig('payload', 'leads', 0)
      expect(api_lead).not_to include('score_breakdown', 'negative_factors')
      expect(api_lead['priority_score']).to eq('81.0')
    end
  end

  it 'a lista de leads e a lista salva também saem sem o bloco para o agente' do
    list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista')
    list.list_leads.create!(account: account, lead: lead)

    lead_from(agent, "#{base_path}/leads") do |body|
      expect(body['payload'].first).not_to include('score_breakdown', 'negative_factors')
    end
    lead_from(agent, "#{base_path}/lists/#{list.id}") do |body|
      expect(body.dig('payload', 'leads', 0)).not_to include('score_breakdown', 'negative_factors')
    end
    lead_from(admin, "#{base_path}/lists/#{list.id}") do |body|
      expect(body.dig('payload', 'leads', 0, 'score_breakdown')).to eq(breakdown)
    end
  end

  it 'as configurações dizem à tela quem vê o detalhe da nota' do
    lead_from(admin, "#{base_path}/settings") { |body| expect(body.dig('payload', 'can_view_score_details')).to be(true) }
    lead_from(agent, "#{base_path}/settings") { |body| expect(body.dig('payload', 'can_view_score_details')).to be(false) }
  end

  describe 'evento ao vivo' do
    def broadcasts
      enqueued_jobs.select { |job| job['job_class'] == 'ActionCableBroadcastJob' }
                   .map { |job| ActiveJob::Arguments.deserialize(job['arguments']) }
    end

    it 'o administrador recebe o lead com o bloco técnico e o agente sem ele' do
      admin_token = admin.pubsub_token
      agent_token = agent.pubsub_token

      Autonomia::Prospecting::LeadBroadcaster.updated(lead)

      full = broadcasts.find { |tokens, _event, _data| tokens.include?(admin_token) }
      restricted = broadcasts.find { |tokens, _event, _data| tokens.include?(agent_token) }
      expect(full[0]).not_to include(agent_token)
      expect(full[2]['lead']).to include('score_breakdown' => breakdown)
      expect(restricted[0]).not_to include(admin_token)
      expect(restricted[2]['lead']).not_to include('score_breakdown', 'negative_factors')
      expect(restricted[2]['lead']['human_insight']).to eq(lead.human_insight)
    end

    it 'o agente sem "Ver buscas de todos" não recebe o lead da busca de outra pessoa' do
      own_only = agent_with(%w[prospecting_manage])
      own_only_token = own_only.pubsub_token

      Autonomia::Prospecting::LeadBroadcaster.updated(lead)

      expect(broadcasts.flat_map(&:first)).not_to include(own_only_token)
    end
  end
end
