require 'rails_helper'

# chat#1489: a IA não responde ao aviso de "mensagem não suportada", mas nunca em silêncio sem rastro. Falha (ou
# recuperação tarde) com a flag ligada vai para as pessoas — se a conversa não estiver resolvida e não tiver seguido.
describe Autonomia::Agents::Operate::NaoSuportada do
  include_context 'with a pending unsupported hybrid message'

  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:events) { Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id) }
  let(:notes) { conversation.messages.where(private: true) }
  let(:failed_note) { 'O cliente mandou uma mensagem que o WhatsApp oficial não mostra. Veja no celular.' }
  let(:late_note) { 'A mensagem do cliente chegou atrasada e a IA não respondeu. Veja a conversa.' }

  before do
    allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(agent_inbox)
    account.update!(locale: 'pt_BR')
    conversation.update!(status: :open, ai_assignee: agent_bot)
    message
  end

  it 'aviso sem recuperação: só o evento skipped_mensagem_nao_suportada' do
    described_class.ignorada(message)

    expect(events.pluck(:event_type, :handoff_reason)).to eq([%w[skipped_mensagem_nao_suportada mensagem_nao_suportada]])
    expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
  end

  describe 'falhou (flag ligada)' do
    it 'com o espelho no comando (open, ai_assignee): evento, passa para as pessoas com o motivo e a nota' do
      allow(Crm::Entrega).to receive(:new).and_call_original

      described_class.falhou(message)

      expect(events.pluck(:event_type)).to contain_exactly('skipped_recuperacao_falhou', 'handed_off')
      expect(events.handed_off.last.handoff_reason).to eq('recuperacao_falhou')
      expect(conversation.reload.bot_handoff_waiting?).to be(true)
      expect(Crm::Entrega).to have_received(:new).with(hash_including(motivo: 'recuperacao_falhou'))
      expect(notes.last).to have_attributes(content: failed_note, message_type: 'outgoing', sender_type: 'AgentBot',
                                            sender_id: agent_bot.id)
    end

    it 'conversa pendente (sem atribuição): também passa' do
      conversation.update!(status: :pending, ai_assignee: nil)

      described_class.falhou(message)

      expect(events.handed_off.count).to eq(1)
      expect(conversation.reload.status).to eq('open')
    end

    it 'conversa resolvida: só o evento, não reabre nem deixa nota' do
      conversation.update!(status: :resolved)

      described_class.falhou(message)

      expect(events.pluck(:event_type)).to eq(%w[skipped_recuperacao_falhou])
      expect(conversation.reload.status).to eq('resolved')
      expect(notes).to be_empty
    end

    it 'alguém falou depois do aviso: evento e nota, sem passar (a conversa já seguiu)' do
      create(:message, message_type: :outgoing, conversation: conversation, account: account, inbox: inbox,
                       sender: create(:user, account: account), content: 'Oi! Posso ajudar?')

      described_class.falhou(message)

      expect(events.pluck(:event_type)).to eq(%w[skipped_recuperacao_falhou])
      expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
      expect(notes.last.content).to eq(failed_note)
    end

    it 'o cliente mandou outra depois: evento e nota, sem passar' do
      create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox, sender: contact,
                       content: 'oi?')

      described_class.falhou(message)

      expect(events.handed_off).to be_empty
      expect(notes.count).to eq(1)
    end

    it 'nota em inglês na conta em inglês' do
      account.update!(locale: 'en')

      described_class.falhou(message)

      expect(notes.last.content).to eq('The customer sent a message the official WhatsApp does not show. Check it on the phone.')
    end
  end

  it 'falhou com a flag desligada: só o evento, ninguém muda de rota' do
    account.disable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE)

    described_class.falhou(message)

    expect(events.pluck(:event_type)).to eq(%w[skipped_recuperacao_falhou])
    expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
    expect(notes).to be_empty
  end

  describe 'tarde' do
    it 'com a flag: evento, passa para as pessoas com o motivo recuperacao_tarde e a nota própria' do
      allow(Crm::Entrega).to receive(:new).and_call_original

      described_class.tarde(message)

      expect(events.pluck(:event_type)).to contain_exactly('skipped_recuperada_tarde', 'handed_off')
      expect(events.handed_off.last.handoff_reason).to eq('recuperada_tarde')
      expect(Crm::Entrega).to have_received(:new).with(hash_including(motivo: 'recuperacao_tarde'))
      expect(notes.last.content).to eq(late_note)
    end

    it 'conversa resolvida: só o evento' do
      conversation.update!(status: :resolved)

      described_class.tarde(message)

      expect(events.pluck(:event_type)).to eq(%w[skipped_recuperada_tarde])
      expect(notes).to be_empty
    end

    it 'sem a flag: só o evento' do
      account.disable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE)

      described_class.tarde(message)

      expect(events.pluck(:event_type)).to eq(%w[skipped_recuperada_tarde])
      expect(notes).to be_empty
    end
  end

  it 'falha ao acordar a IA: evento skipped_recuperacao_acordar_falhou' do
    described_class.acordar_falhou(message)

    expect(events.pluck(:event_type, :handoff_reason)).to eq([%w[skipped_recuperacao_acordar_falhou recuperacao_acordar_falhou]])
  end

  it 'sem agente que responderia a conversa: nada a registrar' do
    allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(nil)

    described_class.falhou(message)

    expect(events).to be_empty
    expect(notes).to be_empty
  end

  it 'erro de banco não sobe: vai ao tracker' do
    allow(Autonomia::Agents::Operate::EventLogger).to receive(:skipped).and_raise(ActiveRecord::StatementInvalid, 'x')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    expect { described_class.falhou(message) }.not_to raise_error
    expect(tracker).to have_received(:capture_exception)
  end
end
