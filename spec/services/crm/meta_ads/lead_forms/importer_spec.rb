require 'rails_helper'

# Um lead do formulário do anúncio (#2195) vira contato e card na etapa escolhida, com a origem e as respostas no card.
# O mesmo lead duas vezes (webhook repetido, "trazer antigos" depois do webhook) não cria nada de novo, e quem já tem
# card aberto naquele funil não ganha outro.
RSpec.describe Crm::MetaAds::LeadForms::Importer do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { create_crm_stage(account: account, pipeline: pipeline, name: 'Qualificar') }
  let(:form) do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento de verão',
                                 pipeline: pipeline, stage: stage)
  end
  let(:questions) { [{ 'key' => 'full_name', 'label' => 'Nome completo' }, { 'key' => 'quando', 'label' => 'Para quando?' }] }
  let(:importer) do
    described_class.new(account: account, pipeline: pipeline, stage: stage, form_name: form.form_name, page_id: '104882', questions: questions)
  end

  def lead(id: 'L1', phone: '+5511987651201', email: 'mariana@example.com', name: 'Mariana Lopes')
    {
      'id' => id, 'created_time' => '2026-10-27T12:00:00+0000', 'form_id' => '9001', 'ad_id' => '120001',
      'ad_name' => 'Verão — carrossel 2', 'campaign_name' => 'Verão 2026',
      'field_data' => [
        { 'name' => 'full_name', 'values' => [name] },
        { 'name' => 'phone_number', 'values' => [phone] },
        { 'name' => 'email', 'values' => [email] },
        { 'name' => 'quando', 'values' => ['Dezembro'] }
      ]
    }
  end

  it 'cria contato e card na etapa escolhida, com a origem e as respostas no card' do
    expect(importer.import(lead)).to eq(:created)

    card = account.crm_cards.last
    expect(card).to have_attributes(pipeline_id: pipeline.id, stage_id: stage.id, title: 'Mariana Lopes', source: 'meta_lead_form')
    expect(card.contact).to have_attributes(name: 'Mariana Lopes', phone_number: '+5511987651201', email: 'mariana@example.com')
    origem = card.metadata['meta_lead_form']
    expect(origem).to include('form_name' => 'Orçamento de verão', 'ad_name' => 'Verão — carrossel 2', 'leadgen_id' => 'L1',
                              'captured_at' => '2026-10-27T12:00:00Z')
    expect(origem['fields']).to include({ 'key' => 'full_name', 'label' => 'Nome completo', 'value' => 'Mariana Lopes' },
                                        { 'key' => 'quando', 'label' => 'Para quando?', 'value' => 'Dezembro' })
    expect(Crm::MetaAdsLead.last).to have_attributes(leadgen_id: 'L1', card_id: card.id, contact_id: card.contact_id,
                                                     new_contact: true, form_id: '9001', ad_name: 'Verão — carrossel 2')
  end

  it 'o mesmo lead de novo não cria outro card nem outro contato' do
    importer.import(lead)

    expect(importer.import(lead)).to eq(:duplicate)
    expect(account.crm_cards.count).to eq(1)
    expect(account.contacts.count).to eq(1)
  end

  it 'contato que já existe pelo telefone: usa o mesmo contato' do
    contact = account.contacts.create!(name: 'Mariana', phone_number: '+5511987651201')

    importer.import(lead(email: nil))

    expect(account.crm_cards.last.contact_id).to eq(contact.id)
    expect(Crm::MetaAdsLead.last.new_contact).to be(false)
  end

  it 'contato que já existe pelo e-mail: usa o mesmo contato' do
    contact = account.contacts.create!(name: 'Mariana', email: 'Mariana@Example.com')

    importer.import(lead(phone: ''))

    expect(account.crm_cards.last.contact_id).to eq(contact.id)
  end

  it 'quem já tem card aberto neste funil não ganha outro' do
    contact = account.contacts.create!(name: 'Mariana', phone_number: '+5511987651201')
    existing = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Mariana')

    expect(importer.import(lead)).to eq(:existing_card)
    expect(account.crm_cards.count).to eq(1)
    expect(Crm::MetaAdsLead.last.card_id).to eq(existing.id)
  end

  it 'telefone sem código do país fica só nas respostas: o contato nasce sem telefone' do
    importer.import(lead(phone: '11 98765-1201'))

    card = account.crm_cards.last
    expect(card.contact.phone_number).to be_nil
    expect(card.metadata['meta_lead_form']['fields']).to include(include('key' => 'phone_number', 'value' => '11 98765-1201'))
  end

  it 'sem nome, telefone com DDI nem e-mail: o card nasce com "Lead" e o id, sem o nome do formulário (#2562)' do
    lead_sem_contato = lead(name: '', phone: '11 98765-1201', email: '')

    expect(importer.import(lead_sem_contato)).to eq(:created)
    expect(account.crm_cards.last.title).to eq('Lead L1')
  end

  # O título vai à IA (Decisor, IA de etapa) e a quem não vê o contato: telefone e e-mail nunca entram nele.
  it 'sem nome, com telefone e e-mail: o título é "Lead" e o id, sem telefone nem e-mail' do
    importer.import(lead(name: ''))

    card = account.crm_cards.last
    expect(card.title).to eq('Lead L1')
    expect(card.contact.phone_number).to eq('+5511987651201')
    decisor = build(:autonomia_decisor, account: account)
    estado = Autonomia::Decisores::Estado.new(card: card, leituras: %w[card contato])
    expect([estado.para_o_jev(decisor).to_json, estado.trecho]).to all(satisfy do |texto|
      texto.exclude?('987651201') && texto.exclude?('mariana@example.com')
    end)
  end

  it 'nome que é um e-mail: título e contato ficam sem ele, e o título é "Lead" e o id' do
    importer.import(lead(name: 'mariana@example.com'))

    card = account.crm_cards.last
    expect(card.title).to eq('Lead L1')
    expect(card.contact.name.to_s).not_to include('mariana@example.com')
  end

  it 'nome que é um telefone: título e contato ficam sem ele, e o título é "Lead" e o id' do
    importer.import(lead(name: '(11) 98765-1201'))

    card = account.crm_cards.last
    expect(card.title).to eq('Lead L1')
    expect(card.contact.name.to_s).not_to include('98765-1201')
  end

  it 'sem nome e sem nome do formulário: o título é "Lead" e o id' do
    sem_formulario = described_class.new(account: account, pipeline: pipeline, stage: stage, form_name: nil)

    sem_formulario.import(lead(name: ''))

    expect(account.crm_cards.last.title).to eq('Lead L1')
  end

  it 'e-mail que o contato não aceita: o lead entra, o contato nasce sem e-mail e a resposta fica no card' do
    expect(importer.import(lead(email: 'mariana@'))).to eq(:created)

    card = account.crm_cards.last
    expect(card.contact.email).to be_nil
    expect(card.metadata['meta_lead_form']['fields']).to include(include('key' => 'email', 'value' => 'mariana@'))
  end

  it 'guarda a Página de onde o lead veio' do
    importer.import(lead)

    expect(Crm::MetaAdsLead.last.page_id).to eq('104882')
  end

  it 'lead que o banco recusa vira :failed, vai ao rastreador e não reserva o leadgen_id' do
    allow(Crm::Cards::Creator).to receive(:new).and_raise(ActiveRecord::RecordInvalid.new(Crm::Card.new))
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    expect(importer.import(lead)).to eq(:failed)
    expect(tracker).to have_received(:capture_exception)
    expect(Crm::MetaAdsLead.count).to eq(0)
  end

  # #2804: a recusa diz de onde veio, para a reconciliação saber quando tentar de novo (RefusedLeads).
  describe 'tipo da recusa' do
    let(:refused) { instance_double(Crm::MetaAds::LeadForms::RefusedLeads, remember!: true) }
    let(:importer) do
      described_class.new(account: account, pipeline: pipeline, stage: stage, form_name: form.form_name, page_id: '104882',
                          questions: questions, refused: refused)
    end

    before do
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
    end

    def recusa(record, attribute, error)
      record.errors.add(attribute, error)
      ActiveRecord::RecordInvalid.new(record)
    end

    it 'card recusado pelo funil ou pela etapa: recusa do destino' do
      allow(Crm::Cards::Creator).to receive(:new).and_raise(recusa(Crm::Card.new, :stage, :invalid))

      expect(importer.import(lead)).to eq(:failed)
      expect(refused).to have_received(:remember!).with('L1', :destination)
    end

    it 'card recusado só pelo título ou pelas respostas: recusa do lead' do
      allow(Crm::Cards::Creator).to receive(:new).and_raise(recusa(Crm::Card.new, :metadata, :invalid))

      importer.import(lead)

      expect(refused).to have_received(:remember!).with('L1', :lead)
    end

    it 'contato recusado pelo dado do lead: recusa do lead' do
      allow_any_instance_of(Contact).to receive(:save!).and_raise(recusa(Contact.new, :name, :too_long)) # rubocop:disable RSpec/AnyInstance

      importer.import(lead)

      expect(refused).to have_received(:remember!).with('L1', :lead)
    end

    it 'contato que outro processo acabou de gravar (unicidade): recusa passageira' do
      allow_any_instance_of(Contact).to receive(:save!).and_raise(recusa(Contact.new, :phone_number, :taken)) # rubocop:disable RSpec/AnyInstance

      importer.import(lead)

      expect(refused).to have_received(:remember!).with('L1', :transient)
    end

    it 'índice único fora da reserva do lead (corrida no banco): :failed passageiro, sem derrubar o lote' do
      allow(Crm::Cards::Creator).to receive(:new).and_raise(ActiveRecord::RecordNotUnique, 'duplicate key')

      expect(importer.import(lead)).to eq(:failed)
      expect(refused).to have_received(:remember!).with('L1', :transient)
      expect(Crm::MetaAdsLead.count).to eq(0)
    end

    it 'impasse no banco (deadlock): :failed passageiro' do
      allow(Crm::Cards::Creator).to receive(:new).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')

      expect(importer.import(lead)).to eq(:failed)
      expect(refused).to have_received(:remember!).with('L1', :transient)
    end
  end

  it 'telefone com espaço e traço vira E.164' do
    importer.import(lead(phone: '+55 11 98765-1201'))

    expect(account.crm_cards.last.contact.phone_number).to eq('+5511987651201')
  end
end
