require 'rails_helper'

describe Instagram::MessageEditService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_instagram, account: account, instagram_id: 'ig-business-1') }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'ig-customer-1') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                     message_type: :incoming, source_id: 'mid-1', content: 'Tem a bolsa em preto?')
  end

  def messaging(text: 'Tem a bolsa em marrom?', mid: 'mid-1', num_edit: 1, sender: 'ig-customer-1', timestamp: 1_760_000_000_000)
    {
      sender: { id: sender },
      recipient: { id: 'ig-business-1' },
      timestamp: timestamp,
      message_edit: { mid: mid, text: text, num_edit: num_edit }
    }.with_indifferent_access
  end

  def perform(**args)
    described_class.new(messaging: messaging(**args), channel: channel).perform
  end

  it 'troca o texto pelo novo, guarda o anterior e marca a edição com o cliente como autor' do
    perform

    message.reload
    expect(message.content).to eq('Tem a bolsa em marrom?')
    expect(message.content_attributes['edited_at']).to be_present
    entry = message.content_attributes['edit_history'].last
    expect(entry).to include('content' => 'Tem a bolsa em preto?', 'sender_type' => 'Contact', 'sender_id' => contact.id,
                             'sequence' => 1)
  end

  it 'aplica as edições em ordem e não deixa uma edição velha voltar o texto' do
    perform(text: 'segunda versão', num_edit: 2)
    perform(text: 'primeira versão', num_edit: 1)
    perform(text: 'segunda versão de novo', num_edit: 2)

    message.reload
    expect(message.content).to eq('segunda versão')
    expect(message.content_attributes['edit_history'].size).to eq(1)
  end

  it 'aceita a edição seguinte depois de uma anterior' do
    perform(text: 'primeira versão', num_edit: 1)
    perform(text: 'segunda versão', num_edit: 2)

    message.reload
    expect(message.content).to eq('segunda versão')
    expect(message.content_attributes['edit_history'].pluck('content')).to eq(['Tem a bolsa em preto?', 'primeira versão'])
  end

  it 'mid desconhecido não quebra nem muda nada' do
    expect { perform(mid: 'mid-que-nao-existe') }.not_to raise_error

    expect(message.reload.content).to eq('Tem a bolsa em preto?')
  end

  it 'mensagem apagada pelo cliente não volta' do
    message.update!(content: 'Esta mensagem foi apagada', deleted: true)

    perform

    expect(message.reload.content).to eq('Esta mensagem foi apagada')
    expect(message.content_attributes['edit_history']).to be_nil
  end

  it 'não edita mensagem de outro contato com o mesmo mid' do
    perform(sender: 'outro-cliente')

    expect(message.reload.content).to eq('Tem a bolsa em preto?')
  end

  it 'não edita mensagem nossa (saída)' do
    message.update!(message_type: :outgoing, sender: nil)

    perform

    expect(message.reload.content).to eq('Tem a bolsa em preto?')
  end

  it 'texto vazio não apaga o texto da mensagem' do
    perform(text: '  ')

    expect(message.reload.content).to eq('Tem a bolsa em preto?')
  end

  it 'mensagem de outra caixa com o mesmo mid fica como está' do
    other_channel = create(:channel_instagram, account: account, instagram_id: 'ig-business-2')

    described_class.new(messaging: messaging, channel: other_channel).perform

    expect(message.reload.content).to eq('Tem a bolsa em preto?')
  end
end
