require 'rails_helper'

RSpec.describe Autonomia::Prospecting::ContactConverter do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account,
      provider: 'mock',
      provider_place_id: 'mock-place-1',
      name: 'Alpha Restaurante',
      phone: '+55 11 99999-8888',
      website: 'https://alpha.example.com',
      address: 'Rua das Flores, 123',
      city: 'Sao Paulo',
      state: 'SP',
      country: 'BR',
      category: 'Restaurante'
    )
  end

  it 'creates a contact and links it to the prospecting lead' do
    result = described_class.new(lead: lead, user: user).perform

    expect(result.created).to be(true)
    expect(result.contact).to be_persisted
    expect(result.contact.name).to eq('Alpha Restaurante')
    expect(result.contact.phone_number).to eq('+5511999998888')
    expect(result.contact.identifier).to eq('prospecting:mock:mock-place-1')
    expect(result.lead.contact_id).to eq(result.contact.id)
  end

  it 'reuses an existing account contact by normalized phone number' do
    contact = create(:contact, account: account, phone_number: '+5511999998888')

    result = described_class.new(lead: lead, user: user).perform

    expect(result.created).to be(false)
    expect(result.contact).to eq(contact)
    expect(result.lead.contact_id).to eq(contact.id)
  end

  it 'returns the linked contact when lead was already converted' do
    contact = create(:contact, account: account, phone_number: '+5511999998888')
    lead.update!(contact: contact)

    result = described_class.new(lead: lead, user: user).perform

    expect(result.created).to be(false)
    expect(result.contact).to eq(contact)
  end

  describe 'empresa e decisor (#680)' do
    let(:profile) do
      Autonomia::Prospecting::CompanyProfile.create!(
        cnpj: '11222333000181', legal_name: 'ALPHA RESTAURANTE LTDA', trade_name: 'Alpha Gastronomia', registration_status: 'ATIVA',
        registration_state: 'SP', verified_at: Time.zone.parse('2026-09-20 10:00')
      )
    end
    let(:researched) do
      {
        company_profile: profile, company_research_status: 'confirmed', decision_research_status: 'confirmed',
        decision_name: 'ANA SOUZA', decision_role: 'SOCIO ADMINISTRADOR', decision_confidence: 0.9,
        decision_linkedin: 'https://www.linkedin.com/in/anasouza', enriched_email: 'contato@alpha.example.com',
        enriched_instagram: 'https://instagram.com/alpharest', enriched_facebook: 'https://facebook.com/alpharest',
        metadata: { 'research' => { 'owners' => [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }] },
                    'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5511999998888' } }
      }
    end

    def convert(target = lead)
      described_class.new(lead: target, user: user).perform
    end

    it 'com decisor confirmado, o contato é a pessoa: nome, cargo, empresa, e-mail, WhatsApp verificado e redes' do
      lead.update!(researched)

      result = convert
      contact = result.contact

      expect(contact.name).to eq('ANA SOUZA')
      expect(contact.company).to eq(result.company)
      expect(result.company).to have_attributes(name: 'Alpha Gastronomia', account_id: account.id)
      expect(contact.email).to eq('contato@alpha.example.com')
      expect(contact.phone_number).to eq('+5511999998888')
      expect(contact.additional_attributes).to include(
        'job_title' => 'SOCIO ADMINISTRADOR', 'company_name' => 'Alpha Gastronomia',
        'social_profiles' => include('linkedin' => 'in/anasouza', 'instagram' => 'alpharest', 'facebook' => 'alpharest')
      )
    end

    it 'decisor possível também é a pessoa; decisor antigo, de antes da pesquisa, também' do
      lead.update!(researched.merge(decision_research_status: 'possible', company_research_status: 'possible'))
      expect(convert.contact.name).to eq('ANA SOUZA')

      old = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/old', name: 'Beta Bar',
                                                 decision_name: 'Carlos Lima', decision_role: 'Dono')
      expect(convert(old).contact).to have_attributes(name: 'Carlos Lima')
      expect(convert(old).contact.additional_attributes['job_title']).to eq('Dono')
    end

    it 'sem decisor (pesquisa sem resultado), o contato é a própria empresa, vinculado a ela' do
      lead.update!(researched.merge(decision_research_status: 'no_result'))

      result = convert

      expect(result.contact.name).to eq('Alpha Gastronomia')
      expect(result.contact.company).to eq(result.company)
      expect(result.contact.additional_attributes).not_to have_key('job_title')
    end

    it 'reenvio não duplica contato nem empresa' do
      lead.update!(researched)
      first = convert

      expect { convert }.not_to change(Contact, :count)
      expect(Company.where(account: account).count).to eq(1)
      expect(convert.contact).to eq(first.contact)
      expect(convert.created).to be(false)
    end

    it 'acha o contato existente pelo e-mail' do
      lead.update!(researched.merge(phone: nil, metadata: {}))
      existing = create(:contact, account: account, email: 'contato@alpha.example.com', phone_number: nil)

      result = convert

      expect(result.created).to be(false)
      expect(result.contact).to eq(existing)
    end

    it 'contato existente mantém o nome que o usuário deu e a empresa que já tinha; só ganha o que está vazio' do
      lead.update!(researched)
      user_company = Company.create!(account: account, name: 'Empresa que o usuário escolheu')
      existing = create(:contact, account: account, name: 'Ana (cliente antiga)', phone_number: '+5511999998888',
                                  company: user_company, additional_attributes: { 'job_title' => 'Diretora' })

      contact = convert.contact.reload

      expect(contact).to eq(existing)
      expect(contact.name).to eq('Ana (cliente antiga)')
      expect(contact.company).to eq(user_company)
      expect(contact.additional_attributes['job_title']).to eq('Diretora')
      expect(contact.email).to eq('contato@alpha.example.com')
    end

    it 'lead convertido antes da empresa existir ganha a empresa no contato já vinculado' do
      legacy = create(:contact, account: account, name: 'Alpha Restaurante', phone_number: '+5511999998888')
      lead.update!(contact: legacy)

      result = convert

      expect(result.contact).to eq(legacy)
      expect(legacy.reload.company).to eq(result.company)
    end

    it 'e-mail já usado por outro contato da conta não é copiado (não quebra a gravação)' do
      create(:contact, account: account, email: 'contato@alpha.example.com', phone_number: '+5511911112222')
      lead.update!(researched)
      create(:contact, account: account, name: 'Outro', phone_number: '+5511999998888')

      expect(convert.contact.email).to be_blank
    end
  end

  describe 'telefone do contato pela tabela compartilhada com o front' do
    ProspectingPhoneContractCases.all.each do |item|
      it "#{item['caso']}: #{item['raw'].inspect} grava #{item['e164'].inspect}" do
        ProspectingPhoneContractCases.apply_region!(account, item['region'])
        lead.update!(phone: item['raw'])

        result = described_class.new(lead: lead, user: user).perform

        expect(result.contact.phone_number).to eq(item['e164'])
      end
    end

    it 'não confunde número nacional com DDI: (11) 3333-4444 vira +551133334444, não +1133334444' do
      lead.update!(phone: '(11) 3333-4444')

      expect(described_class.new(lead: lead, user: user).perform.contact.phone_number).to eq('+551133334444')
    end
  end
end
