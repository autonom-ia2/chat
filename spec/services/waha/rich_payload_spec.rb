require 'rails_helper'

# chat#1709: rich_message do painel → envio nativo do WAHA. nil quer dizer "sai texto, como antes".
RSpec.describe Waha::RichPayload do
  let(:client) { instance_double(Waha::Client) }

  def build(rich, body: 'Qual horário fica melhor?', locale: 'pt_BR')
    described_class.build(rich.deep_stringify_keys, body: body, locale: locale)
  end

  def deliver(payload)
    payload.deliver(client, session: 'hybrid-5511', chat_id: '5511937016094@c.us', id: '3EB0AAAA')
  end

  describe 'options' do
    let(:three) { { type: 'options', options: [{ id: 'manha', title: 'Manhã' }, { id: 'tarde', title: 'Tarde' }, { id: 'noite', title: 'Noite' }] } }

    it 'sends up to 3 options without description as a LIST, with the default button in the account language' do
      allow(client).to receive(:send_list).and_return({ 'id' => 'true_5511937016094@c.us_3EB0LIST' })

      deliver(build(three))

      expect(client).to have_received(:send_list).with(
        session: 'hybrid-5511', chat_id: '5511937016094@c.us',
        message: { title: 'Qual horário fica melhor?', button: 'Ver opções',
                   sections: [{ title: 'Ver opções', rows: [{ title: 'Manhã', rowId: 'manha' }, { title: 'Tarde', rowId: 'tarde' },
                                                            { title: 'Noite', rowId: 'noite' }] }] }
      )
    end

    it 'uses the English default button for an English account' do
      expect(build(three, locale: 'en').send(:list_message)[:button]).to eq('See options')
    end

    it 'keeps header as title, body as description, footer, the given button, sections and descriptions' do
      rich = { type: 'options', header: 'Agenda', footer: 'Toque em uma opção.', button: 'Ver horários',
               sections: [{ title: 'Semana', options: [{ id: 'seg', title: 'Segunda', description: 'Das 8h às 12h' }] },
                          { title: 'Fim de semana', options: [{ id: 'sab', title: 'Sábado' }] }] }

      expect(build(rich).send(:list_message)).to eq(
        title: 'Agenda', description: 'Qual horário fica melhor?', footer: 'Toque em uma opção.', button: 'Ver horários',
        sections: [{ title: 'Semana', rows: [{ title: 'Segunda', rowId: 'seg', description: 'Das 8h às 12h' }] },
                   { title: 'Fim de semana', rows: [{ title: 'Sábado', rowId: 'sab' }] }]
      )
    end

    it 'does not take a pre-generated id' do
      expect(build(three).pre_generated_id?).to be(false)
    end

    {
      'a row title over 24' => ->(rich) { rich[:options][0][:title] = 'x' * 25 },
      'a description over 72' => ->(rich) { rich[:options][0][:description] = 'x' * 73 },
      'a button over 20 (ignored by the Meta buttons)' => ->(rich) { rich[:button] = 'x' * 21 },
      'more than 10 rows' => ->(rich) { rich[:options] = (1..11).map { |n| { id: "o#{n}", title: "Opção #{n}" } } },
      'a multiline title' => ->(rich) { rich[:options][0][:title] = "Manhã\ncedo" },
      'no options' => ->(rich) { rich[:options] = [] }
    }.each do |reason, change|
      it "falls back to text (nil) with #{reason}" do
        rich = three.deep_dup
        change.call(rich)

        expect(build(rich)).to be_nil
      end
    end

    it 'falls back to text without a body' do
      expect(build(three, body: '')).to be_nil
    end
  end

  describe 'location' do
    it 'sends the coordinates with name and address as the title, and the pre-generated id' do
      allow(client).to receive(:send_location)

      deliver(build({ type: 'location', latitude: -23.5489, longitude: -46.6388, name: 'Unidade Centro', address: 'Rua A, 1' }, body: ''))

      expect(client).to have_received(:send_location).with(
        session: 'hybrid-5511', chat_id: '5511937016094@c.us', id: '3EB0AAAA',
        location: { latitude: -23.5489, longitude: -46.6388, title: 'Unidade Centro - Rua A, 1' }
      )
    end

    it 'uses the default title without name and address' do
      allow(client).to receive(:send_location)

      deliver(build({ type: 'location', latitude: 0, longitude: 0 }, body: ''))

      expect(client).to have_received(:send_location).with(hash_including(location: hash_including(title: 'Localização')))
    end

    it 'falls back to text with an invalid coordinate' do
      expect(build({ type: 'location', latitude: '-23.5', longitude: -46.6 })).to be_nil
    end
  end

  describe 'contact' do
    it 'sends the card with the WhatsApp id and the pre-generated id' do
      allow(client).to receive(:send_contact_vcard)

      deliver(build({ type: 'contact', name: 'Recepção', phone: '+55 11 4000-0473', wa_id: '551140000473' }, body: ''))

      expect(client).to have_received(:send_contact_vcard).with(
        session: 'hybrid-5511', chat_id: '5511937016094@c.us', id: '3EB0AAAA',
        contacts: [{ fullName: 'Recepção', phoneNumber: '+55 11 4000-0473', whatsappId: '551140000473' }]
      )
    end

    it 'leaves the WhatsApp id out when the caller did not send one' do
      payload = build({ type: 'contact', name: 'Recepção', phone: '+55 11 4000-0473' }, body: '')

      expect(payload.send(:contact)).to eq(fullName: 'Recepção', phoneNumber: '+55 11 4000-0473')
    end
  end

  it 'returns nil for the types without a native send in the engine' do
    %w[link_button location_request flow link_preview].each do |type|
      expect(build({ type: type, label: 'Abrir', url: 'https://exemplo.com.br' })).to be_nil
    end
    expect(described_class.build(nil, body: 'x')).to be_nil
  end

  describe '.physical_id' do
    it 'reads the physical id from the shapes the engine answers' do
      expect(described_class.physical_id({ 'id' => 'true_5511937016094@c.us_3EB0LIST' })).to eq('3EB0LIST')
      expect(described_class.physical_id({ 'id' => { '_serialized' => 'true_5511937016094@c.us_3EB0SER' } })).to eq('3EB0SER')
      expect(described_class.physical_id({ 'key' => { 'id' => '3EB0KEY' } })).to eq('3EB0KEY')
      expect(described_class.physical_id({})).to be_nil
      expect(described_class.physical_id(nil)).to be_nil
    end
  end
end
