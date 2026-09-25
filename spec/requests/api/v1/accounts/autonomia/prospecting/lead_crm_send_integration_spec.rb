require 'rails_helper'

# Integração das três frentes do #680, sem dublês: o endpoint de lote leva três leads ao estágio com automação de
# entrada, e cada peça real age (empresa, contato, card, automação). O CRM é ligado pela variável de ambiente, como em
# produção. A automação de teste só cria uma tarefa de lembrete: o CRM não tem passo de etiqueta, e nenhum passo pode
# mandar mensagem a cliente.
RSpec.describe 'Autonomia prospecting send to CRM, integration of #680', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:cnpj) { '11222333000181' }
  let(:profile) do
    Autonomia::Prospecting::CompanyProfile.create!(
      cnpj: cnpj, legal_name: 'ALPHA RESTAURANTE LTDA', trade_name: 'Alpha Gastronomia', registration_status: 'ATIVA',
      registration_state: 'SP', verified_at: Time.zone.parse('2026-09-20 10:00')
    )
  end
  let(:owner_lead) do
    create_lead('alpha-centro', name: 'Alpha Centro', phone: '+55 11 3333-1111',
                                company_profile: profile, company_research_status: 'confirmed', decision_research_status: 'confirmed',
                                decision_name: 'ANA SOUZA', decision_role: 'SOCIO ADMINISTRADOR', decision_confidence: 0.9,
                                enriched_email: 'ana@alpha.example.com',
                                metadata: { 'research' => { 'owners' => [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }] } })
  end
  let(:domain_lead) do
    create_lead('beta', name: 'Beta Café', phone: '+55 11 3333-2222', website: 'https://www.betacafe.com.br/?utm_source=gmb',
                        company_research_status: 'no_result', decision_research_status: 'no_result')
  end
  let(:branch_lead) do
    create_lead('alpha-sul', name: 'Alpha Zona Sul', phone: '+55 11 3333-3333',
                             company_profile: profile, company_research_status: 'confirmed', decision_research_status: 'no_result')
  end
  let(:leads) { [owner_lead, domain_lead, branch_lead] }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    automation = account.crm_stage_automations.create!(
      pipeline: pipeline, stage: stage, name: 'Entrada da prospecção', trigger_event: :on_enter, created_by: admin
    )
    automation.steps.create!(
      account: account, position: 0, delay_seconds: 0, action_type: :create_follow_up,
      action_config: { title: 'Ligar para o decisor', automation_mode: 'reminder_only' }
    )
  end

  def create_lead(place, **attributes)
    Autonomia::Prospecting::Lead.create!({ account: account, provider: 'mock', provider_place_id: "places/#{place}", country: 'BR' }
                                           .merge(attributes))
  end

  def send_to_crm
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/crm_cards",
           params: { lead_ids: leads.map(&:id), pipeline_id: pipeline.id, stage_id: stage.id },
           headers: auth_headers(admin), as: :json
    end
    response.parsed_body['payload']
  end

  def row_for(rows, lead)
    rows.find { |row| row['lead_id'] == lead.id }
  end

  describe 'primeiro envio' do
    let!(:payload) { send_to_crm }
    let(:alpha) { account.companies.find(row_for(payload['created'], owner_lead)['company_id']) }
    let(:beta) { account.companies.find(row_for(payload['created'], domain_lead)['company_id']) }

    it 'cria os 3 cards no estágio, sem falha nem existente' do
      expect(response).to have_http_status(:ok)
      expect(payload.values_at('existing', 'failed')).to eq([[], []])
      expect(payload['created'].map { |row| row['lead_id'] }).to match_array(leads.map(&:id))
      expect(leads.map { |lead| lead.reload.crm_card.stage_id }).to eq([stage.id] * 3)
    end

    it 'reaproveita a empresa pelo CNPJ para a filial e cria a do domínio do site' do
      expect(account.companies.count).to eq(2)
      expect(row_for(payload['created'], branch_lead)['company_id']).to eq(alpha.id)
      expect(alpha).to have_attributes(name: 'Alpha Gastronomia', domain: nil)
      expect(alpha.additional_attributes).to include('cnpj' => cnpj, 'legal_name' => 'ALPHA RESTAURANTE LTDA')
      expect(beta).to have_attributes(name: 'Beta Café', domain: 'betacafe.com.br')
    end

    it 'o contato é o decisor quando há um e a empresa quando não há, cada um ligado à sua empresa' do
      person = owner_lead.reload.contact
      expect(person).to have_attributes(name: 'ANA SOUZA', email: 'ana@alpha.example.com', phone_number: '+551133331111', company: alpha)
      expect(person.additional_attributes).to include('job_title' => 'SOCIO ADMINISTRADOR', 'company_name' => 'Alpha Gastronomia')
      expect(domain_lead.reload.contact).to have_attributes(name: 'Beta Café', phone_number: '+551133332222', company: beta)
      expect(branch_lead.reload.contact).to have_attributes(name: 'Alpha Gastronomia', phone_number: '+551133333333', company: alpha)
      expect(account.contacts.count).to eq(3)
    end

    it 'cada card leva o contato, a empresa e o decisor' do
      cards = leads.map { |lead| lead.reload.crm_card }
      expect(cards.map(&:contact_id)).to eq(leads.map(&:contact_id))
      expect(cards.map { |card| card.metadata.dig('autonomia_prospecting', 'company', 'id') }).to eq(leads.map { |lead| lead.contact.company_id })
      expect(cards.first.metadata.dig('autonomia_prospecting', 'decision'))
        .to eq('name' => 'ANA SOUZA', 'role' => 'SOCIO ADMINISTRADOR', 'confidence' => 0.9)
    end

    it 'roda a automação de entrada uma vez por card' do
      executions = account.crm_stage_automation_executions
      expect(executions.group(:card_id).count.values).to eq([1, 1, 1])
      expect(executions.pluck(:card_id)).to match_array(account.crm_cards.pluck(:id))
      expect(executions.pluck(:status).uniq).to eq(['completed'])
      expect(account.crm_follow_ups.where(title: 'Ligar para o decisor').group(:card_id).count.values).to eq([1, 1, 1])
    end
  end

  it 'reenviar devolve os 3 como já existentes e não cria card, empresa, contato nem automação' do
    first = send_to_crm
    scopes = [account.crm_cards, account.companies, account.contacts, account.crm_stage_automation_executions, account.crm_follow_ups]
    before_resend = scopes.map(&:count)

    second = send_to_crm

    expect(response).to have_http_status(:ok)
    expect(second.values_at('created', 'failed')).to eq([[], []])
    expect(second['existing']).to match_array(first['created'].map { |row| row.slice('lead_id', 'card_id') })
    expect(scopes.map(&:count)).to eq(before_resend)
  end
end
