require 'rails_helper'

RSpec.describe Autonomia::Channels::BroadcastGuard do
  describe '.blocked_conversation?' do
    let(:account) { create(:account) }
    let(:channel_api) { create(:channel_api, account: account) }
    let(:inbox) { channel_api.inbox }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    it 'blocks WAHA status conversations' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => 'status@broadcast' })

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    it 'blocks broadcast destinations from contact inbox source ids' do
      contact_inbox.update!(source_id: 'newsletter@broadcast')

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    it 'blocks status@broadcast in the contact inbox source id' do
      contact_inbox.update!(source_id: 'status@broadcast')

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    it 'blocks the chat id regardless of case and surrounding spaces' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => ' Status@Broadcast ' })

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    # Intencional até o PR do jid (#1324, fora daqui): o guard olha só o chat_id e o source_id. Quando o guard passar a
    # olhar o jid, este exemplo muda junto, com OK do Rodrigo.
    it 'does not block when only the WAHA jid is a broadcast' do
      contact.update!(custom_attributes: { 'waha_whatsapp_jid' => 'status@broadcast' })

      expect(described_class.blocked_conversation?(conversation)).to be false
    end

    it 'blocks by the source id even when the WAHA chat id is direct' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '554299999999@c.us' })
      contact_inbox.update!(source_id: 'status@broadcast')

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    it 'allows a conversation without contact attributes and with a uuid source id' do
      expect(described_class.blocked_conversation?(conversation)).to be false
    end

    it 'allows normal WAHA chat ids' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '554299999999@c.us' })

      expect(described_class.blocked_conversation?(conversation)).to be false
    end
  end
end
