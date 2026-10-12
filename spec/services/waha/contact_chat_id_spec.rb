require 'rails_helper'

RSpec.describe Waha::ContactChatId do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:custom_attributes) { {} }
  let(:contact) { create(:contact, account: account, custom_attributes: custom_attributes) }
  let(:source_id) { 'uuid-da-caixa' }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id) }
  let(:all_three) do
    { 'waha_whatsapp_chat_id' => '554299999999@c.us', 'waha_whatsapp_jid' => '554288888888@c.us', 'waha_whatsapp_lid' => '123@lid' }
  end

  describe '.candidates' do
    context 'with chat_id, jid and source_id present' do
      let(:custom_attributes) { all_three }

      it 'returns them in the order chat_id, jid, source_id, without the lid' do
        expect(described_class.candidates(contact, contact_inbox: contact_inbox))
          .to eq(['554299999999@c.us', '554288888888@c.us', 'uuid-da-caixa'])
      end
    end

    context 'with blank strings' do
      let(:custom_attributes) { { 'waha_whatsapp_chat_id' => '  ', 'waha_whatsapp_jid' => '' } }
      let(:source_id) { '120363000000000000@g.us' }

      it 'skips them' do
        expect(described_class.candidates(contact, contact_inbox: contact_inbox)).to eq(['120363000000000000@g.us'])
      end
    end

    context 'with only the jid' do
      let(:custom_attributes) { { 'waha_whatsapp_jid' => '120363000000000000@G.US ' } }

      it 'returns the raw value, without normalizing it' do
        expect(described_class.candidates(contact)).to eq(['120363000000000000@G.US '])
      end
    end

    it 'is empty for a contact without attributes and without contact_inbox' do
      expect(described_class.candidates(contact)).to eq([])
    end

    it 'is empty without a contact' do
      expect(described_class.candidates(nil)).to eq([])
    end

    it 'reads the source_id even without a contact' do
      expect(described_class.candidates(nil, contact_inbox: contact_inbox)).to eq(['uuid-da-caixa'])
    end
  end

  describe '.primary' do
    context 'with all present' do
      let(:custom_attributes) { all_three }

      it 'is the chat_id' do
        expect(described_class.primary(contact, contact_inbox: contact_inbox)).to eq('554299999999@c.us')
      end
    end

    context 'without the chat_id' do
      let(:custom_attributes) { all_three.except('waha_whatsapp_chat_id') }

      it 'is the jid' do
        expect(described_class.primary(contact, contact_inbox: contact_inbox)).to eq('554288888888@c.us')
      end
    end

    context 'with only the lid on the contact' do
      let(:custom_attributes) { { 'waha_whatsapp_lid' => '123@lid' } }

      it 'falls back to the source_id' do
        expect(described_class.primary(contact, contact_inbox: contact_inbox)).to eq('uuid-da-caixa')
      end
    end

    it 'is nil with nothing present' do
      expect(described_class.primary(contact)).to be_nil
    end
  end

  describe '.values' do
    let(:custom_attributes) { all_three }

    it 'returns only the requested sources, in the requested order' do
      expect(described_class.values(contact, :source_id, :chat_id, contact_inbox: contact_inbox))
        .to eq(['uuid-da-caixa', '554299999999@c.us'])
    end

    it 'rejects an unknown source' do
      expect { described_class.values(contact, :lid) }.to raise_error(ArgumentError)
    end
  end

  describe '.store!' do
    let(:custom_attributes) { { 'origem' => 'site', 'waha_whatsapp_lid' => '123@lid' } }

    it 'stores a @c.us chat id as chat_id and jid, keeping the other attributes' do
      described_class.store!(contact, '554299999999@c.us')

      expect(contact.reload.custom_attributes).to eq(
        'origem' => 'site', 'waha_whatsapp_lid' => '123@lid',
        'waha_whatsapp_chat_id' => '554299999999@c.us', 'waha_whatsapp_jid' => '554299999999@c.us'
      )
    end

    context 'with a @lid chat id' do
      let(:custom_attributes) { { 'origem' => 'site', 'waha_whatsapp_jid' => '554299999999@c.us' } }

      it 'stores it as chat_id and lid, keeping the jid' do
        described_class.store!(contact, '987@lid')

        expect(contact.reload.custom_attributes).to eq(
          'origem' => 'site', 'waha_whatsapp_jid' => '554299999999@c.us',
          'waha_whatsapp_chat_id' => '987@lid', 'waha_whatsapp_lid' => '987@lid'
        )
      end
    end

    it 'does not touch the contact when nothing changes' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '554299999999@c.us', 'waha_whatsapp_jid' => '554299999999@c.us' })

      expect { described_class.store!(contact, '554299999999@c.us') }.not_to(change { contact.reload.updated_at })
    end

    it 'only assigns the attributes on a new contact, for the caller to save' do
      new_contact = build(:contact, account: account, custom_attributes: { 'origem' => 'site' })

      described_class.store!(new_contact, '554299999999@c.us')

      expect(new_contact).to be_new_record
      expect(new_contact.custom_attributes).to eq(
        'origem' => 'site', 'waha_whatsapp_chat_id' => '554299999999@c.us', 'waha_whatsapp_jid' => '554299999999@c.us'
      )
    end
  end
end
