require 'rails_helper'
require_relative '../inbound_context'

# chat#1709 (decisão do Rodrigo, 16/10/2026): a visualização única que o aparelho vinculado não abre vira o aviso do
# WhatsApp Web; se a mídia chegar depois, o aviso sai e a mídia fica marcada.
describe Waha::RichNative::Inbound::ViewOnceUnavailable do
  include_context 'with a waha inbox and its connector'

  let(:aviso) { I18n.t('waha.view_once_unavailable', locale: 'pt_BR') }
  let(:jpg) { { filename: 'f.jpg', content_type: 'image/jpeg', file_type: :image } }

  def notice(extra = {})
    from_connector({ waha_view_once_unavailable: { from_me: false, id: 'false_5511999998888@c.us_VO1' } }.merge(extra),
                   content: 'aviso do conector')
  end

  describe 'with the flag' do
    before { flag_on! }

    it 'shows the notice as a customer message with view_once_unavailable and the i18n text' do
      message = notice

      expect(message).to be_incoming
      expect(message.private).to be(false)
      expect(message.sender).to eq(conversation.contact)
      expect(message.content).to eq(aviso)
      expect(message.content_attributes).to include('view_once_unavailable' => true, 'view_once_id' => 'false_5511999998888@c.us_VO1')
      expect(message.content_attributes).not_to have_key('waha_view_once_unavailable')
    end

    # Contrato do conector 3c: a mídia vem com `waha_media.view_once` e o id do aviso no Chatwoot.
    it 'hides the notice found by notice_message_id and marks the media when the real media arrives later' do
      aviso_message = notice
      media = from_connector({ waha_media: { kind: 'image', view_once: true },
                               waha_view_once_resolved: { id: 'false_5511999998888@c.us_VO1', notice_message_id: aviso_message.id } },
                             content: nil, attachments: [jpg])

      expect(media.attachments.first.meta).to include('is_view_once' => true)
      expect(media.content_attributes).not_to have_key('waha_view_once_resolved')
      expect(aviso_message.reload.content_attributes).to include('c2y_hidden' => true, 'view_once_resolved_by' => media.id)
    end

    it 'falls back to the notice id without notice_message_id, and never hides a message that is not the notice' do
      aviso_message = notice
      other = from_connector({}, content: 'texto do cliente')
      by_id = from_connector({ waha_view_once_resolved: { id: 'false_5511999998888@c.us_VO1' } }, content: nil, attachments: [jpg])
      from_connector({ waha_view_once_resolved: { id: 'x', notice_message_id: other.id } }, content: nil, attachments: [jpg])

      expect(aviso_message.reload.content_attributes).to include('c2y_hidden' => true, 'view_once_resolved_by' => by_id.id)
      expect(other.reload.content_attributes).not_to have_key('c2y_hidden')
    end

    # O conector 4: a mídia pode chegar noutra conversa (a do aviso resolvida). Mesma caixa e mesmo contato: o aviso sai.
    it 'finds the notice by notice_message_id in another conversation of the same inbox and contact' do
      aviso_message = notice
      conversation.update!(status: :resolved)
      nova = create(:conversation, inbox: inbox, account: account, contact: conversation.contact)
      media = from_connector({ waha_view_once_resolved: { id: 'x', notice_message_id: aviso_message.id } },
                             content: nil, attachments: [jpg], target_conversation: nova)

      expect(aviso_message.reload.content_attributes).to include('c2y_hidden' => true, 'view_once_resolved_by' => media.id)
    end

    it 'never hides the notice of another contact (forged notice_message_id)' do
      outra = create(:conversation, inbox: inbox, account: account)
      aviso_alheio = from_connector({ waha_view_once_unavailable: { from_me: false, id: 'VO2' } }, target_conversation: outra)
      from_connector({ waha_view_once_resolved: { id: 'x', notice_message_id: aviso_alheio.id } }, content: nil, attachments: [jpg])

      expect(aviso_alheio.reload.content_attributes).not_to have_key('c2y_hidden')
    end

    it 'keeps the media and touches nothing else when there is no matching notice' do
      other = notice
      media = from_connector({ waha_view_once_resolved: { id: 'OUTRO' } }, content: nil, attachments: [jpg])

      expect(media.attachments.first.meta).to include('is_view_once' => true)
      expect(other.reload.content_attributes).not_to have_key('c2y_hidden')
    end

    it 'does not take the key from someone other than the connector' do
      message = from_connector({ waha_view_once_unavailable: { from_me: false, id: 'VO1' } }, user: agent, content: 'texto')

      expect(message.content).to eq('texto')
      expect(message.content_attributes.keys & %w[view_once_unavailable waha_view_once_unavailable]).to eq([])
    end
  end

  it 'turns the notice into a hidden activity without the flag (main never receives it)' do
    message = notice

    expect(message).to be_activity
    expect(message.content_attributes).to include('c2y_hidden' => true)
    expect(message.content_attributes).not_to have_key('view_once_unavailable')
  end
end
