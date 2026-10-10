require 'rails_helper'

RSpec.describe Crm::Subjects::Notifier do
  let(:account) { create_account_and_user.first }
  let(:admin) { account.users.first }
  let(:member) { create_crm_agent(account: account, name: 'Da caixa').first }
  let(:outsider) { create_crm_agent(account: account, name: 'Fora da caixa').first }
  let(:inbox) { create_crm_inbox(account: account, members: [member]) }
  let(:contact) { account.contacts.create!(name: 'Joana', phone_number: '+5511987654321') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  it 'avisa membros da caixa e administradores, só com a conta e o número da conversa' do
    allow(ActionCable.server).to receive(:broadcast)
    outsider

    described_class.notify(conversation)

    expected = { event: 'crm.subjects.changed', data: { account_id: account.id, conversation_id: conversation.display_id } }
    expect(ActionCable.server).to have_received(:broadcast).with(member.pubsub_token, expected)
    expect(ActionCable.server).to have_received(:broadcast).with(admin.pubsub_token, expected)
    expect(ActionCable.server).not_to have_received(:broadcast).with(outsider.pubsub_token, anything)
  end

  it 'falha no aviso não derruba quem chamou' do
    allow(ActionCable.server).to receive(:broadcast).and_raise(Redis::CannotConnectError)

    expect(described_class.notify(conversation)).to be_nil
  end
end
