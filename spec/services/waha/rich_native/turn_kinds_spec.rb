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
end
