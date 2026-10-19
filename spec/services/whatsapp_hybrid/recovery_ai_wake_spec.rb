require 'rails_helper'

# chat#1489: depois de recuperar a mensagem, a nossa IA é chamada uma vez só se ninguém falou depois do aviso.
# Mensagens do sistema, atividades, notas, automações e outro robô não contam; o cliente, uma pessoa ou a nossa IA sim.
describe WhatsappHybrid::RecoveryAiWake do
  include_context 'with a pending unsupported hybrid message'

  let(:reply_job) { Autonomia::Agents::Operate::ReplyJob }
  let(:recovered_at) { Time.zone.now.change(usec: 0) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:our_bot) { create(:agent_bot, account: account) }

  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: our_bot) }

  before do
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(agent_inbox)
    message.update_columns(created_at: recovered_at) # rubocop:disable Rails/SkipsModelValidations
  end

  def after_notice(attributes)
    create(:message, { conversation: conversation, account: account, inbox: inbox, content: 'texto' }.merge(attributes))
  end

  def wake
    travel_to(recovered_at + 30.seconds) { described_class.call(message.reload) }
  end

  shared_examples 'calls the AI once' do
    it 'chama a IA uma vez' do
      expect { wake }.to have_enqueued_job(reply_job).with(conversation.id, message.id, 'settle').exactly(:once)
    end
  end

  shared_examples 'does not call the AI' do
    it 'não chama a IA' do
      expect { wake }.not_to have_enqueued_job(reply_job)
    end
  end

  context 'when nobody spoke after the notice' do
    it_behaves_like 'calls the AI once'
  end

  context 'when the out-of-office message went out right after the notice (fora do horário)' do
    before do
      after_notice(message_type: :template, content: 'Estamos fora do horário', content_type: :text,
                   content_attributes: {}, additional_attributes: {})
    end

    it_behaves_like 'calls the AI once'
  end

  context 'when the greeting went out after the notice' do
    before { after_notice(message_type: :template, content: 'Olá! Bem-vindo.') }

    it_behaves_like 'calls the AI once'
  end

  context 'when an activity was recorded after the notice' do
    before { after_notice(message_type: :activity, content: 'Atribuída a Maria') }

    it_behaves_like 'calls the AI once'
  end

  context 'when an automation rule replied (sem remetente)' do
    before do
      create(:message, :bot_message, conversation: conversation, account: account, inbox: inbox, content: 'Recebemos sua mensagem')
    end

    it 'a mensagem da regra não tem remetente' do
      expect(conversation.messages.outgoing.last.sender).to be_nil
    end

    it_behaves_like 'calls the AI once'
  end

  context 'when another bot (n8n/AgentBot que não é a nossa IA) replied to the notice' do
    before { after_notice(message_type: :outgoing, sender: create(:agent_bot, account: account), content: 'Não entendi') }

    it_behaves_like 'calls the AI once'
  end

  context 'when a private note was added' do
    before { after_notice(message_type: :outgoing, private: true, sender: create(:user, account: account)) }

    it_behaves_like 'calls the AI once'
  end

  context 'when a person replied' do
    before { after_notice(message_type: :outgoing, sender: create(:user, account: account), content: 'Oi!') }

    it_behaves_like 'does not call the AI'
  end

  context 'when our AI replied without saying to which message' do
    before { after_notice(message_type: :outgoing, sender: our_bot, content: 'Olá! Em que posso ajudar?') }

    it_behaves_like 'does not call the AI'
  end

  context 'when our AI replied to the recovered message (or a newer one)' do
    before do
      after_notice(message_type: :outgoing, sender: our_bot, content: 'Olá!',
                   content_attributes: { 'autonomia_reply_to_message_id' => message.id })
    end

    it_behaves_like 'does not call the AI'
  end

  context 'when our AI answered an earlier "oi" after the notice (oi → bolha → IA responde ao oi)' do
    # O "oi" chegou antes da bolha (id menor); a resposta da IA a ele saiu depois da bolha.
    let(:oi) do
      create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox, sender: contact,
                       content: 'oi')
    end
    let(:message) do
      oi
      create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox, sender: contact,
                       content: placeholder, source_id: wamid,
                       content_attributes: { 'is_unsupported' => true, 'whatsapp_web_id' => web_id, 'hybrid_recovery' => 'pending' })
    end

    before do
      after_notice(message_type: :outgoing, sender: our_bot, content: 'Olá! Em que posso ajudar?',
                   content_attributes: { 'autonomia_reply_to_message_id' => oi.id })
    end

    it_behaves_like 'calls the AI once'
  end

  context 'when the contact sent another message (A não suportada, B "oi?")' do
    before { after_notice(message_type: :incoming, sender: contact, content: 'oi?') }

    it_behaves_like 'does not call the AI'
  end

  context 'when the contact wrote in another conversation of the same inbox' do
    before do
      other = create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account)
      create(:message, message_type: :incoming, conversation: other, account: account, inbox: inbox, sender: contact,
                       content: 'oi?')
    end

    it_behaves_like 'does not call the AI'
  end

  context 'when the conversation was resolved' do
    before { conversation.update!(status: :resolved) }

    it_behaves_like 'does not call the AI'
  end

  it 'modelo de outra empresa (hsm) chama como qualquer outra' do
    message.update!(content_attributes: message.content_attributes.merge('unsupported_type' => 'hsm'))

    expect { wake }.to have_enqueued_job(reply_job).exactly(:once)
  end

  describe 'limite de 2 minutos' do
    it 'em 2:00 ainda chama' do
      travel_to(recovered_at + 2.minutes) do
        expect { described_class.call(message.reload) }.to have_enqueued_job(reply_job).exactly(:once)
      end
    end

    it 'em 2:01 não chama e registra o motivo (recuperada_tarde)' do
      allow(Autonomia::Agents::Operate::NaoSuportada).to receive(:tarde)

      travel_to(recovered_at + 2.minutes + 1.second) do
        expect { described_class.call(message.reload) }.not_to have_enqueued_job(reply_job)
      end
      expect(Autonomia::Agents::Operate::NaoSuportada).to have_received(:tarde).with(message)
    end

    it 'tarde, mas alguém já respondeu: não registra recuperada_tarde' do
      allow(Autonomia::Agents::Operate::NaoSuportada).to receive(:tarde)
      after_notice(message_type: :outgoing, sender: create(:user, account: account), content: 'Oi!')

      travel_to(recovered_at + 5.minutes) { described_class.call(message.reload) }

      expect(Autonomia::Agents::Operate::NaoSuportada).not_to have_received(:tarde)
    end
  end

  describe 'marca do turno (debounce) não regride' do
    def marca
      conversation.reload.additional_attributes.to_h.dig('autonomia_debounce', 'pending_message_id')
    end

    def marcar!(id)
      conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => id, 'at' => 1.0 } })
    end

    it 'sem marca ou com marca mais velha: grava a marca desta mensagem e agenda o settle' do
      marcar!(message.id - 1)

      expect { wake }.to have_enqueued_job(reply_job).with(conversation.id, message.id, 'settle').exactly(:once)
      expect(marca).to eq(message.id)
    end

    it 'corrida: a marca já aponta para uma mensagem mais nova; não regride e a IA não é acordada de novo' do
      marcar!(message.id + 1000)

      expect { wake }.not_to have_enqueued_job(reply_job)
      expect(marca).to eq(message.id + 1000)
    end

    it 'Agentes desligados na conta: sai antes de gravar a marca e não acorda' do
      allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false)

      expect { wake }.not_to have_enqueued_job(reply_job)
      expect(marca).to be_nil
      expect(Autonomia::Agents::Operate).not_to have_received(:eligible_agent_inbox)
    end

    it 'sem agente que responderia: nem grava a marca' do
      allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(nil)

      expect { wake }.not_to have_enqueued_job(reply_job)
      expect(marca).to be_nil
    end
  end
end
