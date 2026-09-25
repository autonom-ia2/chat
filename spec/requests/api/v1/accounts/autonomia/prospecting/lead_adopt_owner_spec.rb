require 'rails_helper'

# "Usar como contato" (#680, frente A): um dos sócios que a pesquisa achou vira o decisor do lead, e o contato do
# lead passa a ser essa pessoa. Só vale nome da lista da pesquisa do próprio lead, e só na conta dele.
RSpec.describe 'Autonomia prospecting lead adopt owner', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:owners) do
    [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }, { 'name' => 'BRUNO LIMA', 'qualification' => 'SOCIO' }]
  end
  let(:profile) do
    Autonomia::Prospecting::CompanyProfile.create!(
      cnpj: '11222333000181', legal_name: 'CLINICA SORRISO LTDA', trade_name: 'Clinica Sorriso', registration_status: 'ATIVA',
      verified_at: Time.zone.parse('2026-09-20 10:00'), owners: owners
    )
  end
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/sorriso', name: 'Clinica Sorriso', phone: '+55 41 3333-4444',
      company_profile: profile, company_research_status: 'possible', decision_research_status: 'possible',
      decision_name: 'ANA SOUZA', decision_role: 'SOCIO ADMINISTRADOR', decision_confidence: 0.7,
      decision_linkedin: 'https://www.linkedin.com/in/anasouza',
      metadata: { 'research' => { 'owners' => owners, 'decision_source' => 'qsa' } }
    )
  end
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/adopt_owner" }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def adopt(name, target_path = path)
    post target_path, params: { owner_name: name }, headers: auth_headers(admin), as: :json
  end

  it 'adota o sócio como decisor e devolve o lead com o contato' do
    adopt('BRUNO LIMA')

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload).to include('id' => lead.id, 'decision_name' => 'BRUNO LIMA', 'decision_role' => 'SOCIO')
    expect(payload.dig('research', 'decision')).to include('name' => 'BRUNO LIMA', 'role' => 'SOCIO')
    expect(payload['contact_id']).to eq(lead.reload.contact_id)
    expect(payload['contact_id']).to be_present
  end

  it 'mantém estado e confiança da pesquisa, solta as redes do decisor anterior, registra a troca e cria o contato da pessoa' do
    adopt('BRUNO LIMA')

    lead.reload
    expect(lead.decision_research_status).to eq('possible')
    expect(lead.decision_confidence.to_f).to eq(0.7)
    expect(lead.decision_linkedin).to be_nil
    expect(lead.metadata['decision_adoption']).to include('name' => 'BRUNO LIMA', 'previous_name' => 'ANA SOUZA', 'adopted_by_id' => admin.id)
    expect(lead.contact).to have_attributes(name: 'BRUNO LIMA')
    expect(lead.contact.additional_attributes['job_title']).to eq('SOCIO')
    expect(lead.contact.company).to have_attributes(name: 'Clinica Sorriso', account_id: account.id)
  end

  it 'troca a pessoa do contato que nós criamos, sem duplicar o contato' do
    adopt('ANA SOUZA')
    contact_id = lead.reload.contact_id

    expect { adopt('BRUNO LIMA') }.not_to change(Contact, :count)

    expect(lead.reload.contact_id).to eq(contact_id)
    expect(lead.contact.name).to eq('BRUNO LIMA')
    expect(lead.contact.additional_attributes['job_title']).to eq('SOCIO')
  end

  it 'recusa nome fora da lista da pesquisa com 422, sem mexer no lead' do
    adopt('CARLOS INVENTADO')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('prospecting.owner_not_found')
    expect(response.parsed_body['error']).to be_present
    expect(lead.reload).to have_attributes(decision_name: 'ANA SOUZA', contact_id: nil)
  end

  it 'recusa sem nome, e recusa quando a pesquisa não achou a empresa (a tela não mostra sócios)' do
    adopt('')
    expect(response).to have_http_status(:unprocessable_entity)

    lead.update!(company_research_status: 'no_result')
    adopt('BRUNO LIMA')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.decision_name).to eq('ANA SOUZA')
  end

  it 'lead de outra conta responde 404 e não mexe em nada' do
    other_account = create(:account)
    other_lead = Autonomia::Prospecting::Lead.create!(
      account: other_account, provider: 'mock', provider_place_id: 'places/outra', name: 'Outra', company_profile: profile,
      company_research_status: 'confirmed', decision_research_status: 'confirmed', metadata: { 'research' => { 'owners' => owners } }
    )

    adopt('BRUNO LIMA', "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{other_lead.id}/adopt_owner")

    expect(response).to have_http_status(:not_found)
    expect(other_lead.reload.decision_name).to be_nil
    expect(Contact.where(account: other_account).count).to eq(0)
  end
end
