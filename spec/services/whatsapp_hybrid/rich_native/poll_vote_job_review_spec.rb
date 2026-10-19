require 'rails_helper'
require_relative '../rich_native_context'

RSpec::Matchers.define_negated_matcher :not_include, :include unless RSpec::Matchers.method_defined?(:not_include)

# chat#1709 (fase 3, revisão): o voto do plano B não abre a janela da Cloud, é achado depois de o registro do ack
# expirar e não vira bolha "não suportada" quando a Meta o entrega à Cloud; apagar pede ao motor uma vez só, e o erro do
# motor não leva telefone ao rastreador.
describe WhatsappHybrid::RichNative::PollVoteJob do
  include_context 'with a hybrid inbox for rich native'

  let(:poll) { { type: 'poll', options: [{ id: 'sim', title: 'Sim' }, { id: 'nao', title: 'Não' }] } }
  let(:poll_id) { 'true_5511937016094@c.us_3EB0AAAA' }

  def native_poll
    flag_on!
    allow(client).to receive(:send_poll).and_return({})
    message = outgoing(poll, content: 'Vem amanhã?')
    send_by_web(message)
    message.reload
  end

  def vote(options, vote_id: 'V1')
    described_class.perform_now(connection.id, { 'poll_id' => poll_id, 'options' => options, 'vote_id' => vote_id, 'from_me' => false })
  end

  describe 'the 24 h window of the Cloud' do
    it 'does not count the vote as the customer opening the window' do
      poll_message = native_poll
      vote(['Sim'])

      record = conversation.messages.incoming.sole
      expect(record.additional_attributes).to include('c2y_window_neutral' => true)
      expect(record.content_attributes).to include('c2y_hidden' => true, 'poll_vote_applied_to' => poll_message.id)
      expect(poll_message.reload.content_attributes['poll_votes'].sole).to include('sender_type' => 'Contact', 'options' => ['Sim'])
      expect(Conversations::MessageWindowService.new(conversation.reload).can_reply?).to be(false)
      expect(WhatsappHybrid::Router.new(conversation).cloud_window_open?).to be(false)
    end

    it 'still opens the window with a real customer message, and leaves other inboxes alone' do
      native_poll
      vote(['Sim'])
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, account: account, inbox: inbox, sender: contact)

      expect(Conversations::MessageWindowService.new(conversation.reload).can_reply?).to be(true)
    end
  end

  it 'finds the poll after the ack record expired (7 days)' do
    poll_message = native_poll
    allow(WhatsappHybrid::WebTransport).to receive(:message_for).and_return(nil)

    vote(['Não'], vote_id: 'V9')

    expect(poll_message.reload.content_attributes['poll_votes'].sole['options']).to eq(['Não'])
  end

  it 'keeps the stored keys of its own record (internal write), which the API can never send, and records each vote once' do
    poll_message = native_poll
    vote(['Sim'], vote_id: 'V2')
    vote(['Sim'], vote_id: 'V2')
    vote([], vote_id: 'V3')

    # O voto (V2) é o turno do cliente para a IA; o voto retirado (V3) fica atividade escondida.
    expect(conversation.messages.incoming.pluck(:source_id)).to eq(%w[waha-poll-vote-V2])
    expect(conversation.messages.activity.pluck(:source_id)).to eq(%w[waha-poll-vote-V3])
    expect(conversation.messages.where(source_id: %w[waha-poll-vote-V2 waha-poll-vote-V3]).map { |message| message.content_attributes['c2y_hidden'] })
      .to all(be(true))
    expect(poll_message.reload.content_attributes['poll_votes'].sole['options']).to eq([])
  end

  # Rodada de correção, item 5: o voto agregado e o registro dele vão juntos, sem as validações do modelo.
  describe 'the aggregation and its record in one transaction' do
    it 'keeps the poll untouched when the record cannot be saved' do
      poll_message = native_poll
      allow(Waha::RichNative::InternalWrite).to receive(:mark!).and_raise(ActiveRecord::StatementInvalid, 'falhou')

      expect { vote(['Sim']) }.to raise_error(ActiveRecord::StatementInvalid)

      expect(poll_message.reload.content_attributes['poll_votes']).to be_nil
      expect(conversation.messages.where(source_id: 'waha-poll-vote-V1')).to be_empty
    end

    it 'records the vote in a busy conversation (no flooding validation)' do
      poll_message = native_poll
      allow_any_instance_of(Message).to receive(:prevent_message_flooding) do |message| # rubocop:disable RSpec/AnyInstance
        message.errors.add(:base, 'Too many messages') if message.source_id.to_s.start_with?('waha-poll-vote-')
      end

      vote(['Sim'])

      expect(conversation.messages.where(source_id: 'waha-poll-vote-V1')).to exist
      expect(poll_message.reload.content_attributes['poll_votes'].sole['options']).to eq(['Sim'])
    end
  end

  # Rodada de correção, item 6: voto na conversa resolvida quando o contato já está numa conversa mais nova aberta.
  describe 'a vote on a resolved conversation left behind' do
    it 'only aggregates: a hidden activity, the old conversation stays resolved and there is no AI turn' do
      poll_message = native_poll
      conversation.resolved!
      create(:conversation, inbox: inbox, account: account, contact: contact, contact_inbox: conversation.contact_inbox)

      vote(['Sim'])

      expect(poll_message.reload.content_attributes['poll_votes'].sole['options']).to eq(['Sim'])
      record = conversation.messages.find_by(source_id: 'waha-poll-vote-V1')
      # Atividade (não recebida): nem reabre a conversa nem vira turno da IA (o MessageListener só ouve recebida).
      expect(record).to be_activity
      expect(record.content_attributes).to include('c2y_hidden' => true).and(not_include('c2y_ai_turn'))
      expect(conversation.reload).to be_resolved
    end

    it 'is still a turn on a resolved conversation without a newer one (it reopens, as any customer message)' do
      native_poll
      conversation.resolved!

      vote(['Sim'])

      expect(conversation.messages.find_by(source_id: 'waha-poll-vote-V1')).to be_incoming
    end
  end

  describe 'the unsupported the Meta may send to the Cloud for the vote' do
    def cloud_unsupported(context_id)
      params = {
        'contacts' => [{ 'profile' => { 'name' => 'Cliente' }, 'wa_id' => '5511937016094' }],
        'messages' => [{ 'from' => '5511937016094', 'id' => "wamid.unsupported#{SecureRandom.hex(4)}", 'timestamp' => Time.current.to_i.to_s,
                         'type' => 'unsupported', 'context' => { 'id' => context_id } }]
      }.with_indifferent_access
      Whatsapp::IncomingMessageService.new(inbox: inbox, params: params).perform
    end

    it 'is skipped when it points to our native poll, and kept for anything else' do
      Redis::Alfred.setex(WhatsappHybrid::Config.inbox_flag_key(inbox.id), '1', 60)
      poll_message = native_poll
      poll_message.update!(source_id: 'wamid.POLL')
      count = inbox.messages.count

      cloud_unsupported('wamid.POLL')
      expect(inbox.messages.count).to eq(count)

      cloud_unsupported('wamid.OTHER')
      expect(inbox.messages.reload.last.content_attributes['is_unsupported']).to be(true)
    end
  end

  describe WhatsappHybrid::RichNative::RevokeOnDelete do
    def sent_by_web
      create(:message, message_type: :outgoing, content: 'oops', conversation: conversation, account: account, inbox: inbox,
                       source_id: '3EB0SENT', sender: create(:user, account: account))
    end

    it 'asks the engine only on the transition to deleted, not on the later ack' do
      flag_on!
      message = sent_by_web

      expect { message.update!(content: 'apagada', content_attributes: { deleted: true }) }
        .to have_enqueued_job(WhatsappHybrid::RichNative::RevokeJob).once
      expect { message.update!(content_attributes: message.content_attributes.merge('external_error' => nil)) }
        .not_to have_enqueued_job(WhatsappHybrid::RichNative::RevokeJob)
    end
  end

  describe WhatsappHybrid::RichNative::RevokeJob do
    # Contrato com a pele do Max (#1793): o motor confirmou o apagar para todos → revogada_no_canal; erro → nada.
    def deleted_message
      create(:message, message_type: :outgoing, content: 'apagada', conversation: conversation, account: account, inbox: inbox,
                       source_id: '3EB0SENT', content_attributes: { deleted: true })
    end

    it 'marks revogada_no_canal when the engine confirms, without asking to revoke again' do
      flag_on!
      message = deleted_message
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:delete_message).and_return({})
      Redis::Alfred.setex('whatsapp_hybrid:chat_id:hybrid-test:5511937016094', '5511937016094@c.us', 60)

      expect { described_class.perform_now(message.id, '3EB0SENT') }
        .not_to have_enqueued_job(described_class)

      expect(client).to have_received(:delete_message).once
      expect(message.reload.content_attributes).to include('deleted' => true, 'revogada_no_canal' => true)
    end

    it 'logs only the class when the mark cannot be written, and does not run the job again' do
      flag_on!
      message = deleted_message
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:delete_message).and_return({})
      Redis::Alfred.setex('whatsapp_hybrid:chat_id:hybrid-test:5511937016094', '5511937016094@c.us', 60)
      allow_any_instance_of(Message).to receive(:save!).and_raise(ActiveRecord::ConnectionNotEstablished, 'detalhe do banco') # rubocop:disable RSpec/AnyInstance
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(message.id, '3EB0SENT') }.not_to have_enqueued_job(described_class)

      expect(client).to have_received(:delete_message).once
      expect(Rails.logger).to have_received(:error)
        .with("[whatsapp_hybrid] revoke mark failed message=#{message.id} ActiveRecord::ConnectionNotEstablished")
      expect(message.reload.content_attributes).not_to have_key('revogada_no_canal')
    end

    it 'does not mark it when the engine refuses' do
      flag_on!
      message = deleted_message
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:delete_message).and_raise(Waha::Client::Error.new('WAHA DELETE x -> 400', status: 400))
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
      Redis::Alfred.setex('whatsapp_hybrid:chat_id:hybrid-test:5511937016094', '5511937016094@c.us', 60)

      described_class.perform_now(message.id, '3EB0SENT')

      expect(message.reload.content_attributes).not_to have_key('revogada_no_canal')
    end

    it 'reports only the class and the status, never the phone in the path' do
      flag_on!
      message = create(:message, message_type: :outgoing, content: 'oops', conversation: conversation, account: account, inbox: inbox,
                                 source_id: '3EB0SENT')
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:delete_message)
        .and_raise(Waha::Client::Error.new('WAHA DELETE /api/hybrid-test/chats/5511937016094%40c.us/messages/x -> 400', status: 400))
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      reported = nil
      allow(ChatwootExceptionTracker).to receive(:new) { |error, **| (reported = error) && tracker }

      described_class.perform_now(message.id, '3EB0SENT')

      expect(reported).to be_a(WhatsappHybrid::RichNative::RevokeJob::RevokeFailed)
      expect(reported.message).to eq('Waha::Client::Error status=400')
      expect(reported.message).not_to include('5511')
    end
  end
end
