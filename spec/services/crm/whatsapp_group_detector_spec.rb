require 'rails_helper'

RSpec.describe Crm::WhatsappGroupDetector do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:custom_attributes) { {} }
  let(:source_id) { SecureRandom.uuid }
  let(:contact) { create(:contact, account: account, custom_attributes: custom_attributes) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  describe '.group_conversation?' do
    # WAHA's Chatwoot app creates the contact through the public inbox API
    # without a source_id, so the contact_inbox gets a random uuid.
    context 'when the WAHA chat id on the contact is a group' do
      let(:custom_attributes) { { 'waha_whatsapp_chat_id' => '120363000000000000@g.us' } }

      it 'detects the group even though the source_id is a uuid' do
        expect(described_class.group_conversation?(conversation)).to be(true)
      end
    end

    context 'when only the WAHA jid attribute carries the group id' do
      let(:custom_attributes) { { 'waha_whatsapp_jid' => '120363000000000000@G.US ' } }

      it 'detects the group' do
        expect(described_class.group_conversation?(conversation)).to be(true)
      end
    end

    context 'when the WAHA chat id is a broadcast or a channel' do
      it 'treats both as non direct' do
        %w[status@broadcast 120363000000000000@newsletter].each do |chat_id|
          contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => chat_id })

          expect(described_class.group_conversation?(conversation.reload)).to be(true)
        end
      end
    end

    context 'when the WAHA chat id is a direct chat' do
      let(:custom_attributes) { { 'waha_whatsapp_chat_id' => '554299999999@c.us', 'waha_whatsapp_lid' => '1234567890@lid' } }

      it 'is not a group' do
        expect(described_class.group_conversation?(conversation)).to be(false)
      end
    end

    context 'when the WAHA chat id is direct but the source_id looks like a group' do
      let(:custom_attributes) { { 'waha_whatsapp_chat_id' => '554299999999@c.us' } }
      let(:source_id) { '120363000000000000@g.us' }

      it 'trusts the WAHA chat id over the fallback' do
        expect(described_class.group_conversation?(conversation)).to be(false)
      end
    end

    context 'when the contact has no WAHA attributes' do
      it 'is not a group for a uuid source_id' do
        expect(described_class.group_conversation?(conversation)).to be(false)
      end

      context 'with a group JID in the source_id' do
        let(:source_id) { '120363000000000000@g.us' }

        it 'falls back to the source_id' do
          expect(described_class.group_conversation?(conversation)).to be(true)
        end
      end
    end

    context 'when the inbox is not a WhatsApp-capable channel' do
      let(:inbox) { create(:inbox, account: account) }
      let(:custom_attributes) { { 'waha_whatsapp_chat_id' => '120363000000000000@g.us' } }

      it 'is not a group' do
        expect(described_class.group_conversation?(conversation)).to be(false)
      end
    end

    it 'is not a group without a conversation' do
      expect(described_class.group_conversation?(nil)).to be(false)
    end
  end
end
