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

  def message_with(card_id)
    create(:message, account: account, conversation: conversation, message_type: :outgoing,
                     content_attributes: { 'crm_card_id' => card_id, 'external_echo' => 'mantido' })
  end

  it 'keeps the subject when the card belongs to the conversation' do
    card = create_card(primary: conversation)
    message = message_with(card.id)

    described_class.new(message).sanitize!

    expect(message.reload.content_attributes['crm_card_id']).to eq(card.id)
  end

  it 'drops a card from another conversation and keeps the other attributes' do
    other_card = create_card(primary: create(:conversation, account: account))
    message = message_with(other_card.id)

    described_class.new(message).sanitize!

    expect(message.reload.content_attributes).not_to have_key('crm_card_id')
    expect(message.content_attributes['external_echo']).to eq('mantido')
  end

  it 'drops a card from another account' do
    other_account = create(:account)
    foreign_pair = create_crm_pipeline(account: other_account, user: create(:user, account: other_account))
    foreign_card = create_card(primary: create(:conversation, account: other_account), target_account: other_account,
                               pipeline_and_stage_pair: foreign_pair)
    message = message_with(foreign_card.id)

    described_class.new(message).sanitize!

    expect(message.reload.content_attributes).not_to have_key('crm_card_id')
  end

  it 'leaves messages without a subject untouched' do
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing)

    expect { described_class.new(message).sanitize! }.not_to(change { message.reload.updated_at })
  end
end
