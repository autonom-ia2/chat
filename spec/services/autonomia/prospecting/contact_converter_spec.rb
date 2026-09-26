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

  it 'WhatsApp verificado gravado como veio vira E.164 no contato, sem quebrar a gravação' do
    lead.update!(metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+55 11 99999-7777' } })

    expect(described_class.new(lead: lead, user: user).perform.contact.phone_number).to eq('+5511999997777')
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

  describe 'dois leads com o mesmo telefone ou e-mail (#680, central única, franquia)' do
    def other_lead(name, **attributes)
      Autonomia::Prospecting::Lead.create!(
        { account: account, provider: 'mock', provider_place_id: "places/#{name}", name: name, country: 'BR' }.merge(attributes)
      )
    end

    it 'o contato do primeiro lead não é renomeado nem passa a ser do segundo' do
      alfa = other_lead('Padaria Alfa', phone: '+55 31 3222-1000')
      beta = other_lead('Oficina Beta', phone: '+55 31 3222-1000')

      first = described_class.new(lead: alfa, user: user).perform
      second = described_class.new(lead: beta, user: user).perform
      contact = first.contact.reload

      expect(second.contact).to eq(contact)
      expect(contact.name).to eq('Padaria Alfa')
      expect(contact.custom_attributes['autonomia_prospecting_lead_id']).to eq(alfa.id)
      expect(contact.company).to eq(first.company)
      expect(second.company).not_to eq(first.company)
    end

    it 'e-mail compartilhado também não troca o dono do contato' do
      alfa = other_lead('Padaria Alfa', enriched_email: 'central@shopping.com.br')
      beta = other_lead('Oficina Beta', enriched_email: 'central@shopping.com.br')
      described_class.new(lead: alfa, user: user).perform

      contact = described_class.new(lead: beta, user: user).perform.contact.reload

      expect(contact.name).to eq('Padaria Alfa')
      expect(contact.custom_attributes['autonomia_prospecting_lead_id']).to eq(alfa.id)
    end

    it 'Usar como contato no segundo lead não renomeia o contato do primeiro, e a empresa do segundo não vira a do primeiro' do
      alfa = other_lead('Padaria Alfa', phone: '+55 31 3222-1000')
      beta = other_lead('Oficina Beta', phone: '+55 31 3222-1000')
      first = described_class.new(lead: alfa, user: user).perform
      beta_company = described_class.new(lead: beta, user: user).perform.company
      beta.update!(decision_name: 'JOAO BETA', decision_role: 'Dono', decision_research_status: 'confirmed')

      again = described_class.new(lead: beta.reload, user: user).perform

      expect(first.contact.reload.name).to eq('Padaria Alfa')
      expect(again.company).to eq(beta_company)
    end
  end

  # Contato que o usuário já tinha e que a prospecção nunca gravou: o nome dele pode coincidir com o do negócio no
  # Google (perfil comercial do WhatsApp), e mesmo assim não é nosso para renomear nem para apagar o cargo.
  describe 'contato do usuário com o mesmo nome do negócio (#680)' do
    it 'decisor não renomeia o contato nem apaga o cargo que o usuário digitou' do
      existing = create(:contact, account: account, name: 'Padaria Alpha', phone_number: '+5531999990001',
                                  additional_attributes: { 'job_title' => 'Atendimento loja centro' })
      padaria = Autonomia::Prospecting::Lead.create!(
        account: account, provider: 'mock', provider_place_id: 'places/padaria', name: 'Padaria Alpha', phone: '+5531999990001',
        country: 'BR', decision_name: 'Joao da Silva', decision_role: 'Dono', decision_research_status: 'not_researched'
      )

      contact = described_class.new(lead: padaria, user: user).perform.contact.reload

      expect(contact).to eq(existing)
      expect(contact.name).to eq('Padaria Alpha')
      expect(contact.additional_attributes['job_title']).to eq('Atendimento loja centro')
    end

    it 'sem decisor, o cargo do contato do usuário fica' do
      create(:contact, account: account, name: 'Oficina Beta', phone_number: '+5531999990002',
                       additional_attributes: { 'job_title' => 'Gerente' })
      oficina = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/oficina',
                                                     name: 'Oficina Beta', phone: '+5531999990002', country: 'BR')

      contact = described_class.new(lead: oficina, user: user).perform.contact.reload

      expect(contact.name).to eq('Oficina Beta')
      expect(contact.additional_attributes['job_title']).to eq('Gerente')
    end

    it 'cargo que nós gravamos troca com o decisor; cargo que o usuário mudou depois fica' do
      lead.update!(decision_name: 'ANA SOUZA', decision_role: 'SOCIA', decision_research_status: 'not_researched')
      contact = described_class.new(lead: lead, user: user).perform.contact
      expect(contact.additional_attributes['job_title']).to eq('SOCIA')

      lead.update!(decision_name: 'BRUNO LIMA', decision_role: 'SOCIO')
      expect(described_class.new(lead: lead, user: user).perform.contact.additional_attributes['job_title']).to eq('SOCIO')

      contact.reload.update!(additional_attributes: contact.additional_attributes.merge('job_title' => 'Diretor comercial'))
      lead.update!(decision_name: 'CARLA DIAS', decision_role: 'SOCIA')
      renamed = described_class.new(lead: lead, user: user).perform.contact
      expect(renamed.name).to eq('CARLA DIAS')
      expect(renamed.additional_attributes['job_title']).to eq('Diretor comercial')
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

  describe 'recusa gravada no contato (chat#713)' do
    it 'contato criado a partir de lead recusado nasce com a recusa da Prospecção' do
      lead.update!(status: :no_consent)

      contact = described_class.new(lead: lead, user: user).perform.contact

      expect(contact).to be_opted_out
      expect(contact.opt_out_source).to eq('prospecting')
      expect(contact.opted_out_by_id).to be_nil
    end

    it 'contato criado para outro lead do mesmo número que um lead recusado herda a recusa' do
      Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'mock-place-recusou',
                                           name: 'Matriz', phone: '+55 11 99999-8888', country: 'BR', status: :no_consent)

      contact = described_class.new(lead: lead, user: user).perform.contact

      expect(contact).to be_opted_out
      expect(contact.opt_out_source).to eq('prospecting')
    end

    it 'lead sem recusa não marca o contato' do
      contact = described_class.new(lead: lead, user: user).perform.contact

      expect(contact).not_to be_opted_out
    end

    it 'não troca a recusa manual do contato existente' do
      existing = create(:contact, account: account, phone_number: '+5511999998888')
      existing.opt_out!(source: 'manual', by: user)
      lead.update!(status: :no_consent)

      described_class.new(lead: lead, user: user).perform

      expect(existing.reload.opt_out_source).to eq('manual')
    end
  end
end
