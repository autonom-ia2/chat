require 'rails_helper'

RSpec.describe Crm::Conversations::MessageSubject do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:conversation) { create(:conversation, account: account) }

  def create_card(primary:, target_account: account, pipeline_and_stage_pair: pipeline_and_stage)
    pipeline, stage = pipeline_and_stage_pair
    target_account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: primary.contact,
                                     primary_conversation: primary, title: 'Assunto')
  end

  # A conferência roda no before_validation da mensagem: o que se lê aqui é o que foi gravado.
  def create_message(card_id)
    create(:message, account: account, conversation: conversation, message_type: :outgoing,
                     content_attributes: { 'crm_card_id' => card_id, 'external_echo' => 'mantido' })
  end

  it 'keeps the subject when the card belongs to the conversation' do
    card = create_card(primary: conversation)

    expect(create_message(card.id).reload.content_attributes['crm_card_id']).to eq(card.id)
  end

  it 'normalizes a numeric string id' do
    card = create_card(primary: conversation)

    expect(create_message(card.id.to_s).reload.content_attributes['crm_card_id']).to eq(card.id)
  end

  it 'drops a card from another conversation and keeps the other attributes' do
    other_card = create_card(primary: create(:conversation, account: account))

    message = create_message(other_card.id).reload

    expect(message.content_attributes).not_to have_key('crm_card_id')
    expect(message.content_attributes['external_echo']).to eq('mantido')
  end

  it 'drops a card from another account' do
    other_account = create(:account)
    foreign_pair = create_crm_pipeline(account: other_account, user: create(:user, account: other_account))
    foreign_card = create_card(primary: create(:conversation, account: other_account), target_account: other_account,
                               pipeline_and_stage_pair: foreign_pair)

    expect(create_message(foreign_card.id).reload.content_attributes).not_to have_key('crm_card_id')
  end

  it 'drops values that are not a whole id instead of failing' do
    card = create_card(primary: conversation)

    [[card.id], { 'id' => card.id }, true, "#{card.id}abc", 1.9, ''].each do |value|
      expect(create_message(value).reload.content_attributes).not_to have_key('crm_card_id')
    end
  end

  it 'leaves messages without a subject untouched' do
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing,
                               content_attributes: { 'external_echo' => 'mantido' })

    expect(message.reload.content_attributes).to eq('external_echo' => 'mantido')
  end
end
