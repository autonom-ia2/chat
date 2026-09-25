require 'rails_helper'

# Job da pesquisa (#679, frente C). Duas pesquisas simultâneas da mesma empresa fazem uma chamada paga só: a segunda
# espera a trava da empresa (waiting_capacity) e, quando volta, reaproveita o que a primeira gravou.
RSpec.describe Autonomia::Prospecting::Research::ResearchJob do
  include ActiveJob::TestHelper

  let(:research) { Autonomia::Prospecting::Research }
  let(:cnpj) { '12345678000190' }
  let(:account) { create(:account) }
  let(:discovery) { instance_double(research::CnpjDiscovery) }
  let(:company) do
    partner = research::Registry::Partner.build(name: 'ANA SOUZA', qualification: 'SOCIO ADMINISTRADOR', person_type: 'PF')
    research::Registry::Company.new(
      cnpj: cnpj, legal_name: 'CLINICA SORRISO LTDA', trade_name: nil, registration_status: 'ATIVA', registration_state: 'PR',
      city: 'Curitiba', legal_nature_code: 2062, legal_nature_text: 'Sociedade Empresária Limitada', opened_on: nil, cnae: nil,
      provider: 'OpenCNPJ', sources: [{ 'provider' => 'OpenCNPJ' }], qsa: [partner]
    )
  end
  let(:owner) { { 'name' => 'ANA SOUZA', 'qualification' => 'Sócio-Administrador' } }
  let(:selection) { research::OwnerPolicy::Selection.new(owners: [owner], reason: nil, evidence: :qsa) }

  def found
    research::CnpjDiscovery::Result.new(status: :found, cnpj: cnpj, confidence: 0.9, evidence: [], candidates: [cnpj], error_code: nil)
  end

  def create_lead(owner_account, place_id)
    Autonomia::Prospecting::Lead.create!(account: owner_account, provider: 'google_places', provider_place_id: place_id, name: 'Clinica Sorriso')
  end

  def enqueue(lead)
    research::Queue.enqueue(lead)
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_research_for!(account)
    allow(research::CnpjDiscovery).to receive(:new).and_return(discovery)
    allow(discovery).to receive(:perform) { found }
    allow(research::Registry).to receive(:fetch).and_return(company)
    allow(research::OwnerPolicy).to receive(:select).and_return(selection)
    allow(Autonomia::Prospecting::LeadBroadcaster).to receive(:updated)
  end

  it 'pesquisa o lead da fila, conta a tentativa e avisa a tela ao começar e ao terminar' do
    lead = create_lead(account, 'places/a')
    enqueue(lead)

    described_class.perform_now(lead.id, false)

    expect(lead.reload).to have_attributes(company_research_status: 'confirmed', research_attempts: 1)
    expect(lead.research_started_at).to be_present
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: lead.id)).at_least(:twice)
  end

  it 'não roda lead que não está na fila' do
    lead = create_lead(account, 'places/a')

    described_class.perform_now(lead.id, false)

    expect(research::CnpjDiscovery).not_to have_received(:new)
    expect(lead.reload.company_research_status).to eq('not_researched')
  end

  describe 'duas pesquisas simultâneas da mesma empresa' do
    let(:other_account) { create(:account) }
    let(:first) { create_lead(account, 'places/mesma') }
    let(:second) { create_lead(other_account, 'places/mesma') }

    before do
      Autonomia::Prospecting::Config.enable_for!(other_account)
      Autonomia::Prospecting::Config.enable_research_for!(other_account)
    end

    # A trava é do Postgres (pg_try_advisory_lock), segurada por outra sessão, como a de outro worker do Sidekiq. Conexão
    # própria do pg: na suíte transacional as threads dividem a conexão do teste, e a trava de sessão é reentrante.
    def with_company_lock_held_elsewhere(key)
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      other = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username],
                         password: config[:password])
      params = [research::CompanyLock::NAMESPACE, "#{research::CompanyLock::PREFIX}#{key}"]
      expect(other.exec_params('SELECT pg_try_advisory_lock($1::int, hashtext($2))', params).getvalue(0, 0)).to eq('t')
      yield
    ensure
      other&.close
    end

    it 'fazem uma chamada só à descoberta: a segunda espera a vez e reaproveita' do
      enqueue(first)
      enqueue(second)
      clear_enqueued_jobs

      with_company_lock_held_elsewhere(research::CompanyLock.key_for(second)) do
        described_class.perform_now(second.id, false)
      end

      expect(research::CnpjDiscovery).not_to have_received(:new)
      expect(second.reload.company_research_status).to eq('waiting_capacity')
      expect(described_class).to have_been_enqueued.with(second.id, false)

      described_class.perform_now(first.id, false)
      described_class.perform_now(second.id, false)

      expect(research::CnpjDiscovery).to have_received(:new).once
      expect(first.reload).to have_attributes(company_research_status: 'confirmed', research_reused: false)
      expect(second.reload).to have_attributes(company_research_status: 'confirmed', research_reused: true, decision_name: 'ANA SOUZA')
    end

    it 'a chave da trava é a mesma para o mesmo lugar em contas diferentes' do
      expect(research::CompanyLock.key_for(first)).to eq(research::CompanyLock.key_for(second))
      expect(research::CompanyLock.key_for(create_lead(account, 'places/outra'))).not_to eq(research::CompanyLock.key_for(first))
    end
  end

  # Porta "continues items 8-N when item 7 needs reconciliation" (research-queue.test.ts): a quebra de um lead
  # não para os outros.
  it 'a quebra inesperada de um lead vira failed e os outros seguem' do
    leads = Array.new(10) { |index| create_lead(account, "places/#{index}") }
    leads.each { |lead| enqueue(lead) }
    broken = leads[6]
    allow(research::CnpjDiscovery).to receive(:new) do |lead:|
      raise 'quebrou no meio' if lead.id == broken.id

      discovery
    end

    leads.each { |lead| described_class.perform_now(lead.id, false) }

    expect(broken.reload).to have_attributes(company_research_status: 'failed', decision_research_status: 'failed',
                                             research_error: 'interrupted')
    expect((leads - [broken]).map { |lead| lead.reload.company_research_status }.uniq).to eq(['confirmed'])
  end

  it 'pesquisa desligada depois do pedido fica blocked, sem chamada' do
    lead = create_lead(account, 'places/a')
    enqueue(lead)
    Autonomia::Prospecting::Config.disable_research_for!(account)

    described_class.perform_now(lead.id, false)

    expect(lead.reload).to have_attributes(company_research_status: 'blocked', research_error: 'research_disabled')
    expect(research::CnpjDiscovery).not_to have_received(:new)
  end
end
