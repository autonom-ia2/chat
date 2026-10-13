require 'rails_helper'

# Pessoa respondendo numa conversa à espera de pessoa fica com ela (#1499, decisão do Rodrigo em 13/10, opção b).
RSpec.describe 'Pessoa respondendo conversa à espera' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, status: :open).reload.tap do |conv|
      conv.update!(ai_assignee: bot, assignee: nil)
    end
  end

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  def reply(sender: ana, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: sender,
                     content: 'Oi, sou a Ana', **attrs)
  end

  # Pega o caso do Agentes IA: a Ana responde, e a fila do motor entregaria a conversa ao João em até 2 minutos.
  it 'conversa à espera de pessoa: quem respondeu fica com ela, o robô sai e as marcas de espera também', :aggregate_failures do
    conversation.bot_handoff!
    expect(conversation.reload.bot_handoff_waiting?).to be(true)

    reply

    conversation.reload
    expect(conversation).to have_attributes(assignee_id: ana.id, ai_assignee: nil, status: 'open')
    expect(conversation.bot_handoff_waiting?).to be(false)
    expect(conversation.crm_delivery_pending?).to be(false)
    expect(Conversation.awaiting_person).not_to include(conversation)
  end

  it 'nota privada não faz ninguém ficar com a conversa' do
    conversation.bot_handoff!

    reply(private: true)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
    expect(conversation.bot_handoff_waiting?).to be(true)
  end

  # A decisão de 13/10 (atendente responde não assume) continua: sem passagem, o robô segue atendendo.
  it 'robô ainda atendendo (sem marca de espera): a resposta da pessoa não tira o robô' do
    reply

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  it 'resposta de robô, de automação ou de campanha não conta como pessoa', :aggregate_failures do
    conversation.bot_handoff!

    reply(sender: bot)
    reply(content_attributes: { 'automation_rule_id' => 1 })
    reply(additional_attributes: { 'campaign_id' => 7 })

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
    expect(conversation.bot_handoff_waiting?).to be(true)
  end

  it 'com uma pessoa já no nome, quem responde não toma a conversa dela' do
    joao = create(:user, account: account, role: :agent)
    conversation.update!(assignee: joao)

    reply

    expect(conversation.reload.assignee_id).to eq(joao.id)
  end

  it 'se ficar com a conversa falhar, a mensagem segue gravada e o erro só é registrado', :aggregate_failures do
    conversation.bot_handoff!
    allow(Conversation).to receive(:lock).and_raise(ActiveRecord::LockWaitTimeout)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    message = reply

    expect(message).to be_persisted
    expect(tracker).to have_received(:capture_exception)
  end
end
