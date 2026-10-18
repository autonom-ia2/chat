require 'rails_helper'

# #1702: a figurinha do WhatsApp chega como `type: "sticker"`. Continua anexo de foto, com a marca `meta.is_sticker`,
# e a marca sai no anexo que vai para a tela e para os webhooks.
describe ConversaCanal::FigurinhaRecebida do
  # O canal 360dialog registra o webhook ao nascer.
  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    channel.account.enable_features!('conversa_cara_do_canal')
  end

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  let(:media_id) { 'figurinha-media-id' }
  let(:webp) { File.read('spec/assets/booking_small.webp') }

  def cloud_params(channel, type, media)
    {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: '5511900000001' }],
        messages: [{ from: '5511900000001', id: "wamid.#{type}", timestamp: '1760371920', type: type }.merge(type => media)]
      } }] }]
    }.with_indifferent_access
  end

  context 'with the Cloud API' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

    before do
      stub_request(:get, channel.media_url(media_id)).to_return(
        status: 200,
        body: { url: 'https://chatwoot-assets.local/figurinha.webp', mime_type: 'image/webp', id: media_id }.to_json,
        headers: { 'content-type' => 'application/json' }
      )
      stub_request(:get, 'https://chatwoot-assets.local/figurinha.webp').to_return(
        status: 200, body: webp, headers: { 'content-type' => 'image/webp' }
      )
    end

    def receive(type, media)
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: cloud_params(channel, type, media)).perform
      Message.find_by!(source_id: "wamid.#{type}")
    end

    it 'does not mark the sticker when the conversa_cara_do_canal flag is off' do
      channel.account.disable_features!('conversa_cara_do_canal')

      attachment = receive('sticker', { id: media_id, mime_type: 'image/webp' }).attachments.sole

      expect(attachment.file_type).to eq('image')
      expect(attachment.meta).to be_blank
    end

    it 'keeps the sticker as an image attachment marked as sticker' do
      attachment = receive('sticker', { id: media_id, mime_type: 'image/webp', animated: false }).attachments.sole

      expect(attachment.file_type).to eq('image')
      expect(attachment.meta).to eq('is_sticker' => true)
      expect(attachment.file).to be_attached
    end

    it 'marks an animated sticker the same way' do
      attachment = receive('sticker', { id: media_id, mime_type: 'image/webp', animated: true }).attachments.sole

      expect(attachment.meta['is_sticker']).to be(true)
    end

    it 'sends the mark with the attachment to the dashboard and the webhooks' do
      message = receive('sticker', { id: media_id, mime_type: 'image/webp' })

      expect(message.attachments.sole.push_event_data[:is_sticker]).to be(true)
      expect(message.webhook_data[:attachments].sole[:is_sticker]).to be(true)
    end

    it 'leaves a regular photo without the mark' do
      attachment = receive('image', { id: media_id, mime_type: 'image/jpeg' }).attachments.sole

      expect(attachment.file_type).to eq('image')
      expect(attachment.meta).to be_blank
      expect(attachment.push_event_data).not_to have_key(:is_sticker)
    end

    it 'marks the sticker the business sent from the phone app (coexistence echo)' do
      params = {
        object: 'whatsapp_business_account',
        entry: [{ changes: [{ field: 'smb_message_echoes', value: {
          message_echoes: [{ from: channel.phone_number.delete('+'), to: '5511900000001', id: 'wamid.sticker-echo',
                             timestamp: '1760371920', type: 'sticker', sticker: { id: media_id, mime_type: 'image/webp' } }]
        } }] }]
      }.with_indifferent_access

      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform
      message = Message.find_by!(source_id: 'wamid.sticker-echo')

      expect(message).to be_outgoing
      expect(message.attachments.sole.meta).to eq('is_sticker' => true)
    end

    it 'creates the message without an attachment when the download fails' do
      stub_request(:get, channel.media_url(media_id)).to_return(status: 404)

      message = receive('sticker', { id: media_id, mime_type: 'image/webp' })

      expect(message.attachments).to be_empty
    end
  end

  context 'with 360dialog' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }

    it 'marks the sticker the same way' do
      stub_request(:get, channel.media_url(media_id)).to_return(status: 200, body: webp, headers: { 'content-type' => 'image/webp' })
      params = {
        contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: '5511900000001' }],
        messages: [{ from: '5511900000001', id: 'wamid.sticker-360', timestamp: '1760371920', type: 'sticker',
                     sticker: { id: media_id, mime_type: 'image/webp' } }]
      }.with_indifferent_access

      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
      attachment = Message.find_by!(source_id: 'wamid.sticker-360').attachments.sole

      expect(attachment.file_type).to eq('image')
      expect(attachment.meta).to eq('is_sticker' => true)
    end
  end
end
