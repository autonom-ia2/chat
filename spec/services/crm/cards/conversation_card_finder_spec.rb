require 'rails_helper'

RSpec.describe Crm::Cards::ConversationCardFinder do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:conversation) { create(:conversation, account: account) }
  let(:other_conversation) { create(:conversation, account: account, contact: conversation.contact, inbox: conversation.inbox) }
  let(:finder) { described_class.new(account: account) }

  def create_card(primary:, status: :open, title: 'Lead')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                              primary_conversation: primary, title: title, status: status)
  end

  def link(card, focused_at: nil)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .tap { |record| record.update!(focused_at: focused_at) }
  end

  it 'sem assunto atual marcado, mantém a escolha de antes: o card principal da conversa, depois o vinculado' do
    linked = create_card(primary: other_conversation, title: 'Vinculado')
    link(linked)
    primary = create_card(primary: conversation, title: 'Principal')

    expect(finder.find(conversation)).to eq(primary)
    expect(finder.all(conversation).to_a).to eq([primary, linked])
  end

  it 'devolve o assunto atual (focused_at mais recente) quando a conversa tem vários cards' do
    primary = create_card(primary: conversation, title: 'Cotação auto')
    link(primary, focused_at: 2.hours.ago)
    residencial = create_card(primary: other_conversation, title: 'Cotação residencial')
    link(residencial, focused_at: 1.minute.ago)

    expect(finder.find(conversation)).to eq(residencial)
    expect(finder.all(conversation).to_a).to eq([residencial, primary])
  end

  it 'ignora card arquivado e mantém card ganho' do
    won = create_card(primary: conversation, status: :won)
    archived = create_card(primary: other_conversation, status: :archived)
    link(archived, focused_at: Time.current)

    expect(finder.all(conversation).to_a).to eq([won])
  end

  it 'não devolve card de outra conversa sem vínculo' do
    create_card(primary: other_conversation)

    expect(finder.find(conversation)).to be_nil
  end
end
