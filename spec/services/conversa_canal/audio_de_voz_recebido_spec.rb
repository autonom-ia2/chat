require 'rails_helper'

# #1702: a Cloud API diz se o áudio é nota de voz (`audio.voice`). A marca vira `meta.is_voice_message` no anexo e vai
# para a tela dentro de `meta`, como no WhatsApp Híbrido (#1709). Sem a pele ligada, nada muda.
describe ConversaCanal::AudioDeVozRecebido do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:media_id) { 'audio-media-id' }

  before do
    channel.account.enable_features!('conversa_cara_do_canal')
    stub_request(:get, channel.media_url(media_id)).to_return(
      status: 200,
      body: { url: 'https://chatwoot-assets.local/voz.ogg', mime_type: 'audio/ogg', id: media_id }.to_json,
      headers: { 'content-type' => 'application/json' }
    )
    stub_request(:get, 'https://chatwoot-assets.local/voz.ogg').to_return(
      status: 200, body: File.read('spec/assets/sample.ogg'), headers: { 'content-type' => 'audio/ogg' }
    )
  end

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  def receive(audio, id: 'wamid.audio')
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: '5511900000001' }],
        messages: [{ from: '5511900000001', id: id, timestamp: '1760371920', type: 'audio', audio: audio }]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    Message.find_by!(source_id: id)
  end

  it 'marks a voice note recorded in the app' do
    attachment = receive({ id: media_id, mime_type: 'audio/ogg; codecs=opus', voice: true }).attachments.sole

    expect(attachment.meta).to eq('is_voice_message' => true)
    expect(attachment.push_event_data[:meta]).to include('is_voice_message' => true)
  end

  it 'marks an audio file as not a voice note' do
    attachment = receive({ id: media_id, mime_type: 'audio/ogg', voice: false }).attachments.sole

    expect(attachment.meta).to eq('is_voice_message' => false)
    expect(attachment.push_event_data[:meta]).to include('is_voice_message' => false)
  end

  it 'records nothing when the notice does not say' do
    attachment = receive({ id: media_id, mime_type: 'audio/ogg' }).attachments.sole

    expect(attachment.meta).to be_blank
    expect(attachment.push_event_data).not_to have_key(:meta)
  end

  it 'changes nothing when the conversa_cara_do_canal flag is off' do
    channel.account.disable_features!('conversa_cara_do_canal')

    attachment = receive({ id: media_id, mime_type: 'audio/ogg', voice: true }).attachments.sole

    expect(attachment.meta).to be_blank
    expect(attachment.push_event_data).not_to have_key(:meta)
  end

  it 'does not expose the panel recording mark with the flag off' do
    message = receive({ id: media_id, mime_type: 'audio/ogg', voice: true })
    channel.account.disable_features!('conversa_cara_do_canal')

    expect(message.attachments.sole.reload.push_event_data).not_to have_key(:meta)
  end
end
