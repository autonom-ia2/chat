require 'rails_helper'

# chat#1489: a IA não responde ao aviso de "mensagem não suportada", mas nunca em silêncio sem rastro. Falha da
# recuperação com a flag ligada passa a conversa para as pessoas com uma nota; com a flag desligada, só o evento.
describe Autonomia::Agents::Operate::NaoSuportada do
  include_context 'with a pending unsupported hybrid message'

  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:events) { Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id) }
  let(:note_pt) { 'O cliente mandou uma mensagem que o WhatsApp oficial não mostra. Veja no celular.' }

  before do
    allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(agent_inbox)
    conversation.update!(status: :pending)
    account.update!(locale: 'pt_BR')
  end

  it 'aviso sem recuperação: evento skipped_mensagem_nao_suportada, ninguém muda de rota' do
    described_class.ignorada(message)

    expect(events.pluck(:event_type, :handoff_reason)).to eq([%w[skipped_mensagem_nao_suportada mensagem_nao_suportada]])
    expect(conversation.reload.status).to eq('pending')
  end

  it 'recuperada tarde: evento skipped_recuperada_tarde' do
    described_class.tarde(message)

    expect(events.pluck(:event_type)).to eq(%w[skipped_recuperada_tarde])
  end

  it 'falha com a flag ligada: evento, passa para as pessoas e deixa a nota privada' do
    described_class.falhou(message)

    expect(events.pluck(:event_type)).to contain_exactly('skipped_recuperacao_falhou', 'handed_off')
    expect(events.handed_off.last.handoff_reason).to eq('recuperacao_falhou')
    expect(conversation.reload).to have_attributes(status: 'open', ai_assignee_type: nil)
    note = conversation.messages.where(private: true).last
    expect(note).to have_attributes(content: note_pt, message_type: 'outgoing', sender_type: 'AgentBot', sender_id: agent_bot.id)
  end

  it 'falha com a flag desligada: só o evento, sem passar para as pessoas e sem nota' do
    account.disable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE)

    described_class.falhou(message)

    expect(events.pluck(:event_type)).to eq(%w[skipped_recuperacao_falhou])
    expect(conversation.reload.status).to eq('pending')
    expect(conversation.messages.where(private: true)).to be_empty
  end

  it 'sem agente que responderia a conversa: nada a registrar' do
    allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(nil)

    described_class.falhou(message)

    expect(events).to be_empty
    expect(conversation.messages.where(private: true)).to be_empty
  end

  it 'nota em inglês na conta em inglês' do
    account.update!(locale: 'en')

    described_class.falhou(message)

    expect(conversation.messages.where(private: true).last.content)
      .to eq('The customer sent a message the official WhatsApp does not show. Check it on the phone.')
  end
end
