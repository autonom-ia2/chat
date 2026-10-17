require 'rails_helper'

# #1691 caso 2: agente da plataforma em "Só no horário", fora do horário. A IA fica calada de propósito; o aviso ao
# cliente é a mensagem de fora do horário da PRÓPRIA caixa (Chatwoot), configurada pelo dono. Prova que ela sai com o
# nosso agente na caixa: vínculo porta, espelho AgentBot com AgentBotInbox ativo, conversa com o robô no nome (pendente,
# legado, ou aberta, desde o #1377). Nada dublado: a mensagem do cliente passa pelo callback real
# (Message#execute_message_template_hooks), com o override do Enterprise carregado.
RSpec.describe MessageTemplates::HookExecutionService do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo') }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.',
                                     config: { 'with_knowledge' => false, 'response_window' => 'business_hours' })
  end
  let(:aviso) { 'Estamos fora do horário. Voltamos amanhã às 9h.' }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
    inbox.update!(working_hours_enabled: true, out_of_office_message: aviso)
  end

  # Quinta-feira, 22h em São Paulo: a caixa (seg a sex, 9h às 17h) está fechada.
  around { |example| travel_to(Time.find_zone('America/Sao_Paulo').local(2026, 10, 15, 22, 0)) { example.run } }

  def cliente_escreve(conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')
  end

  def avisos(conversation)
    conversation.messages.where(message_type: :template).pluck(:content)
  end

  it 'a caixa está fora do horário e o agente, em "Só no horário", não atende agora' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :pending, assignee: nil)

    expect(inbox.out_of_office?).to be(true)
    expect(Autonomia::Agents::Operate::EngagementGate.new(agent: agent, conversation: conversation).blocked_reason).to eq('schedule')
  end

  it 'conversa pendente com o robô da caixa: a mensagem de fora do horário sai' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :pending, assignee: nil)

    cliente_escreve(conversation)

    expect(avisos(conversation)).to eq([aviso])
  end

  it 'conversa aberta com o robô no nome (#1377): a mensagem de fora do horário sai' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :open, assignee: nil)
    conversation.update!(ai_assignee: agent_bot)

    cliente_escreve(conversation)

    expect(avisos(conversation)).to eq([aviso])
  end

  it 'sai uma vez por dia, como no Chatwoot' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :pending, assignee: nil)

    cliente_escreve(conversation)
    cliente_escreve(conversation)

    expect(avisos(conversation)).to eq([aviso])
  end
end
