require 'rails_helper'
require_relative 'inbound_context'

# chat#1709 (testador da IA, B1): a escolha vale só se for a MAIS NOVA do eleitor naquele alvo e o valor ainda bater.
# Contrato público (memória da IA, #1601): mensagem que não é escolha, true; escolha superada, false.
describe Waha::RichNative::TurnKinds do
  include_context 'with a waha inbox and its connector'

  let(:contact) { conversation.contact }
  let(:poll) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Qual horário?')
  end

  def stored!(titles)
    poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => contact.id, 'options' => titles }] }) # rubocop:disable Rails/SkipsModelValidations
  end

  def vote(title)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                               content: "Votou: #{title}")
    message.update_column(:content_attributes, { 'c2y_hidden' => true }.merge(Waha::RichNative::AiTurn.choice('poll_vote', poll, [title]))) # rubocop:disable Rails/SkipsModelValidations
    message.reload
  end

  describe '.choice_current?' do
    it 'Tarde -> Manhã -> Tarde: only the last one counts, although the first has the same value' do
      first = vote('Tarde')
      second = vote('Manhã')
      last = vote('Tarde')
      stored!(['Tarde'])

      expect([first, second, last].map { |message| described_class.choice_current?(message) }).to eq([false, false, true])
    end

    it 'sees the newer choice also when its row is stored as a JSON object' do
      first = vote('Tarde')
      newer = vote('Tarde')
      Message.where(id: newer.id).update_all( # rubocop:disable Rails/SkipsModelValidations
        ['content_attributes = ?::json', { 'c2y_ai_turn' => { 'kind' => 'poll_vote', 'target_id' => poll.id, 'choice' => ['Tarde'] } }.to_json]
      )
      stored!(['Tarde'])

      expect(described_class.choice_current?(first)).to be(false)
    end

    it 'keeps the contract: true for a message that is not a choice, false when the value changed' do
      plain = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
      only = vote('Tarde')
      stored!(['Manhã'])

      expect(described_class.choice_current?(plain)).to be(true)
      expect(described_class.choice_current?(only)).to be(false)
    end

    it 'does not mix voters nor targets' do
      other_poll = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Outra?')
      mine = vote('Tarde')
      other = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                               content: 'Votou: Sim')
      other.update_column(:content_attributes, Waha::RichNative::AiTurn.choice('poll_vote', other_poll, ['Sim'])) # rubocop:disable Rails/SkipsModelValidations
      stored!(['Tarde'])

      expect(described_class.choice_current?(mine)).to be(true)
    end
  end

  # Os consumidores do contrato esperam a regra nova (Tarde → Manhã → Tarde = [false, false, true]).
  describe 'consumers of choice_current? with Tarde -> Manhã -> Tarde' do
    let!(:votes) do
      list = [vote('Tarde'), vote('Manhã'), vote('Tarde')]
      stored!(['Tarde'])
      list
    end
    let(:stale_mark) { 'não vale mais' }

    it 'AiChoiceText marks only the superseded ones' do
      texts = votes.map { |message| Waha::RichNative::AiChoiceText.for(message) }

      expect(texts.first(2)).to all(include(stale_mark))
      expect(texts.last).not_to include(stale_mark)
    end

    it 'the CRM ContextBuilder (prepend) reads the same' do
      builder = Crm::Ai::ContextBuilder.new(card: nil)

      expect(builder.send(:message_content, votes.first)).to include(stale_mark)
      expect(builder.send(:message_content, votes.last)).not_to include(stale_mark)
    end

    it 'Decisores::Estado reads the same' do
      flag_on!
      messages = Autonomia::Decisores::Estado.new(conversation: conversation, leituras: %w[mensagens_recentes]).conversa[:messages]

      expect(messages.first(2)).to all(include(stale_mark))
      expect(messages.last).not_to include(stale_mark)
    end

    it 'turn_silence silences a turn with only superseded choices, and not one with the current choice' do
      expect(described_class.turn_silence(votes.first(2), waha: false)).to eq(Waha::RichNative::AgentTurnGuard::STALE_CHOICE_REASON)
      expect(described_class.turn_silence([votes.last], waha: false)).to be_nil
    end
  end

  # Revisão: os leitores avulsos usam o memo por chamada; as consultas de "superada" não crescem com N escolhas.
  describe 'queries of the readers outside the Responder' do
    def choice_queries
      queries = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries += 1 if payload[:sql].include?('c2y_ai_turn') && !payload[:cached]
      end
      yield
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def votes!(count)
      list = (1..count).map { |numero| vote(numero.even? ? 'Tarde' : 'Manhã') }
      stored!([list.last.content_attributes.dig('c2y_ai_turn', 'choice', 0)])
      list
    end

    [5, 20].each do |count|
      it "the CRM ContextBuilder makes one query for #{count} choices" do
        list = votes!(count)
        builder = Crm::Ai::ContextBuilder.new(card: nil)

        expect(choice_queries { list.each { |message| builder.send(:message_content, message) } }).to eq(1)
      end

      it "Decisores::Estado makes one query for #{count} choices" do
        votes!(count)
        estado = Autonomia::Decisores::Estado.new(conversation: conversation, leituras: %w[mensagens_recentes])

        expect(choice_queries { estado.conversa }).to eq(1)
      end
    end
  end

  # Revisão: o ResponderChoice passa ao AiChoiceText o que o guard já decidiu (memo do turno), sem perguntar de novo.
  describe 'ResponderChoice with the memo of the guard' do
    it 'passes current: explicitly to the history text' do
      superseded = vote('Tarde')
      current = vote('Tarde')
      stored!(['Tarde'])
      responder = Autonomia::Agents::Operate::Responder.allocate
      responder.instance_variable_set(:@conversation, conversation)
      responder.instance_variable_set(:@agent, criar_principal(conversation.account))
      allow(responder).to receive_messages(recent_messages: [superseded, current],
                                           equipe: instance_double(Autonomia::Agents::Operate::HistoricoDaEquipe, aplica?: false))
      allow(Waha::RichNative::AiChoiceText).to receive(:for).and_call_original
      allow(described_class).to receive(:choice_current?).and_call_original

      history = responder.send(:history)

      expect(Waha::RichNative::AiChoiceText).to have_received(:for).with(superseded, current: false)
      expect(Waha::RichNative::AiChoiceText).to have_received(:for).with(current, current: true)
      expect(described_class).not_to have_received(:choice_current?)
      expect(history.first[:content]).to include('não vale mais')
      expect(history.last[:content]).not_to include('não vale mais')
    end
  end
end
