require 'rails_helper'

RSpec.describe Crm::Cards::CurrentSubject do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:conversation) { create(:conversation, account: account) }

  def create_card(title, primary: conversation)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                              primary_conversation: primary, title: title)
  end

  def focar(card, at)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: at)
  end

  it 'é o assunto atual quando a conversa tem um pedido só' do
    expect(described_class.card?(create_card('Único'))).to be(true)
  end

  it 'só o card com o foco mais recente é o assunto atual' do
    auto = create_card('Auto')
    casa = create_card('Casa')
    focar(auto, 2.hours.ago)
    focar(casa, 1.minute.ago)

    expect(described_class.card?(casa)).to be(true)
    expect(described_class.card?(auto)).to be(false)
  end

  it 'card sem conversa não é barrado' do
    pipeline, stage = pipeline_and_stage
    solto = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Sem conversa')

    expect(described_class.card?(solto)).to be(true)
  end
end
