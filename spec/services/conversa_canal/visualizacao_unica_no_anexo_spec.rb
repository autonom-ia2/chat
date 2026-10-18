require 'rails_helper'

# #1702: mensagem de visualização única. Quando o provedor entrega a mídia, ela fica guardada e visível, com a marca
# `meta.is_view_once` no anexo (decisão do Rodrigo, 16/10). Quem grava a marca na caixa WAHA é o #1709; aqui, a marca
# sai para a tela e os webhooks, e a Cloud API (que não entrega nem diz que era visualização única) segue genérica.
describe ConversaCanal::VisualizacaoUnicaNoAnexo do
  let(:message) { create(:message) }

  before { message.account.enable_features!('conversa_cara_do_canal') }

  def anexo(meta)
    message.attachments.create!(account_id: message.account_id, file_type: :image, meta: meta,
                                file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
  end

  it 'sends the mark with the attachment to the dashboard and the webhooks' do
    anexo('is_view_once' => true)

    expect(message.attachments.sole.push_event_data[:is_view_once]).to be(true)
    expect(message.reload.webhook_data[:attachments].sole[:is_view_once]).to be(true)
  end

  it 'keeps the media itself available' do
    data = anexo('is_view_once' => true).push_event_data

    expect(data[:data_url]).to be_present
    expect(data[:file_type]).to eq('image')
  end

  it 'leaves a regular photo without the key' do
    expect(anexo({}).push_event_data).not_to have_key(:is_view_once)
  end

  it 'with the skin off, the attachment goes out as on main (the mark comes from #1709, not from the skin)' do
    message.account.disable_features!('conversa_cara_do_canal')

    expect(anexo('is_view_once' => true).push_event_data).not_to have_key(:is_view_once)
  end

  it 'ignores a mark that is not exactly true' do
    expect(anexo('is_view_once' => 'true').push_event_data).not_to have_key(:is_view_once)
  end

  context 'with the Cloud API' do
    after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

    it 'keeps the generic unsupported notice, since Meta does not say it was view once' do
      params = {
        phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: '5511900000001' }],
          messages: [{ from: '5511900000001', id: 'wamid.unsupported', timestamp: '1760371920', type: 'unsupported',
                       errors: [{ code: 131_051, title: 'Message type unknown' }], unsupported: { type: 'image' } }]
        } }] }]
      }.with_indifferent_access

      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
      received = Message.find_by!(source_id: 'wamid.unsupported')

      expect(received.content).to eq(I18n.t('conversations.messages.whatsapp.unsupported_message'))
      expect(received.content_attributes['is_unsupported']).to be(true)
      expect(received.attachments).to be_empty
    end
  end
end
