require 'rails_helper'

# Pesquisa inteira de um lead (#679), com as classes reais das frentes A, B e C juntas e só o HTTP simulado (WebMock):
# BigDataCorp acha o CNPJ, o cadastro público (OpenCNPJ) confirma cidade e UF e traz o quadro de sócios, a regra do dono
# escolhe o decisor, o perfil da empresa é gravado, o lead é atualizado e o evento vai para a tela. A segunda pesquisa do
# mesmo lugar, em outra conta, reaproveita o perfil sem nenhuma chamada HTTP. O pedido entra pela fila (Research::Queue)
# e roda no ResearchJob real, que chama o Runner e emite o evento final.
#
# O lead chega como sai da busca: com site e sem enriched_cnpj, porque o enriquecimento roda em paralelo. A própria
# pesquisa lê o CNPJ no site (DNS dublado, página pelo WebMock), como no Orth.
RSpec.describe Autonomia::Prospecting::Research::Runner do
  include ActiveJob::TestHelper

  let(:cnpj) { '11222333000181' }
  let(:token_url) { 'https://plataforma.bigdatacorp.com.br/tokens/gerar' }
  let(:companies_url) { 'https://plataforma.bigdatacorp.com.br/empresas' }
  let(:registry_url) { "https://api.opencnpj.org/#{cnpj}" }
  let(:env) { { BIGDATACORP_USER: 'fixture-user-secret', BIGDATACORP_PASSWORD: 'fixture-password-secret' } }
  let(:account) { create(:account) }
  let(:other_cnpj) { '11444777000161' }
  let(:site_url) { 'https://www.alfa-sintetica.com.br/' }
  let(:lead) { create_lead(account, website: site_url) }

  def create_lead(owner_account, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: owner_account, provider: 'google_places', provider_place_id: 'places/alfa-sintetica', name: 'Alfa Sintetica',
      phone: '(11) 99900-0001', city: 'São Paulo', state: 'SP', **attributes
    )
  end

  def enable(target_account)
    Autonomia::Prospecting::Config.enable_for!(target_account)
    Autonomia::Prospecting::Config.enable_research_for!(target_account)
  end

  def bigdatacorp_row(tax_id, percentage)
    { 'MatchKeys' => 'name{Alf*********ca},phone{********0001}',
      'BasicData' => { 'TaxIdNumber' => tax_id, 'OfficialName' => 'Empresa Alfa Sintetica Ltda', 'TradeName' => 'Alfa Sintetica',
                       'TaxIdStatus' => 'ATIVA', 'OfficialNameInputNameMatchPercentage' => percentage,
                       'TradeNameInputNameMatchPercentage' => percentage } }
  end

  def stub_bigdatacorp(rows)
    stub_request(:post, companies_url).to_return(
      status: 200, body: { QueryId: 'query-2', Status: { basic_data: [{ Code: 0, Message: 'OK' }] }, Result: rows }.to_json
    )
  end

  # Cadastro de outra empresa do mesmo nome e da mesma cidade (um homônimo), com outro sócio.
  def stub_other_registry
    payload = JSON.parse(Rails.root.join('spec/fixtures/prospecting/registry/opencnpj-success.json').read)
    payload['cnpj'] = other_cnpj
    payload['QSA'][0]['nome_socio'] = 'OUTRA PESSOA SINTETICA'
    stub_request(:get, "https://api.opencnpj.org/#{other_cnpj}").to_return(
      status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def stub_http
    stub_request(:post, token_url).to_return(status: 200, body: { token: 'fixture-access-secret', tokenID: 'fixture-token-id-secret' }.to_json)
    stub_request(:post, companies_url).to_return(
      status: 200,
      body: {
        QueryId: 'query-1', Status: { basic_data: [{ Code: 0, Message: 'OK' }] },
        Result: [{ 'MatchKeys' => 'name{Alf*********ca},phone{********0001}',
                   'BasicData' => { 'TaxIdNumber' => cnpj, 'OfficialName' => 'Empresa Alfa Sintetica Ltda', 'TradeName' => 'Alfa Sintetica',
                                    'TaxIdStatus' => 'ATIVA', 'OfficialNameInputNameMatchPercentage' => 80,
                                    'TradeNameInputNameMatchPercentage' => 100 } }]
      }.to_json
    )
    stub_request(:get, registry_url).to_return(
      status: 200, body: Rails.root.join('spec/fixtures/prospecting/registry/opencnpj-success.json').read,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  def research(target)
    Autonomia::Prospecting::Research::Queue.enqueue(target)
    with_modified_env(**env) { Autonomia::Prospecting::Research::ResearchJob.perform_now(target.id, false) }
  end

  def broadcast_leads
    enqueued_jobs.select { |job| job['job_class'] == 'ActionCableBroadcastJob' }.filter_map do |job|
      _tokens, event, data = ActiveJob::Arguments.deserialize(job['arguments'])
      data['lead'] if event == 'prospecting.lead.updated'
    end
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34'])
    stub_request(:get, site_url).to_return(status: 200, body: '<html><body><p>Alfa Sintetica. CNPJ 11.222.333/0001-81</p></body></html>')
    # Quem pode ver a Prospecção na conta recebe o evento prospecting.lead.updated.
    create(:user, :administrator, account: account)
    enable(account)
    stub_http
  end

  it 'acha o CNPJ na BigDataCorp, lê o cadastro, escolhe o dono e grava o perfil da empresa' do
    research(lead)

    expect(a_request(:post, companies_url)).to have_been_made.once
    expect(a_request(:get, registry_url)).to have_been_made.once
    # O CNPJ do site foi lido pela própria pesquisa, sem esperar o enriquecimento.
    expect(a_request(:get, site_url)).to have_been_made.once

    profile = Autonomia::Prospecting::CompanyProfile.find_by!(cnpj: cnpj)
    expect(profile).to have_attributes(legal_name: 'EMPRESA ALFA SINTETICA LTDA', trade_name: 'ALFA SINTETICA',
                                       registration_status: 'ATIVA', registration_state: 'SP')
    expect(profile.verified_at).to be_within(5.seconds).of(Time.current)
    # Da pessoa física só nome, qualificação e entrada; a faixa etária e o representante legal não chegam ao banco, e o
    # menor (faixa de 13 a 20 anos) não entra no quadro gravado.
    expect(profile.qsa).to eq(
      [{ 'name' => 'PESSOA FISICA SINTETICA', 'qualification' => 'Sócio-Administrador', 'entered_on' => nil },
       { 'name' => 'PESSOA JURIDICA SINTETICA', 'qualification' => 'Sócio', 'entered_on' => nil, 'person_type' => 'PJ' }]
    )
    expect(profile.owners).to eq([{ 'name' => 'PESSOA FISICA SINTETICA', 'qualification' => 'Sócio-Administrador' }])
  end

  it 'atualiza o lead com a empresa e o decisor e avisa a tela pelo evento' do
    research(lead)

    profile = Autonomia::Prospecting::CompanyProfile.find_by!(cnpj: cnpj)
    lead.reload
    expect(lead).to have_attributes(
      company_research_status: 'confirmed', decision_research_status: 'confirmed', research_reused: false, research_error: nil,
      company_profile_id: profile.id, enriched_cnpj: nil, decision_name: 'PESSOA FISICA SINTETICA',
      decision_role: 'Sócio-Administrador', decision_source_url: nil, research_attempts: 1
    )
    expect(lead.decision_confidence.to_f).to be_between(0.65, 1.0)
    expect(lead.metadata.dig('research', 'discovery_evidence')).to include(
      { 'source' => 'official_site', 'signal' => 'cnpj_corroborated' }
    )

    final = broadcast_leads.last
    expect(final.dig('research', 'company_status')).to eq('confirmed')
    expect(final.dig('research', 'company', 'cnpj')).to eq(cnpj)
    expect(final.dig('research', 'decision', 'name')).to eq('PESSOA FISICA SINTETICA')
    expect(final.dig('research', 'owners')).to eq([{ 'name' => 'PESSOA FISICA SINTETICA', 'qualification' => 'Sócio-Administrador' }])
  end

  it 'a segunda pesquisa da mesma empresa, em outra conta, reaproveita sem nenhuma chamada HTTP' do
    research(lead)
    WebMock::RequestRegistry.instance.reset!
    other_account = create(:account)
    enable(other_account)
    same_place = create_lead(other_account)

    research(same_place)

    expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
    expect(same_place.reload).to have_attributes(
      research_reused: true, company_research_status: 'confirmed', decision_research_status: 'confirmed',
      decision_name: 'PESSOA FISICA SINTETICA', company_profile_id: lead.reload.company_profile_id, enriched_cnpj: nil
    )
    expect(Autonomia::Prospecting::CompanyProfile.count).to eq(1)
  end

  it 'o site com o CNPJ de um homônimo rejeita o candidato da BigDataCorp mesmo sem o enriquecimento ter rodado' do
    stub_bigdatacorp([bigdatacorp_row(other_cnpj, 100)])

    research(lead)

    expect(a_request(:get, "https://api.opencnpj.org/#{other_cnpj}")).not_to have_been_made
    expect(lead.reload).to have_attributes(company_research_status: 'no_result', company_profile_id: nil, decision_name: nil)
    expect(lead.metadata.dig('research', 'discovery_evidence')).to include({ 'source' => 'official_site', 'signal' => 'cnpj_conflict' })
  end

  it 'verificar novamente pode trocar o CNPJ: o aceito antes não se corrobora como se fosse do site' do
    no_site = create_lead(account, provider_place_id: 'places/alfa-sem-site')
    stub_other_registry
    research(no_site)
    expect(no_site.reload.company_profile.cnpj).to eq(cnpj)

    stub_bigdatacorp([bigdatacorp_row(other_cnpj, 100), bigdatacorp_row(cnpj, 85)])
    Autonomia::Prospecting::Research::Queue.enqueue(no_site, force: true)
    with_modified_env(**env) { Autonomia::Prospecting::Research::ResearchJob.perform_now(no_site.id, true) }

    no_site.reload
    expect(no_site.company_profile.cnpj).to eq(other_cnpj)
    expect(no_site).to have_attributes(company_research_status: 'confirmed', decision_name: 'OUTRA PESSOA SINTETICA', enriched_cnpj: nil)
    expect(no_site.metadata.dig('research', 'discovery_evidence')).not_to include(hash_including('source' => 'official_site'))
  end
end
