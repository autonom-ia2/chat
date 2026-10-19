require 'rails_helper'
require_relative '../../whatsapp_hybrid/rich_native_context'

# chat#1709: `whatsapp_api_group`, a conversa de grupo na caixa WAHA comum ou na híbrida (o painel não junta no álbum a
# foto de outro participante). Fonte única: Waha::RichNative.group_conversation?.
describe Waha::RichNative, '.api_group?' do
  def group_contact(account)
    create(:contact, account: account, identifier: '120363000000000000@g.us')
  end

  context 'with a WAHA inbox' do
    let(:inbox) { create(:channel_api, additional_attributes: { 'provider' => 'waha', 'session' => 's1' }).inbox }
    let(:account) { inbox.account }
    let(:group) { create(:conversation, inbox: inbox, account: account, contact: group_contact(account)) }

    it 'is true for a group and false for a person' do
      expect(described_class.api_group?(group)).to be(true)
      expect(described_class.api_group?(create(:conversation, inbox: inbox, account: account))).to be(false)
    end

    it 'goes to the panel: conversation event and conversation JSON' do
      expect(Conversations::EventDataPresenter.new(group).push_data[:whatsapp_api_group]).to be(true)

      json = JSON.parse(ApplicationController.render(partial: 'api/v1/conversations/partials/conversation',
                                                     locals: { conversation: group }, formats: [:json]))
      expect(json['whatsapp_api_group']).to be(true)
    end
  end

  context 'with a hybrid inbox' do
    include_context 'with a hybrid inbox for rich native'

    it 'is true for a group conversation' do
      group = create(:conversation, inbox: inbox, account: account, contact: group_contact(account))

      expect(described_class.api_group?(group)).to be(true)
      expect(described_class.api_group?(conversation)).to be(false)
    end
  end

  it 'is false in any other inbox, even with a group identifier' do
    inbox = create(:inbox)
    conversation = create(:conversation, inbox: inbox, account: inbox.account, contact: group_contact(inbox.account))

    expect(described_class.api_group?(conversation)).to be(false)
  end
end
