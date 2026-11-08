require 'rails_helper'

# #2697: o "Depois" da fila Para chamar mora em metadata['para_chamar']. CompanyUpserter e OwnerAdoption gravam só a
# chave deles no jsonb (Lead.write_metadata_key!); um "Depois" gravado entre a leitura do lead e a escrita deles fica.
RSpec.describe Autonomia::Prospecting::Lead, '.write_metadata_key!' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:owners) { [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO' }, { 'name' => 'BRUNO LIMA', 'qualification' => 'SOCIO' }] }
  let(:profile) do
    Autonomia::Prospecting::CompanyProfile.create!(cnpj: '11222333000181', trade_name: 'Clinica Sorriso', registration_status: 'ATIVA',
                                                   verified_at: Time.current, owners: owners)
  end
  let(:lead) do
    described_class.create!(
      account: account, provider: 'mock', provider_place_id: 'places/sorriso', name: 'Clinica Sorriso', phone: '+55 41 3333-4444',
      company_profile: profile, company_research_status: 'confirmed', decision_research_status: 'confirmed', decision_name: 'ANA SOUZA',
      metadata: { 'research' => { 'owners' => owners } }
    )
  end

  def postpone_elsewhere!
    Autonomia::Prospecting::ParaChamar.new(account: account, user: user).postpone!(described_class.find(lead.id))
  end

  it 'CompanyUpserter: o lead lido antes do "Depois" grava a empresa sem apagar o "Depois"' do
    stale = described_class.find(lead.id)
    postpone_elsewhere!

    company = Autonomia::Prospecting::CompanyUpserter.new(lead: stale).perform.company

    metadata = lead.reload.metadata
    expect(metadata['chatwoot_company_id']).to eq(company.id)
    expect(metadata.dig('para_chamar', 'depois', user.id.to_s)).to be_present
    expect(stale.metadata['chatwoot_company_id']).to eq(company.id)
    expect(stale).not_to be_changed
  end

  it 'OwnerAdoption: o "Depois" gravado depois da leitura (lock!) e antes da escrita fica' do
    allow(lead).to receive(:lock!).and_wrap_original do |original, *args|
      original.call(*args).tap { postpone_elsewhere! }
    end

    Autonomia::Prospecting::OwnerAdoption.new(lead: lead, user: user, owner_name: 'BRUNO LIMA').perform

    metadata = lead.reload.metadata
    expect(metadata['decision_adoption']).to include('name' => 'BRUNO LIMA', 'previous_name' => 'ANA SOUZA')
    expect(metadata.dig('para_chamar', 'depois', user.id.to_s)).to be_present
    expect(metadata['research']).to eq('owners' => owners)
  end
end
