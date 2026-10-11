require 'rails_helper'

RSpec.describe Crm::FollowUps::Broadcaster do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  it 'broadcasts reminder due events for overdue reminder follow-ups' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', owner: admin)
    follow_up = account.crm_follow_ups.create!(
      card: card,
      title: 'Retornar',
      due_at: 10.minutes.ago,
      timezone: 'UTC',
      automation_mode: :reminder_only,
      status: :overdue,
      assignee: admin,
      created_by: admin
    )

    allow(ActionCableBroadcastJob).to receive(:perform_later)

    described_class.broadcast_due(follow_up)

    expect(ActionCableBroadcastJob).to have_received(:perform_later).at_least(:once).with(
      [admin.pubsub_token],
      Events::Types::CRM_FOLLOW_UP_DUE,
      hash_including(id: follow_up.id, title: 'Retornar', account_id: account.id)
    )
  end

  it 'leva no evento só o metadata que o cartão usa para reconhecer o alerta do agendamento' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', owner: admin)
    follow_up = account.crm_follow_ups.create!(
      card: card, title: 'O aviso não saiu', due_at: 1.minute.ago, timezone: 'UTC', automation_mode: :reminder_only,
      status: :overdue, assignee: admin,
      metadata: { 'source' => 'booking_agent_alert', 'event' => 'notice_failed', 'meeting_id' => 9, 'kind' => 'booked',
                  'reason' => 'template_required', 'contact_name' => 'Marcos', 'starts_at' => '2026-10-20T13:00:00Z',
                  'reminder_dismissed_by' => {}, 'send_error' => 'boom' }
    )
    allow(ActionCableBroadcastJob).to receive(:perform_later)

    described_class.broadcast_due(follow_up)

    expect(ActionCableBroadcastJob).to have_received(:perform_later).at_least(:once).with(
      [admin.pubsub_token], Events::Types::CRM_FOLLOW_UP_DUE,
      hash_including(metadata: {
                       'source' => 'booking_agent_alert', 'event' => 'notice_failed', 'meeting_id' => 9, 'kind' => 'booked',
                       'reason' => 'template_required', 'contact_name' => 'Marcos', 'starts_at' => '2026-10-20T13:00:00Z'
                     })
    )
  end

  it 'skips auto-send follow-ups' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead')
    follow_up = account.crm_follow_ups.new(
      card: card,
      title: 'Auto',
      due_at: 10.minutes.ago,
      timezone: 'UTC',
      automation_mode: :auto_send_message,
      status: :overdue,
      created_by: admin,
      metadata: { message_body: 'Oi' }
    )
    follow_up.save!(validate: false)

    allow(ActionCableBroadcastJob).to receive(:perform_later)

    described_class.broadcast_due(follow_up)

    expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
  end
end
