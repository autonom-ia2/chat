require 'rails_helper'

RSpec.describe Sla::EvaluateAppliedSlaService do
  # The service (and the applied_sla creation hook) are no-ops without the `sla` feature (fork choke point),
  # so the feature must be on before the let! records below are created.
  let!(:account) { create(:account).tap { |created| created.enable_features!('sla') } }
  let!(:user_1) { create(:user, account: account) }
  let!(:sla_policy) do
    create(:sla_policy,
           account: account,
           first_response_time_threshold: nil,
           next_response_time_threshold: nil,
           resolution_time_threshold: nil)
  end
  let!(:conversation) do
    create(:conversation,
           created_at: 6.hours.ago, assignee: user_1,
           account: sla_policy.account,
           sla_policy: sla_policy)
  end
  let!(:applied_sla) { conversation.applied_sla }

  describe '#perform - blocked contacts' do
    before do
      applied_sla.sla_policy.update(first_response_time_threshold: 1.hour, resolution_time_threshold: 1.hour)
      conversation.contact.update!(blocked: true)
    end

    it 'does not create SLA events or update SLA status' do
      described_class.new(applied_sla: applied_sla).perform

      expect(SlaEvent.where(applied_sla: applied_sla)).not_to exist
      expect(applied_sla.reload.sla_status).to eq('active')
    end

    it 'does not mark resolved conversations as hit or missed' do
      conversation.resolved!

      described_class.new(applied_sla: applied_sla).perform

      expect(SlaEvent.where(applied_sla: applied_sla)).not_to exist
      expect(applied_sla.reload.sla_status).to eq('active')
    end
  end

  describe '#perform - SLA misses' do
    context 'when first response SLA is missed' do
      before { applied_sla.sla_policy.update(first_response_time_threshold: 1.hour) }

      it 'updates the SLA status to missed and logs a warning' do
        allow(Rails.logger).to receive(:warn)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:warn).with("SLA frt missed for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}")
        expect(applied_sla.reload.sla_status).to eq('active_with_misses')
      end

      it 'creates SlaEvent only for frt miss' do
        described_class.new(applied_sla: applied_sla).perform

        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'frt').count).to eq(1)
        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'nrt').count).to eq(0)
        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'rt').count).to eq(0)
      end
    end

    context 'when next response SLA is missed' do
      before do
        applied_sla.sla_policy.update(next_response_time_threshold: 1.hour)
        conversation.update(first_reply_created_at: 5.hours.ago, waiting_since: 5.hours.ago)
      end

      it 'updates the SLA status to missed and logs a warning' do
        allow(Rails.logger).to receive(:warn)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:warn).with("SLA nrt missed for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}")
        expect(applied_sla.reload.sla_status).to eq('active_with_misses')
      end

      it 'creates SlaEvent only for nrt miss' do
        described_class.new(applied_sla: applied_sla).perform

        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'frt').count).to eq(0)
        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'nrt').count).to eq(1)
        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'rt').count).to eq(0)
      end
    end

    context 'when resolution time SLA is missed' do
      before { applied_sla.sla_policy.update(resolution_time_threshold: 1.hour) }

      it 'updates the SLA status to missed and logs a warning' do
        allow(Rails.logger).to receive(:warn)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:warn).with("SLA rt missed for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}")

        expect(applied_sla.reload.sla_status).to eq('active_with_misses')
      end

      it 'creates SlaEvent only for rt miss' do
        described_class.new(applied_sla: applied_sla).perform

        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'frt').count).to eq(0)
        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'nrt').count).to eq(0)
        expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'rt').count).to eq(1)
      end
    end

    # We will mark resolved miss only if while processing the SLA
    # if the conversation is resolved and the resolution time is missed by small margins then we will not mark it as missed
    context 'when resolved conversation with resolution time SLA is missed' do
      before do
        conversation.resolved!
        applied_sla.sla_policy.update(resolution_time_threshold: 1.hour)
      end

      it 'does not update the SLA status to missed' do
        described_class.new(applied_sla: applied_sla).perform
        expect(applied_sla.reload.sla_status).to eq('hit')
      end
    end

    context 'when multiple SLAs are missed' do
      before do
        applied_sla.sla_policy.update(first_response_time_threshold: 1.hour, next_response_time_threshold: 1.hour, resolution_time_threshold: 1.hour)
        conversation.update(first_reply_created_at: 5.hours.ago, waiting_since: 5.hours.ago)
      end

      it 'updates the SLA status to missed and logs multiple warnings' do
        allow(Rails.logger).to receive(:warn)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:warn).with("SLA rt missed for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}").exactly(1).time
        expect(Rails.logger).to have_received(:warn).with("SLA nrt missed for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}").exactly(1).time
        expect(applied_sla.reload.sla_status).to eq('active_with_misses')
      end
    end
  end

  describe '#perform - SLA hits' do
    context 'when first response SLA is hit' do
      before do
        applied_sla.sla_policy.update(first_response_time_threshold: 6.hours)
        conversation.update(first_reply_created_at: 30.minutes.ago)
      end

      it 'sla remains active until conversation is resolved' do
        described_class.new(applied_sla: applied_sla).perform
        expect(applied_sla.reload.sla_status).to eq('active')
      end

      it 'updates the SLA status to hit and logs an info when conversations is resolved' do
        conversation.resolved!
        allow(Rails.logger).to receive(:info)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:info).with("SLA hit for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}")
        expect(applied_sla.reload.sla_status).to eq('hit')
        expect(SlaEvent.count).to eq(0)
        expect(Notification.count).to eq(0)
      end
    end

    context 'when first response SLA is hit after non-business hours' do
      let(:created_at) { Time.zone.parse('2026-06-25 00:39:56 UTC') }
      let(:wall_clock_breach_time) { Time.zone.parse('2026-06-25 01:40:03 UTC') }
      let(:first_reply_created_at) { Time.zone.parse('2026-06-25 11:45:36 UTC') }
      let(:post_reply_eval_time) { Time.zone.parse('2026-06-25 11:46:38 UTC') }
      let(:email_inbox) { create(:inbox, :with_email, account: account, working_hours_enabled: true, timezone: 'America/New_York') }
      let(:business_hours_sla_policy) do
        create(
          :sla_policy,
          account: account,
          first_response_time_threshold: 1.hour,
          next_response_time_threshold: nil,
          resolution_time_threshold: nil,
          only_during_business_hours: true
        )
      end
      let(:business_hours_conversation) do
        create(
          :conversation,
          account: account,
          inbox: email_inbox,
          sla_policy: business_hours_sla_policy,
          created_at: created_at,
          last_activity_at: created_at
        )
      end
      let(:business_hours_applied_sla) { business_hours_conversation.applied_sla }

      before do
        {
          0 => [11, 0, 20, 0],
          1 => [7, 0, 20, 0],
          2 => [7, 0, 20, 0],
          3 => [7, 0, 20, 0],
          4 => [7, 0, 16, 0],
          5 => [7, 0, 16, 0],
          6 => [11, 0, 20, 0]
        }.each do |day_of_week, (open_hour, open_minutes, close_hour, close_minutes)|
          email_inbox.working_hours.find_by(day_of_week: day_of_week).update!(
            open_hour: open_hour,
            open_minutes: open_minutes,
            close_hour: close_hour,
            close_minutes: close_minutes,
            closed_all_day: false,
            open_all_day: false
          )
        end
      end

      it 'does not mark FRT missed while outside business hours or after an on-time business-hours reply' do
        travel_to wall_clock_breach_time do
          described_class.new(applied_sla: business_hours_applied_sla).perform
        end

        business_hours_conversation.update!(first_reply_created_at: first_reply_created_at, last_activity_at: first_reply_created_at)

        travel_to post_reply_eval_time do
          described_class.new(applied_sla: business_hours_applied_sla).perform
        end

        expect(business_hours_applied_sla.reload.sla_status).to eq('active')
        expect(SlaEvent.where(applied_sla: business_hours_applied_sla, event_type: 'frt')).not_to exist
      end
    end

    context 'when next response SLA is hit' do
      before do
        applied_sla.sla_policy.update(next_response_time_threshold: 6.hours)
        conversation.update(first_reply_created_at: 30.minutes.ago, waiting_since: nil)
      end

      it 'sla remains active until conversation is resolved' do
        described_class.new(applied_sla: applied_sla).perform
        expect(applied_sla.reload.sla_status).to eq('active')
      end

      it 'updates the SLA status to hit and logs an info when conversations is resolved' do
        conversation.resolved!
        allow(Rails.logger).to receive(:info)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:info).with("SLA hit for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}")
        expect(applied_sla.reload.sla_status).to eq('hit')
        expect(SlaEvent.count).to eq(0)
      end
    end

    context 'when resolution time SLA is hit' do
      before do
        applied_sla.sla_policy.update(resolution_time_threshold: 8.hours)
        conversation.resolved!
      end

      it 'updates the SLA status to hit and logs an info' do
        allow(Rails.logger).to receive(:info)
        described_class.new(applied_sla: applied_sla).perform
        expect(Rails.logger).to have_received(:info).with("SLA hit for conversation #{conversation.id} in account " \
                                                          "#{applied_sla.account_id} for sla_policy #{sla_policy.id}")
        expect(applied_sla.reload.sla_status).to eq('hit')
        expect(SlaEvent.count).to eq(0)
      end
    end
  end

  describe 'SLA evaluation with frt hit, multiple nrt misses and rt miss' do
    before do
      # Setup SLA Policy thresholds
      applied_sla.sla_policy.update(
        first_response_time_threshold: 2.hours, # Hit frt
        next_response_time_threshold: 1.hour, # Miss nrt multiple times
        resolution_time_threshold: 4.hours # Miss rt
      )

      # Simulate conversation timeline
      # Hit frt
      # incoming message from customer
      create(:message, conversation: conversation, account: conversation.account, created_at: 6.hours.ago, message_type: :incoming)
      # outgoing message from agent within frt
      create(:message, conversation: conversation, account: conversation.account, created_at: 5.hours.ago, message_type: :outgoing)

      # Miss nrt first time
      create(:message, conversation: conversation, account: conversation.account, created_at: 4.hours.ago, message_type: :incoming)
      described_class.new(applied_sla: applied_sla).perform

      # Miss nrt second time
      create(:message, conversation: conversation, account: conversation.account, created_at: 3.hours.ago, message_type: :incoming)
      described_class.new(applied_sla: applied_sla).perform

      # Conversation is resolved missing rt
      conversation.update(status: 'resolved')

      # this will not create a new notification for rt miss as conversation is resolved
      # but we would have already created an rt miss notification during previous evaluation
      described_class.new(applied_sla: applied_sla).perform
    end

    it 'updates the SLA status to missed' do
      # the status would be missed as the conversation is resolved
      expect(applied_sla.reload.sla_status).to eq('missed')
    end

    it 'creates necessary sla events' do
      expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'frt').count).to eq(0)
      expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'nrt').count).to eq(2)
      expect(SlaEvent.where(applied_sla: applied_sla, event_type: 'rt').count).to eq(1)
    end
  end

  # Issue #283: the deadline shown on the card/Kanban (AppliedSla#calculate_due_at) and the instant a
  # breach is recorded must be the same number, under the fork calendar rules (agent > inbox > 24/7,
  # several blocks per day, exclude_groups, AiBreachGuard, blocked-contact and resolution freezes).
  describe 'one clock: card deadline == breach instant' do
    # America/Sao_Paulo (UTC-3, no DST). 2026-09-02 is a Wednesday.
    def brt(text)
      ActiveSupport::TimeZone['America/Sao_Paulo'].parse(text)
    end

    def events(applied_sla, type)
      SlaEvent.where(applied_sla: applied_sla, event_type: type)
    end

    def perform_at(applied_sla, time)
      travel_to(time) { described_class.new(applied_sla: applied_sla).perform }
    end

    # Evaluates one second before the card deadline (nothing may be recorded) and at the deadline
    # (the breach must be recorded), proving both clocks agree.
    def expect_breach_exactly_at_due_at(applied_sla, type, due_at)
      perform_at(applied_sla, Time.zone.at(due_at) - 1.second)
      expect(events(applied_sla, type)).not_to exist

      perform_at(applied_sla, Time.zone.at(due_at))
      expect(events(applied_sla, type).count).to eq(1)
      expect(applied_sla.reload.sla_status).to eq('active_with_misses')
    end

    # NOTE: the file-level let!(:conversation)/let!(:applied_sla) evaluate the innermost definitions
    # before any nested `before`, so per-context variations go through `let` overrides, not updates.
    let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo') }
    let(:only_during_business_hours) { true }
    let(:business_hours_policy) do
      create(:sla_policy, account: account, only_during_business_hours: only_during_business_hours, exclude_groups: true,
                          first_response_time_threshold: 30.minutes, next_response_time_threshold: 30.minutes,
                          resolution_time_threshold: 4.hours)
    end
    let(:conversation_created_at) { brt('2026-09-02 13:00') }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, assignee: user_1, sla_policy: business_hours_policy,
                            created_at: conversation_created_at, last_activity_at: conversation_created_at)
    end
    let(:applied_sla) { conversation.applied_sla }

    before do
      # Inbox calendar: Mon-Fri 08:00-18:00. The agent calendar (when present) overrides it.
      create(:crm_service_schedule, account: account, owner: inbox, weekdays: [1, 2, 3, 4, 5], hours: [['08:00', '18:00']])
    end

    context 'when the agent calendar differs from the inbox calendar (corretor 14h-18h, cliente escreve 13h)' do
      before { create(:crm_service_schedule, account: account, owner: user_1, weekdays: [3], hours: [['14:00', '18:00']]) }

      it 'shows 14:30 on the card and records the FRT breach at 14:30, not at 13:30' do
        expect(applied_sla.frt_due_at).to eq(brt('2026-09-02 14:30').to_i)

        expect_breach_exactly_at_due_at(applied_sla, 'frt', applied_sla.frt_due_at)
      end

      it 'records the NRT breach exactly at nrt_due_at computed from waiting_since' do
        conversation.update!(first_reply_created_at: brt('2026-09-02 14:05'), waiting_since: brt('2026-09-02 17:50'))

        # The agent calendar wins as a whole (it only opens on Wednesdays): 10 min Wed + 20 min next Wed.
        expect(applied_sla.nrt_due_at).to eq(brt('2026-09-09 14:20').to_i)

        expect_breach_exactly_at_due_at(applied_sla, 'nrt', applied_sla.nrt_due_at)
      end

      it 'records the RT breach exactly at rt_due_at (4h: Wed 14-18)' do
        conversation.update!(first_reply_created_at: brt('2026-09-02 14:05'), waiting_since: nil)

        expect(applied_sla.rt_due_at).to eq(brt('2026-09-02 18:00').to_i)

        expect_breach_exactly_at_due_at(applied_sla, 'rt', applied_sla.rt_due_at)
      end

      it 'treats a first reply on or before frt_due_at as within threshold even outside wall-clock time' do
        conversation.update!(first_reply_created_at: brt('2026-09-02 14:30'), waiting_since: nil)

        travel_to(brt('2026-09-02 15:00')) { described_class.new(applied_sla: applied_sla).perform }

        expect(events(applied_sla, 'frt')).not_to exist
        expect(applied_sla.reload.sla_status).to eq('active')
      end

      it 'records the FRT breach when the first reply came after frt_due_at' do
        conversation.update!(first_reply_created_at: brt('2026-09-02 14:31'), waiting_since: nil)

        travel_to(brt('2026-09-02 15:00')) { described_class.new(applied_sla: applied_sla).perform }

        expect(events(applied_sla, 'frt').count).to eq(1)
      end
    end

    context 'when the inbox calendar has several blocks in a day (09-12, 14-18)' do
      let(:conversation_created_at) { brt('2026-09-02 11:45') }

      before do
        blocks = attributes_for(:crm_service_schedule, weekdays: [3], hours: [['09:00', '12:00'], ['14:00', '18:00']])[:blocks]
        Crm::ServiceSchedule.find_by!(account: account, owner: inbox).update!(blocks: blocks)
      end

      it 'jumps the lunch gap on the card and on the breach (11:45 + 30min = 14:15)' do
        expect(applied_sla.frt_due_at).to eq(brt('2026-09-02 14:15').to_i)

        expect_breach_exactly_at_due_at(applied_sla, 'frt', applied_sla.frt_due_at)
      end
    end

    context 'when no fork calendar is usable' do
      before { Crm::ServiceSchedule.where(account: account).update_all(enabled: false) } # rubocop:disable Rails/SkipsModelValidations

      it 'falls back to the upstream inbox working hours for both the card and the breach' do
        inbox.update!(working_hours_enabled: true)
        inbox.working_hours.find_each { |wh| wh.update!(open_hour: 15, open_minutes: 0, close_hour: 19, close_minutes: 0, closed_all_day: false) }

        expect(applied_sla.frt_due_at).to eq(brt('2026-09-02 15:30').to_i)

        expect_breach_exactly_at_due_at(applied_sla, 'frt', applied_sla.frt_due_at)
      end
    end

    context 'when the policy is 24/7 (only_during_business_hours = false)' do
      let(:only_during_business_hours) { false }

      before { create(:crm_service_schedule, account: account, owner: user_1, weekdays: [3], hours: [['14:00', '18:00']]) }

      it 'ignores every calendar: card and breach at created_at + threshold' do
        expect(applied_sla.frt_due_at).to eq(brt('2026-09-02 13:30').to_i)

        expect_breach_exactly_at_due_at(applied_sla, 'frt', applied_sla.frt_due_at)
      end
    end

    context 'when the conversation is a WhatsApp group and the policy excludes groups' do
      let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo', channel: create(:channel_api, account: account)) }
      let(:conversation) do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '120363000000000000@g.us')
        create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, assignee: user_1,
                              sla_policy: business_hours_policy, created_at: conversation_created_at, last_activity_at: conversation_created_at)
      end

      it 'still shows a deadline but never records a breach' do
        expect(applied_sla.frt_due_at).to eq(brt('2026-09-02 13:30').to_i)

        travel_to(Time.zone.at(applied_sla.frt_due_at) + 1.day) { described_class.new(applied_sla: applied_sla).perform }

        expect(SlaEvent.where(applied_sla: applied_sla)).not_to exist
        expect(applied_sla.reload.sla_status).to eq('active')
      end
    end

    context 'when the AI breach guard decides the customer is not waiting' do
      before do
        allow(Sla::AiBreachGuard).to receive(:new).and_return(instance_double(Sla::AiBreachGuard, skip_breach?: true))
      end

      it 'holds the breach at the deadline and asks the guard only at that instant' do
        travel_to(Time.zone.at(applied_sla.frt_due_at) - 1.second) { described_class.new(applied_sla: applied_sla).perform }
        expect(Sla::AiBreachGuard).not_to have_received(:new)

        travel_to(Time.zone.at(applied_sla.frt_due_at)) { described_class.new(applied_sla: applied_sla).perform }

        expect(Sla::AiBreachGuard).to have_received(:new).with(applied_sla: applied_sla, breach_type: 'frt')
        expect(events(applied_sla, 'frt')).not_to exist
        expect(applied_sla.reload.sla_status).to eq('active')
      end
    end

    context 'when the contact is blocked' do
      before { conversation.contact.update!(blocked: true) }

      it 'freezes: no breach at or after the deadline' do
        travel_to(Time.zone.at(applied_sla.frt_due_at) + 1.hour) { described_class.new(applied_sla: applied_sla).perform }

        expect(SlaEvent.where(applied_sla: applied_sla)).not_to exist
        expect(applied_sla.reload.sla_status).to eq('active')
      end
    end

    context 'when the conversation is resolved before the resolution deadline' do
      it 'freezes: RT is not breached afterwards and the SLA is marked hit with completed_at' do
        conversation.update!(first_reply_created_at: brt('2026-09-02 13:10'))
        travel_to(brt('2026-09-02 15:00')) { conversation.resolved! }

        travel_to(Time.zone.at(applied_sla.rt_due_at) + 1.day) { described_class.new(applied_sla: applied_sla).perform }

        expect(events(applied_sla, 'rt')).not_to exist
        expect(applied_sla.reload.sla_status).to eq('hit')
        expect(applied_sla.completed_at).to eq(brt('2026-09-02 15:00'))
      end
    end
  end
end
