require 'rails_helper'

# Regression: quiet-hours clamping must resolve the operational timezone through
# TimeZoneResolver, NOT collapse to UTC. The live bug (conta 6): account has
# reporting_timezone = America/Sao_Paulo, the WhatsApp contact carries no tz, so
# the old `presence || 'UTC'` chain clamped the 08–20 window in UTC and touch #1
# fired at 08:00 UTC == 05:00 BRT.
RSpec.describe 'Crm::FollowUps auto follow-up timezone resolution' do # rubocop:disable RSpec/DescribeClass
  let(:quiet_window) { { 'start' => 8, 'end' => 20, 'tz' => 'contact' } }

  def enable_auto_followup!(pipeline, quiet: quiet_window, intervals: [20, 72, 168])
    metadata = pipeline.metadata.to_h.deep_dup
    metadata['ai'] = {
      'auto_followup' => {
        'enabled' => true,
        'max_touches' => 3,
        'intervals_hours' => intervals,
        'quiet_hours' => quiet
      }
    }
    pipeline.update!(metadata: metadata)
  end

  def build_two_way_conversation(account:, inbox:, contact:, user:, last_inbound_at:)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    # Two inbound + two outbound so sufficient_two_way_exchange? passes.
    2.times { create_incoming_message(conversation: conversation) }
    2.times do
      conversation.messages.create!(
        account_id: account.id, inbox_id: inbox.id,
        message_type: :outgoing, content: 'Resposta', sender: user
      )
    end
    conversation.messages.incoming.update_all(created_at: last_inbound_at) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  describe 'AutoFollowupPlanner touch #1 due_at (planner clamp path)' do
    it 'clamps to 08:00 Sao_Paulo (11:00 UTC) when account.reporting_timezone=America/Sao_Paulo and contact has no tz' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
      contact = account.contacts.create!(name: 'Lead SP', phone_number: '+5511987654321')

      # now = 2026-07-10 09:00 UTC (06:00 SP). last_inbound 20h ago so touch #1
      # target == now (06:00 SP), which is before the 08:00 quiet-window start and
      # must clamp UP to 08:00 SP local == 11:00 UTC.
      now = Time.utc(2026, 7, 10, 9, 0, 0)
      conversation = build_two_way_conversation(
        account: account, inbox: inbox, contact: contact, user: user,
        last_inbound_at: now - 20.hours
      )
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(
        pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
        primary_conversation: conversation, title: 'Lead SP'
      )
      enable_auto_followup!(pipeline)

      allow(Crm::FollowUps::MessagingWindow).to receive(:new).and_wrap_original do |m, *args, **kwargs|
        window = m.call(*args, **kwargs)
        allow(window).to receive(:whatsapp_capable?).and_return(true)
        window
      end

      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline, now: now).perform
      end

      follow_up = card.follow_ups.reload.first
      expect(follow_up).to be_present
      expect(follow_up.due_at.utc).to eq(Time.utc(2026, 7, 10, 11, 0, 0))
      expect(follow_up.due_at.utc).not_to eq(Time.utc(2026, 7, 10, 8, 0, 0))
    end

    it 'uses ENV DEFAULT_OPERATIONAL_TIMEZONE when reporting_timezone is nil' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: nil)
      inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
      contact = account.contacts.create!(name: 'Lead Sem TZ', phone_number: '+5511987654322')

      now = Time.utc(2026, 7, 10, 9, 0, 0)
      conversation = build_two_way_conversation(
        account: account, inbox: inbox, contact: contact, user: user,
        last_inbound_at: now - 20.hours
      )
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(
        pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
        primary_conversation: conversation, title: 'Lead Sem TZ'
      )
      enable_auto_followup!(pipeline)

      allow(Crm::FollowUps::MessagingWindow).to receive(:new).and_wrap_original do |m, *args, **kwargs|
        window = m.call(*args, **kwargs)
        allow(window).to receive(:whatsapp_capable?).and_return(true)
        window
      end

      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'America/Sao_Paulo' do
        Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline, now: now).perform
      end

      follow_up = card.follow_ups.reload.first
      expect(follow_up).to be_present
      expect(follow_up.due_at.utc).to eq(Time.utc(2026, 7, 10, 11, 0, 0))
    end

    it 'DEFERS (fail-closed, no touch) when nothing resolves (source :none) instead of firing at 05h UTC' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: nil)
      inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
      contact = account.contacts.create!(name: 'Lead None', phone_number: '+5511987654323')

      now = Time.utc(2026, 7, 10, 9, 0, 0)
      conversation = build_two_way_conversation(
        account: account, inbox: inbox, contact: contact, user: user,
        last_inbound_at: now - 20.hours
      )
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(
        pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
        primary_conversation: conversation, title: 'Lead None'
      )
      enable_auto_followup!(pipeline)

      allow(Crm::FollowUps::MessagingWindow).to receive(:new).and_wrap_original do |m, *args, **kwargs|
        window = m.call(*args, **kwargs)
        allow(window).to receive(:whatsapp_capable?).and_return(true)
        window
      end

      planned = with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline, now: now).perform
      end

      expect(planned).to eq(0)
      expect(card.follow_ups.reload).to be_empty
    end
  end

  describe 'AutoFollowupTouchBuilder persisted follow_up.timezone' do
    it 'persists the resolved operational timezone (America/Sao_Paulo), not UTC' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
      contact = account.contacts.create!(name: 'Lead TZ', phone_number: '+5511987654324')
      conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
      pipeline, stage = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(
        pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
        primary_conversation: conversation, title: 'Lead TZ'
      )

      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        follow_up = Crm::FollowUps::AutoFollowupTouchBuilder.new(
          card: card, touch: 1, due_at: Time.utc(2026, 7, 10, 11, 0, 0)
        ).perform

        expect(follow_up.timezone).to eq('America/Sao_Paulo')
      end
    end
  end

  describe 'Crm::Ai::Config.resolved_timezone' do
    it 'resolves account.reporting_timezone via the shared resolver' do
      account = Account.create!(name: 'Acc TZ', reporting_timezone: 'America/Sao_Paulo')

      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        expect(Crm::Ai::Config.resolved_timezone(account: account)).to eq('America/Sao_Paulo')
      end
    end

    it 'falls back to ENV default when reporting_timezone is nil' do
      account = Account.create!(name: 'Acc No TZ', reporting_timezone: nil)

      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'America/Sao_Paulo' do
        expect(Crm::Ai::Config.resolved_timezone(account: account)).to eq('America/Sao_Paulo')
      end
    end
  end
end
