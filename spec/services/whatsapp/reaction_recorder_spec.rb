require 'rails_helper'

# #1702: a reação do cliente fica na mensagem reagida (selo), nunca vira balão novo.
describe Whatsapp::ReactionRecorder do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) do
    create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account, status: :resolved)
  end
  let!(:reacted) do
    create(:message, message_type: :outgoing, content: 'Proposta enviada', conversation: conversation, account: inbox.account,
                     inbox: inbox, source_id: 'wamid.REAGIDA', content_attributes: { 'external_echo' => true })
  end

  def react(emoji, source_id: 'wamid.REAGIDA', at: Time.zone.parse('2026-10-16 10:00'))
    described_class.new(inbox: inbox, reacted_source_id: source_id, emoji: emoji, reacted_at: at).perform
  end

  def reactions
    reacted.reload.content_attributes['reactions']
  end

  it 'grava a reação na mensagem reagida, sem criar mensagem' do
    expect { react('👍') }.not_to change(Message, :count)

    expect(reactions).to eq([{ 'emoji' => '👍', 'sender_type' => 'Contact', 'sender_id' => contact.id,
                               'at' => '2026-10-16T10:00:00Z' }])
    expect(reacted.content_attributes['external_echo']).to be(true)
  end

  it 'troca a reação anterior do mesmo autor' do
    react('👍')
    react('❤️', at: Time.zone.parse('2026-10-16 10:05'))

    expect(reactions.pluck('emoji')).to eq(['❤️'])
  end

  it 'mantém a reação de outro autor' do
    reacted.update!(content_attributes: { 'reactions' => [{ 'emoji' => '🙏', 'sender_type' => 'User', 'sender_id' => 9 }] })

    react('👍')

    expect(reactions.pluck('emoji')).to eq(%w[🙏 👍])
  end

  it 'tira a reação quando o emoji vem vazio e limpa a chave' do
    react('👍')
    react('', at: Time.zone.parse('2026-10-16 10:05'))

    expect(reacted.reload.content_attributes).not_to have_key('reactions')
  end

  it 'tira a reação quando o emoji não vem (como a Cloud API manda)' do
    react('👍')
    react(nil, at: Time.zone.parse('2026-10-16 10:05'))

    expect(reactions).to be_nil
  end

  it 'ignora reação mais antiga que a gravada do mesmo autor (entrega fora de ordem)' do
    react('❤️', at: Time.zone.parse('2026-10-16 10:05'))
    react('👍', at: Time.zone.parse('2026-10-16 10:00'))

    expect(reactions.pluck('emoji')).to eq(['❤️'])
  end

  it 'não reabre nem mexe na conversa' do
    expect { react('👍') }.not_to(change { conversation.reload.status })
  end

  it 'dispara a atualização da mensagem para o painel' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    react('👍')

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::MESSAGE_UPDATED, anything, hash_including(message: reacted))
  end

  it 'não dispara nada quando a reação repetida não muda a mensagem' do
    react('👍')
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    react('👍')

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_UPDATED, any_args)
  end

  it 'ignora em silêncio (log info) quando a mensagem reagida não está no banco' do
    allow(Rails.logger).to receive(:info)

    expect { expect(react('👍', source_id: 'wamid.NAO_EXISTE')).to be_nil }.not_to change(Message, :count)
    expect(Rails.logger).to have_received(:info).with(/reacted message not found/)
  end

  it 'não procura em outra caixa' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    result = described_class.new(inbox: other.inbox, reacted_source_id: 'wamid.REAGIDA', emoji: '👍').perform

    expect(result).to be_nil
    expect(reactions).to be_nil
  end

  it 'acha a mensagem da caixa híbrida pelo id físico quando o eco da Meta ainda não chegou' do
    reacted.update!(source_id: '3EB0AAAA')
    wamid = "wamid.#{Base64.strict_encode64("#{[0x18, 8].pack('C*')}3EB0AAAA")}"

    react('👍', source_id: wamid)

    expect(reactions.pluck('emoji')).to eq(['👍'])
  end
end
