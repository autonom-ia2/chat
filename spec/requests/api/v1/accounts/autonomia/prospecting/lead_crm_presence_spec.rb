require 'rails_helper'

# Lead já no CRM (#732, item 1): o lead continua por conta, e onde ele aparece (lista de leads, busca aberta, lista,
# lead avulso) vem junto "funil, estágio, responsável" do card que ele já tem. Sem card, crm_presence é nulo.
RSpec.describe 'Autonomia prospecting lead crm presence', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account, name: 'Admin Dono') }
  let(:owner) { create(:user, account: account, role: :agent, name: 'Vendedora Ana') }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Funil Vendas') }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:crm_tables) { %w[crm_cards crm_pipelines crm_pipeline_stages users] }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "presence-#{index}", name: "Empresa #{index}")
  end

  def create_lead_in_crm(index, card_owner: owner)
    create_lead(index).tap do |lead|
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: card_owner, title: "Card #{index}")
      lead.update!(crm_card: card)
    end
  end

  def presence_of(leads, lead)
    leads.find { |item| item['id'] == lead.id }['crm_presence']
  end

  def expected_presence(lead)
    card = lead.reload.crm_card
    {
      'card_id' => card.id, 'pipeline_id' => pipeline.id, 'pipeline_name' => 'Funil Vendas', 'stage_id' => stage.id,
      'stage_name' => 'Novo Lead', 'owner_id' => card.owner_id, 'owner_name' => card.owner&.name, 'status' => 'open'
    }
  end

  # Consultas às tabelas do card, fora a do usuário logado: não podem crescer com o número de leads.
  def crm_query_count(&)
    count = 0
    counter = lambda do |*, payload|
      sql = payload[:sql].to_s
      count += 1 if sql.start_with?('SELECT') && crm_tables.any? { |table| sql.include?("FROM \"#{table}\"") }
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  it 'a lista de leads diz funil, estágio e responsável do card, e nulo para lead fora do CRM' do
    in_crm = create_lead_in_crm(1)
    outside = create_lead(2)

    get "#{base_path}/leads", headers: auth_headers(admin)

    leads = response.parsed_body['payload']
    expect(presence_of(leads, in_crm)).to eq(expected_presence(in_crm))
    expect(presence_of(leads, outside)).to be_nil
  end

  it 'card sem responsável vem com responsável nulo' do
    lead = create_lead_in_crm(1, card_owner: nil)

    get "#{base_path}/leads/#{lead.id}", headers: auth_headers(admin)

    expect(response.parsed_body.dig('payload', 'crm_presence')).to include('owner_id' => nil, 'owner_name' => nil)
  end

  it 'a busca aberta e a lista trazem o mesmo estado' do
    lead = create_lead_in_crm(1)
    search = Autonomia::Prospecting::Search.create!(account: account, query: 'padaria', metadata: { 'lead_ids' => [lead.id] })
    list = Autonomia::Prospecting::List.create!(account: account, name: 'Lista')
    list.list_leads.create!(lead: lead, account: account)

    get "#{base_path}/searches/#{search.id}", headers: auth_headers(admin)
    expect(presence_of(response.parsed_body.dig('payload', 'leads'), lead)).to eq(expected_presence(lead))

    get "#{base_path}/lists/#{list.id}", headers: auth_headers(admin)
    expect(presence_of(response.parsed_body.dig('payload', 'leads'), lead)).to eq(expected_presence(lead))
  end

  it 'o número de consultas ao CRM não cresce com o número de leads no CRM (sem N+1)' do
    admin
    2.times { |index| create_lead_in_crm(index) }
    few = crm_query_count { get "#{base_path}/leads", headers: auth_headers(admin) }

    (2..7).each { |index| create_lead_in_crm(index, card_owner: create(:user, account: account, role: :agent)) }
    many = crm_query_count { get "#{base_path}/leads", headers: auth_headers(admin) }

    expect(response.parsed_body['payload'].size).to eq(8)
    expect(many).to eq(few)
  end

  it 'a busca aberta também não faz uma consulta por lead' do
    admin
    leads = Array.new(2) { |index| create_lead_in_crm(index) }
    search = Autonomia::Prospecting::Search.create!(account: account, query: 'padaria', metadata: { 'lead_ids' => leads.map(&:id) })
    few = crm_query_count { get "#{base_path}/searches/#{search.id}", headers: auth_headers(admin) }

    more = leads + (2..7).map { |index| create_lead_in_crm(index, card_owner: create(:user, account: account, role: :agent)) }
    search.update!(metadata: { 'lead_ids' => more.map(&:id) })
    many = crm_query_count { get "#{base_path}/searches/#{search.id}", headers: auth_headers(admin) }

    expect(many).to eq(few)
  end
end
