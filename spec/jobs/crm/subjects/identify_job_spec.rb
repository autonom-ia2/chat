require 'rails_helper'

RSpec.describe Crm::Subjects::IdentifyJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:identifier) { instance_double(Crm::Subjects::Identifier, perform: nil) }

  def incoming(content)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Subjects::Identifier).to receive(:new).and_return(identifier)
  end

  it 'pergunta pela última mensagem recebida' do
    message = incoming('Quero agentes de IA')

    described_class.perform_now(conversation.id, message.id)

    expect(Crm::Subjects::Identifier).to have_received(:new).with(conversation: conversation, message: message)
  end

  it 'deixa para o job da mensagem seguinte quando o cliente mandou outra na espera' do
    first = incoming('Oi')
    incoming('Quero agentes de IA')

    described_class.perform_now(conversation.id, first.id)

    expect(Crm::Subjects::Identifier).not_to have_received(:new)
  end

  it 'uma resposta da equipe na espera não impede a pergunta' do
    message = incoming('Quero agentes de IA')
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, content: 'Claro!')

    described_class.perform_now(conversation.id, message.id)

    expect(identifier).to have_received(:perform)
  end
end
