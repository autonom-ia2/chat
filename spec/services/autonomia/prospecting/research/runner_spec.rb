require 'rails_helper'

# Pesquisa de empresa e decisor de um lead (#679, frente C). A descoberta do CNPJ (frente A), o cadastro e a regra do
# dono (frente B) são as classes reais, com o resultado escolhido por teste: aqui se prova o que a frente C decide e grava.
# A pesquisa inteira, com HTTP simulado e sem dublê, está em runner_integration_spec.rb.
RSpec.describe Autonomia::Prospecting::Research::Runner do
  let(:research) { Autonomia::Prospecting::Research }
  let(:cnpj) { '12345678000190' }
  let(:account) { create(:account) }
  let(:lead) { create_lead(account, 'places/sorriso') }
  let(:discovery_result) { discovery(:found) }
  let(:company) { registry_company }
  let(:selection) do
    owner_selection(owners: [{ name: 'ANA SOUZA', qualification: 'SOCIO ADMINISTRADOR' }, { name: 'BRUNO LIMA', qualification: 'SOCIO' }])
  end

  def create_lead(owner_account, place_id, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: owner_account, provider: 'google_places', provider_place_id: place_id, name: 'Clinica Sorriso',
      phone: '+5541999990000', city: 'Curitiba', state: 'PR', **attributes
    )
  end

  def discovery(status, confidence: 0.92, error_code: nil, company: nil)
    research::CnpjDiscovery::Result.new(
      status: status, cnpj: status == :found ? cnpj : nil, confidence: confidence, error_code: error_code, candidates: [cnpj],
      evidence: [{ source: 'bigdatacorp', signal: 'phone_match' }, { source: 'site', signal: 'cnpj_on_site' }], company: company
    )
  end

  def partner(name, qualification, person_type: 'PF', is_minor: false)
    research::Registry::Partner.build(name: name, qualification: qualification, person_type: person_type, is_minor: is_minor,
                                      entered_on: Date.new(2015, 3, 2))
  end

  def registry_company(qsa: nil)
    research::Registry::Company.new(
      cnpj: cnpj, legal_name: 'CLINICA SORRISO LTDA', trade_name: 'Clinica Sorriso', registration_status: 'ATIVA',
      registration_state: 'PR', city: 'Curitiba', legal_nature_code: 2062, legal_nature_text: 'Sociedade Empresária Limitada',
      opened_on: Date.new(2015, 3, 2), cnae: '8630504', provider: 'OpenCNPJ',
      sources: [{ 'provider' => 'OpenCNPJ', 'url' => "https://api.opencnpj.org/#{cnpj}" }],
      qsa: qsa || [partner('ANA SOUZA', 'SOCIO ADMINISTRADOR'), partner('BRUNO LIMA', 'SOCIO'),
                   partner('SORRISO HOLDING LTDA', 'SOCIO', person_type: 'PJ')]
    )
  end

  def owner_selection(owners:, reason: nil, evidence: :qsa)
    research::OwnerPolicy::Selection.new(owners: owners, reason: reason, evidence: evidence)
  end

  def run(target = lead, force: false)
    described_class.new(lead: target, force: force).perform
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_research_for!(account)
    allow(research::CnpjDiscovery).to receive(:new) { instance_double(research::CnpjDiscovery, perform: discovery_result) }
    allow(research::Registry).to receive(:fetch).and_return(company)
    allow(research::OwnerPolicy).to receive(:select).and_return(selection)
    allow(Autonomia::Prospecting::LeadBroadcaster).to receive(:updated)
  end

  describe 'empresa achada e dono escolhido' do
    it 'grava empresa e decisor confirmados, o perfil da empresa e a confiança com o nome' do
      expect(run).to eq(:done)

      lead.reload
      expect(lead).to have_attributes(
        company_research_status: 'confirmed', decision_research_status: 'confirmed', research_reused: false,
        research_error: nil, enriched_cnpj: cnpj, decision_name: 'ANA SOUZA', decision_role: 'SOCIO ADMINISTRADOR',
        decision_source_url: nil
      )
      expect(lead.decision_confidence.to_f).to eq(0.92)
      expect(lead.research_completed_at).to be_within(5.seconds).of(Time.current)
      expect(lead.company_profile).to have_attributes(cnpj: cnpj, legal_name: 'CLINICA SORRISO LTDA', registration_status: 'ATIVA')
      expect(lead.company_profile.verified_at).to be_within(5.seconds).of(Time.current)
    end

    it 'guarda os donos na ordem da regra do dono, com a fonte, e pede o dono para o tipo de decisor da busca' do
      run

      expect(lead.reload.metadata['research']).to include(
        'owners' => [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' },
                     { 'name' => 'BRUNO LIMA', 'qualification' => 'SOCIO' }],
        'decision_source' => 'qsa', 'no_decision_reason' => nil
      )
      expect(research::OwnerPolicy).to have_received(:select).with(company: company, requested_role: 'owner')
    end

    it 'guarda no quadro de sócios só nome, qualificação e entrada da pessoa física, e a PJ marcada como PJ' do
      run

      expect(lead.reload.company_profile.qsa).to eq(
        [{ 'name' => 'ANA SOUZA', 'qualification' => 'Sócio-Administrador', 'entered_on' => '2015-03-02' },
         { 'name' => 'BRUNO LIMA', 'qualification' => 'Sócio', 'entered_on' => '2015-03-02' },
         { 'name' => 'SORRISO HOLDING LTDA', 'qualification' => 'Sócio', 'entered_on' => '2015-03-02', 'person_type' => 'PJ' }]
      )
      expect(lead.company_profile.data).to include('city' => 'Curitiba', 'provider' => 'OpenCNPJ', 'requested_role' => 'owner')
    end

    it 'usa o cadastro que a descoberta já leu, sem consultar de novo' do
      allow(research::CnpjDiscovery).to receive(:new) do
        instance_double(research::CnpjDiscovery, perform: discovery(:found, company: registry_company))
      end

      run

      expect(research::Registry).not_to have_received(:fetch)
      expect(lead.reload.company_profile).to have_attributes(cnpj: cnpj, legal_name: 'CLINICA SORRISO LTDA')
    end

    it 'nunca grava menor de idade no quadro de sócios, mesmo que a fonte o traga' do
      allow(research::Registry).to receive(:fetch).and_return(
        registry_company(qsa: [partner('ANA SOUZA', 'SOCIO ADMINISTRADOR'), partner('JOAO MENOR', 'SOCIO', is_minor: true)])
      )

      run

      expect(lead.reload.company_profile.qsa.pluck('name')).to eq(['ANA SOUZA'])
    end

    it 'não troca o CNPJ que o site já trouxe: o cadastro aparece pelo perfil da empresa' do
      lead.update!(enriched_cnpj: '12.345.678/0001-90')

      run

      expect(lead.reload.enriched_cnpj).to eq('12.345.678/0001-90')
      expect(lead.company_profile.cnpj).to eq(cnpj)
    end

    it 'decisor novo limpa as redes do decisor anterior e nunca recebe a rede da empresa' do
      lead.update!(decision_name: 'Pessoa da IA', decision_linkedin: 'https://linkedin.com/company/clinicasorriso',
                   decision_instagram: 'https://instagram.com/clinicasorriso',
                   enriched_linkedin: 'https://linkedin.com/company/clinicasorriso',
                   enriched_instagram: 'https://instagram.com/clinicasorriso')

      run

      expect(lead.reload).to have_attributes(decision_name: 'ANA SOUZA', decision_linkedin: nil, decision_instagram: nil,
                                             enriched_linkedin: 'https://linkedin.com/company/clinicasorriso')
    end

    it 'mesmo decisor mantém as redes que já eram dele' do
      lead.update!(decision_name: 'ANA SOUZA', decision_linkedin: 'https://linkedin.com/in/anasouza')

      run

      expect(lead.reload.decision_linkedin).to eq('https://linkedin.com/in/anasouza')
    end
  end

  describe 'sem decisor' do
    it 'grava o motivo da regra do dono e nunca a confiança sem nome' do
      allow(research::OwnerPolicy).to receive(:select).and_return(owner_selection(owners: [], reason: 'only_companies', evidence: nil))

      run

      lead.reload
      expect(lead).to have_attributes(company_research_status: 'confirmed', decision_research_status: 'no_result',
                                      decision_name: nil, decision_confidence: nil)
      expect(lead.metadata.dig('research', 'no_decision_reason')).to eq('only_companies')
    end

    it 'dono sem nome não é decisor: não grava confiança' do
      allow(research::OwnerPolicy).to receive(:select).and_return(owner_selection(owners: [{ name: ' ', qualification: 'SOCIO' }]))

      run

      expect(lead.reload).to have_attributes(decision_research_status: 'no_result', decision_name: nil, decision_confidence: nil)
    end

    it 'não apaga o decisor que o lead já tinha' do
      lead.update!(decision_name: 'Pessoa da IA', decision_role: 'Diretor')
      allow(research::OwnerPolicy).to receive(:select).and_return(owner_selection(owners: [], reason: 'no_qsa', evidence: nil))

      run

      expect(lead.reload).to have_attributes(decision_name: 'Pessoa da IA', decision_role: 'Diretor', decision_research_status: 'no_result')
    end
  end

  describe 'descoberta do CNPJ sem empresa' do
    {
      not_found: ['no_result', 'no_result', nil, 'company_not_found'],
      ambiguous: ['ambiguous', 'ambiguous', nil, 'company_ambiguous'],
      not_configured: ['blocked', 'blocked', 'not_configured', nil],
      failed: ['failed', 'failed', 'bigdatacorp_timeout', nil]
    }.each do |status, (company_status, decision_status, error, reason)|
      it "#{status}: empresa #{company_status}, decisor #{decision_status}, sem cadastro e sem perfil" do
        allow(research::CnpjDiscovery).to receive(:new) do
          instance_double(research::CnpjDiscovery, perform: discovery(status, error_code: status == :failed ? 'bigdatacorp_timeout' : nil))
        end

        run

        lead.reload
        expect(lead).to have_attributes(company_research_status: company_status, decision_research_status: decision_status,
                                        research_error: error, company_profile_id: nil, decision_confidence: nil)
        expect(lead.metadata.dig('research', 'no_decision_reason')).to eq(reason)
        expect(research::Registry).not_to have_received(:fetch)
        expect(Autonomia::Prospecting::CompanyProfile.count).to eq(0)
      end
    end
  end

  describe 'falha tipada' do
    it 'cadastro fora do ar vira failed com o código, sem perfil' do
      allow(research::Registry).to receive(:fetch).and_return(
        research::Registry::Failure.new(cnpj: cnpj, reason: :providers_exhausted, attempts: [])
      )

      run

      expect(lead.reload).to have_attributes(company_research_status: 'failed', research_error: 'REGISTRY_PROVIDERS_EXHAUSTED',
                                             company_profile_id: nil)
      expect(Autonomia::Prospecting::CompanyProfile.count).to eq(0)
    end

    it 'Violation de campo de pessoa vinda das fontes vira failed e nada é gravado' do
      allow(research::Registry).to receive(:fetch).and_raise(research::PersonFields::Violation, 'cpf')

      run

      expect(lead.reload).to have_attributes(company_research_status: 'failed', decision_research_status: 'failed',
                                             research_error: 'person_fields_violation', decision_name: nil, enriched_cnpj: nil)
      expect(Autonomia::Prospecting::CompanyProfile.count).to eq(0)
    end

    it 'sócio pessoa física com campo fora da lista fechada levanta Violation na montagem e nada é gravado' do
      leaky = instance_double(research::Registry::Partner, is_minor: false, company?: false,
                                                           storable: { 'name' => 'ANA SOUZA', 'cpf' => '***.123.456-**' })
      allow(research::Registry).to receive(:fetch).and_return(registry_company(qsa: [leaky]))

      run

      expect(lead.reload).to have_attributes(company_research_status: 'failed', research_error: 'person_fields_violation',
                                             decision_name: nil, decision_confidence: nil, enriched_cnpj: nil)
      expect(Autonomia::Prospecting::CompanyProfile.count).to eq(0)
    end

    it 'dono com campo de pessoa fora da lista também é recusado' do
      allow(research::OwnerPolicy).to receive(:select).and_return(
        owner_selection(owners: [{ name: 'ANA SOUZA', qualification: 'SOCIO ADMINISTRADOR', birth_date: '1980-01-01' }])
      )

      run

      expect(lead.reload).to have_attributes(company_research_status: 'failed', research_error: 'person_fields_violation', decision_name: nil)
      expect(Autonomia::Prospecting::CompanyProfile.count).to eq(0)
    end
  end

  describe 'reaproveitamento por 90 dias' do
    # A primeira pesquisa faz a chamada paga; as contas abaixo somam as duas rodadas.
    def research_once(target)
      run(target)
    end

    it 'o mesmo lugar pesquisado há menos de 90 dias reaproveita sem chamada paga e marca research_reused' do
      research_once(lead)
      travel 30.days
      other_account = create(:account)
      Autonomia::Prospecting::Config.enable_for!(other_account)
      Autonomia::Prospecting::Config.enable_research_for!(other_account)
      same_place = create_lead(other_account, 'places/sorriso')

      run(same_place)

      expect(research::CnpjDiscovery).to have_received(:new).once
      expect(research::Registry).to have_received(:fetch).once
      expect(same_place.reload).to have_attributes(
        research_reused: true, company_research_status: 'confirmed', decision_research_status: 'confirmed',
        decision_name: 'ANA SOUZA', company_profile_id: lead.reload.company_profile_id
      )
      expect(same_place.decision_confidence.to_f).to eq(0.92)
    end

    it 'o próprio lead pesquisado de novo reaproveita' do
      research_once(lead)

      run

      expect(research::CnpjDiscovery).to have_received(:new).once
      expect(lead.reload.research_reused).to be(true)
    end

    it 'perfil com mais de 90 dias pesquisa de novo e renova a verificação' do
      research_once(lead)
      travel 91.days

      run

      expect(research::CnpjDiscovery).to have_received(:new).twice
      expect(lead.reload.research_reused).to be(false)
      expect(lead.company_profile.verified_at).to be_within(5.seconds).of(Time.current)
    end

    it 'force ignora o reaproveitamento e faz a chamada' do
      research_once(lead)

      run(force: true)

      expect(research::CnpjDiscovery).to have_received(:new).twice
      expect(lead.reload.research_reused).to be(false)
    end

    it 'CNPJ já cadastrado há menos de 90 dias não consulta o cadastro de novo' do
      research_once(lead)
      other_place = create_lead(account, 'places/outra-unidade')

      run(other_place)

      expect(research::CnpjDiscovery).to have_received(:new).twice
      expect(research::Registry).to have_received(:fetch).once
      expect(other_place.reload).to have_attributes(research_reused: false, company_profile_id: lead.reload.company_profile_id,
                                                    decision_name: 'ANA SOUZA')
    end
  end

  it 'com a pesquisa desligada fica blocked sem chamar nada' do
    Autonomia::Prospecting::Config.disable_research_for!(account)

    run

    expect(lead.reload).to have_attributes(company_research_status: 'blocked', research_error: 'research_disabled')
    expect(research::CnpjDiscovery).not_to have_received(:new)
  end
end
