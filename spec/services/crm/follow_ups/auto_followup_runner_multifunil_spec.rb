require 'rails_helper'

# Multifunil (#1147): a resposta do cliente só encerra a cadência do card que é o assunto atual da conversa.
RSpec.describe Crm::FollowUps::AutoFollowupRunner do
  let(:now) { Time.current }
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [user]) }
  let(:contact) { account.contacts.create!(name: 'Lead', phone_number: '+5511987650000') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:card) { create_card('Cotação auto') }
  let(:other_card) { create_card('Cotação residencial') }
  let(:follow_up) do
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Retomar', due_at: 10.minutes.ago, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user,
      metadata: { source: 'ai_followup', touch: 1, message_body: 'Olá' }
    )
  end

  before do
    travel_to Time.utc(2026, 9, 14, 15)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    create_incoming_message(conversation: conversation)
    pipeline_and_stage.first.update!(metadata: { ai: { auto_followup: { enabled: true } } })
    focar(card, 1.hour.ago)
    follow_up
    travel 1.second
  end

  def create_card(title)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                              primary_conversation: conversation, title: title)
  end

  def focar(target, at)
    Crm::CardConversation.find_or_create_by!(account: account, card: target, conversation: conversation).update!(focused_at: at)
  end

  it 'adia, sem encerrar, quando o cliente responde sobre outro pedido da conversa' do
    focar(other_card, Time.current)
    create_incoming_message(conversation: conversation, content: 'E a do apartamento?')
    expect(Crm::FollowUps::MessageSender).not_to receive(:new)

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:rescheduled)
    expect(follow_up.reload.due_at).to be >= Time.current + described_class::OTHER_SUBJECT_WAIT
    state = card.reload.metadata.dig('ai', 'auto_followup_state')
    expect(state['reply_seen_message_id']).to be_present
    expect(state['stopped_reason']).to be_blank
    expect(card.activities.where(event_type: 'ai_followup_postponed')).to exist
  end

  it 'encerra quando a resposta é sobre este card (assunto atual)' do
    create_incoming_message(conversation: conversation, content: 'Pode seguir com a do carro')

    result = described_class.new(follow_up: follow_up, now: Time.current).perform

    expect(result.status).to eq(:stopped)
  end

  it 'depois de adiar, a mesma resposta não adia de novo (horário com fração de segundo)' do
    focar(other_card, Time.current)
    reply = create_incoming_message(conversation: conversation, content: 'E a do apartamento?')
    reply.update!(created_at: reply.created_at + 0.123456.seconds)
    described_class.new(follow_up: follow_up, now: Time.current).perform

    runner = described_class.new(follow_up: follow_up.reload, now: 7.hours.from_now)

    expect(runner.send(:customer_replied_about_other_subject)).to be_nil
    expect(runner.send(:customer_replied_since_scheduling?)).to be(false)
  end
end
