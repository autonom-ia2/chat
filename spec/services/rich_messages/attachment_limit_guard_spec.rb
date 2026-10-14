require 'rails_helper'

# chat#1473 (P4, opção A): no WhatsApp (Cloud, 360dialog e Híbrido, a mesma caixa `Channel::Whatsapp`) só o 1º
# anexo de uma mensagem saía, em silêncio. Mensagem com 2 ou mais anexos falha com o motivo e nada sai, nem o 1º.
# Com 0 ou 1 anexo, e nos outros canais, o envio é o de sempre.
describe RichMessages::AttachmentLimitGuard do
  let(:graph_url) { "https://graph.facebook.com/v24.0/#{channel.provider_config['phone_number_id']}/messages" }
  let(:text_url) { "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages" }
  let(:success) { { status: 200, body: { messages: [{ id: 'wamid.anexo-1' }] }.to_json, headers: { 'content-type' => 'application/json' } } }

  def outgoing_message(conversation, content: 'Segue o arquivo', files: 1)
    message = build(:message, message_type: :outgoing, content: content, conversation: conversation, account: conversation.account,
                              inbox: conversation.inbox)
    files.times do |index|
      attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
      attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: "foto-#{index}.png", content_type: 'image/png')
    end
    message.save!
    message
  end

  def open_window(conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, account: conversation.account,
                     inbox: conversation.inbox)
  end

  context 'with a WhatsApp Cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox, account: channel.account) }

    before do
      open_window(conversation)
      allow(Whatsapp::MediaUploadService).to receive(:new).and_return(instance_double(Whatsapp::MediaUploadService, perform: { 'id' => 'media-1' }))
    end

    it 'fails a message with two attachments with the reason and sends nothing, not even the first' do
      message = outgoing_message(conversation, files: 2)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload).to be_failed
      expect(message.external_error).to eq(RichMessages::AttachmentLimit::ONE_PER_MESSAGE)
      expect(message.source_id).to be_nil
      expect(a_request(:post, graph_url)).not_to have_been_made
      expect(a_request(:post, text_url)).not_to have_been_made
    end

    it 'sends a message with one attachment exactly as before (the panel sends one file per message)' do
      request = stub_request(:post, graph_url)
                .with(body: { messaging_product: 'whatsapp', context: nil, to: '5511937016094', type: 'image',
                              image: { id: 'media-1', caption: 'Segue o arquivo' } }.to_json)
                .to_return(success)
      message = outgoing_message(conversation, files: 1)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_made.once
      expect(message.reload).not_to be_failed
      expect(message.source_id).to eq('wamid.anexo-1')
    end

    it 'sends a text message without attachments exactly as before' do
      request = stub_request(:post, text_url)
                .with(body: { messaging_product: 'whatsapp', context: nil, to: '5511937016094', text: { body: 'Só texto' },
                              type: 'text' }.to_json)
                .to_return(success)
      message = outgoing_message(conversation, content: 'Só texto', files: 0)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_made.once
      expect(message.reload.source_id).to eq('wamid.anexo-1')
    end

    it 'does not touch a private note with two attachments' do
      message = outgoing_message(conversation, files: 2)
      message.update!(private: true)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload).not_to be_failed
      expect(message.external_error).to be_nil
    end
  end

  context 'with a 360dialog inbox' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox, account: channel.account) }

    it 'fails a message with two attachments with the reason and sends nothing' do
      open_window(conversation)
      message = outgoing_message(conversation, files: 2)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload).to be_failed
      expect(message.external_error).to eq(RichMessages::AttachmentLimit::ONE_PER_MESSAGE)
      expect(a_request(:post, 'https://waba.360dialog.io/v1/messages')).not_to have_been_made
    end
  end

  context 'with the WhatsApp Híbrido and the official window closed' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:contact) { create(:contact, account: channel.account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, contact: contact, inbox: channel.inbox, account: channel.account) }

    around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: channel.account_id.to_s) { example.run } }

    it 'fails a message with two attachments with the reason and does not reach the WhatsApp API engine' do
      WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-anexos', status: 'connected',
                                         connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                         status_checked_at: Time.current)
      allow(WhatsappHybrid::WebTransport).to receive(:new)
      message = outgoing_message(conversation, files: 2)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload).to be_failed
      expect(message.external_error).to eq(RichMessages::AttachmentLimit::ONE_PER_MESSAGE)
      expect(WhatsappHybrid::WebTransport).not_to have_received(:new)
    end
  end

  context 'with an Instagram inbox' do
    let(:channel) { create(:channel_instagram) }
    let(:inbox) { create(:inbox, channel: channel, account: channel.account) }
    let(:contact) { create(:contact, account: channel.account) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: 'ig-contato') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, contact: contact, inbox: inbox, account: channel.account) }

    it 'keeps sending every attachment as before' do
      InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').first_or_create(value: false)
      message = outgoing_message(conversation, content: nil, files: 2)
      service = Instagram::SendOnInstagramService.new(message: message)
      allow(service).to receive(:send_message)

      service.perform

      expect(service).to have_received(:send_message).twice
      expect(message.reload.external_error).to be_nil
    end
  end
end
