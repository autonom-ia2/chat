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

  before do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: our_bot)
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
      expect { wake }.to have_enqueued_job(reply_job).with(conversation.id, message.id).exactly(:once)
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

  context 'when our AI replied' do
    before { after_notice(message_type: :outgoing, sender: our_bot, content: 'Olá! Em que posso ajudar?') }

    it_behaves_like 'does not call the AI'
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

    it 'em 2:01 não chama' do
      travel_to(recovered_at + 2.minutes + 1.second) do
        expect { described_class.call(message.reload) }.not_to have_enqueued_job(reply_job)
      end
    end
  end
end
