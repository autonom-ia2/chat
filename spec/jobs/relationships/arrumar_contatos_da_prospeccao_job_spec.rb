require 'rails_helper'

# #3176 — o "Sobre a pessoa" que a Prospecção gravou com um tipo cru do Google sai, e o cargo que ela gravou em
# additional_attributes passa para custom_attributes; o resto fica.
RSpec.describe Relationships::ArrumarContatosDaProspeccaoJob do
  let(:account) { create(:account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'lugar-ficticio-1', name: 'Clínica Exemplo',
                                         country: 'BR', category: 'doctor')
  end
  let(:interno) do
    { 'autonomia_prospecting_lead_id' => lead.id, 'autonomia_prospecting_provider' => 'mock',
      'autonomia_prospecting_provider_place_id' => 'lugar-ficticio-1', 'autonomia_prospecting_rating' => 4.7 }
  end
  let!(:contact) do
    create(:contact, account: account, custom_attributes: interno,
                     additional_attributes: { 'description' => 'doctor', 'city' => 'Cidade Exemplo', 'source' => 'autonomia_prospecting' })
  end

  before { lead.update!(contact: contact) }

  # MOTIVO: a categoria em inglês sai do "Sobre a pessoa"; a cidade e as chaves internas (a Prospecção depende delas) ficam.
  it 'tira a categoria crua e mantém o resto', :aggregate_failures do
    expect(described_class.perform_now).to eq(1)

    contact.reload
    expect(contact.additional_attributes).to eq('city' => 'Cidade Exemplo', 'source' => 'autonomia_prospecting')
    expect(contact.custom_attributes).to eq(interno)
  end

  # MOTIVO: rodar de novo não acha nada; o job pode ser repetido sem risco.
  it 'é idempotente' do
    described_class.perform_now

    expect(described_class.perform_now).to eq(0)
  end

  # MOTIVO: o texto que alguém escreveu no "Sobre a pessoa" nunca é apagado.
  it 'não mexe no "Sobre a pessoa" escrito por alguém' do
    contact.update!(additional_attributes: contact.additional_attributes.merge('description' => 'Atende só de manhã.'))

    expect(described_class.perform_now).to eq(0)
    expect(contact.reload.additional_attributes['description']).to eq('Atende só de manhã.')
  end

  # MOTIVO: uma busca nova regrava a categoria do lead; o "Sobre a pessoa" antigo ainda é um tipo do Google daquele lugar.
  it 'tira a categoria antiga quando ela ainda está nos tipos do Google do lugar' do
    lead.update!(category: 'medical_clinic', raw_payload: { 'types' => %w[medical_clinic doctor] })

    expect(described_class.perform_now).to eq(1)
    expect(contact.reload.additional_attributes).not_to have_key('description')
  end

  # MOTIVO: contato que outro lead gravou (mesmo telefone de outro negócio) é daquele lead; este não mexe nele.
  it 'só arruma o contato do próprio lead' do
    outro = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'lugar-ficticio-2', name: 'Outra',
                                                 country: 'BR', category: 'doctor')
    contact.update!(custom_attributes: interno.merge('autonomia_prospecting_lead_id' => outro.id))

    expect(described_class.perform_now).to eq(0)
    expect(contact.reload.additional_attributes['description']).to eq('doctor')
  end

  describe 'cargo' do
    let(:marca) { Autonomia::Prospecting::CargoEscrito::WRITTEN_KEY }

    def com_cargo(adicional:, proprios: {})
      contact.update!(custom_attributes: interno.merge(marca => 'SOCIA').merge(proprios),
                      additional_attributes: contact.additional_attributes.merge('job_title' => adicional))
    end

    # MOTIVO: o cargo que a Prospecção gravou (igual à marca) vai para onde o card, o Decisor e a ficha o leem.
    it 'move o cargo nosso para custom_attributes', :aggregate_failures do
      com_cargo(adicional: 'SOCIA')

      expect(described_class.perform_now).to eq(1)
      contact.reload
      expect(contact.custom_attributes).to include('job_title' => 'SOCIA', marca => 'SOCIA')
      expect(contact.additional_attributes).not_to have_key('job_title')
      expect(described_class.perform_now).to eq(0)
    end

    # MOTIVO: cargo que não é nosso (diferente da marca) não muda de lugar.
    it 'não mexe no cargo que não é nosso', :aggregate_failures do
      com_cargo(adicional: 'Gerente')
      contact.update!(additional_attributes: contact.additional_attributes.except('description'))

      expect(described_class.perform_now).to eq(0)
      expect(contact.reload.additional_attributes['job_title']).to eq('Gerente')
      expect(contact.custom_attributes).not_to have_key('job_title')
    end

    # MOTIVO: o cargo que já está em custom_attributes (o usuário ou o Decisor escreveram) não é sobrescrito.
    it 'não sobrescreve o cargo que já está em custom_attributes', :aggregate_failures do
      com_cargo(adicional: 'SOCIA', proprios: { 'job_title' => 'Diretora' })
      contact.update!(additional_attributes: contact.additional_attributes.except('description'))

      expect(described_class.perform_now).to eq(0)
      expect(contact.reload.custom_attributes['job_title']).to eq('Diretora')
      expect(contact.additional_attributes['job_title']).to eq('SOCIA')
    end
  end

  # MOTIVO: a conferência na conta piloto roda só nela; as outras contas ficam para depois do OK.
  it 'com account_id, só aquela conta' do
    expect(described_class.perform_now(create(:account).id)).to eq(0)
    expect(contact.reload.additional_attributes['description']).to eq('doctor')
    expect(described_class.perform_now(account.id)).to eq(1)
  end
end
