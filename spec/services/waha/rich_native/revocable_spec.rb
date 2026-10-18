require 'rails_helper'
require_relative '../../whatsapp_hybrid/rich_native_context'

# chat#1709: `c2y_revocable`, o sinal do "Apagar para todos" no painel.
describe Waha::RichNative::Revocable do
  def message_in(inbox, conversation, **attrs)
    create(:message, { message_type: :outgoing, content: 'oi', conversation: conversation, account: inbox.account, inbox: inbox }.merge(attrs))
  end

  context 'with a WAHA inbox (o conector apaga quando a mensagem fica deleted)' do
    let(:inbox) { create(:channel_api, additional_attributes: { 'provider' => 'waha', 'session' => 's1' }).inbox }
    let(:conversation) { create(:conversation, inbox: inbox, account: inbox.account) }

    before { inbox.account.enable_features!(Waha::RichNative::FLAG) }

    it 'is true for our public message only with the flag (without it, false: the menu keeps the texts of today)' do
      message = message_in(inbox, conversation)

      expect(described_class.for(message)).to be(true)
      inbox.account.disable_features!(Waha::RichNative::FLAG)
      expect(described_class.for(message.reload)).to be(false)
    end

    it 'is false for a failed message (it never reached the customer)' do
      expect(described_class.for(message_in(inbox, conversation, status: :failed))).to be(false)
    end

    it 'is false for a note and for a customer message' do
      expect(described_class.for(message_in(inbox, conversation, private: true))).to be(false)
      expect(described_class.for(message_in(inbox, conversation, message_type: :incoming))).to be(false)
    end

    it 'goes to the panel: API JSON and the screen event' do
      message = message_in(inbox, conversation)

      json = JSON.parse(ApplicationController.render(partial: 'api/v1/models/message', locals: { message: message }, formats: [:json]))
      expect(json['c2y_revocable']).to be(true)
      expect(message.push_event_data[:c2y_revocable]).to be(true)
    end
  end

  context 'with a hybrid inbox (RevokeOnDelete pede ao motor pelo id físico)' do
    include_context 'with a hybrid inbox for rich native'

    it 'is true only with the flag and a physical id of the engine' do
      sent = message_in(inbox, conversation, source_id: '3EB0SENT')
      expect(described_class.for(sent)).to be(false)

      flag_on!
      expect(described_class.for(sent)).to be(true)
      expect(described_class.for(message_in(inbox, conversation, source_id: nil))).to be(false)
      expect(described_class.for(message_in(inbox, conversation, source_id: '3EB0NOTE', private: true))).to be(false)
      expect(described_class.for(message_in(inbox, conversation, source_id: '3EB0FAIL', status: :failed))).to be(false)
    end
  end

  it 'is false in any other inbox' do
    inbox = create(:inbox)
    conversation = create(:conversation, inbox: inbox, account: inbox.account)

    expect(described_class.for(message_in(inbox, conversation))).to be(false)
  end
end
