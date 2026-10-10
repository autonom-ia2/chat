require 'rails_helper'

# Multifunil (#1147): quem passa a tratar de um pedido na conversa e quem a IA deixa em paz.
RSpec.describe 'Assunto atual no multifunil' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:contact) { account.contacts.create!(name: 'Lead', phone_number: '+5511987652222') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:finder) { Crm::Cards::ConversationCardFinder.new(account: account) }

  def create_card(title, primary: conversation)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, contact: contact, inbox: inbox,
                              primary_conversation: primary)
  end

  def focar(card, at)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: at)
  end

  describe Crm::Cards::ConversationLinker do
    it 'o card vinculado vira o assunto atual da conversa' do
      focar(create_card('Auto'), 1.hour.ago)
      outra = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      casa = create_card('Casa', primary: outra)

      described_class.new(card: casa, conversation: conversation, actor: admin).link

      expect(finder.find(conversation)).to eq(casa)
    end

    it 'vínculo que já existia não rouba o foco' do
      outra = create_crm_conversation(account: account, inbox: inbox, contact: contact)
      casa = create_card('Casa', primary: outra)
      focar(casa, 2.hours.ago)
      auto = create_card('Auto')
      focar(auto, 1.minute.ago)

      described_class.new(card: casa, conversation: conversation, actor: admin).link

      expect(finder.find(conversation)).to eq(auto)
    end
  end

  describe Crm::Ai::StaleCardsJob do
    it 'só enfileira o card parado que é o assunto atual' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      auto = create_card('Auto')
      casa = create_card('Casa')
      focar(auto, 2.hours.ago)
      focar(casa, 1.minute.ago)
      [auto, casa].each { |card| card.update_columns(last_activity_at: 30.days.ago) } # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.new.perform }.to have_enqueued_job(Crm::Ai::EvaluateCardJob).with(casa.id).exactly(:once)
      expect(Crm::Ai::EvaluateCardJob).not_to have_been_enqueued.with(auto.id)
    end
  end

  describe Crm::Ai::Observer do
    it 'não apaga o que outro processo gravou no metadata enquanto o card estava em memória' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      card = create_card('Auto')
      outro_processo = Crm::Card.find(card.id)
      outro_processo.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'touches' => [1] } } })

      described_class.new(card: card).schedule_evaluation

      ai = card.reload.metadata['ai']
      expect(ai['auto_followup_state']).to eq('touches' => [1])
      expect(ai['evaluate_token']).to be_present
    end
  end
end
