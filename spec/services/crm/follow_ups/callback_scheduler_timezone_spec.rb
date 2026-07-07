require 'rails_helper'

# Regression (H2-callback): "me liga terça 9h" must schedule the reminder at
# 09:00 in the account's OPERATIONAL timezone, not 09:00 UTC. The old chain
# `ActiveSupport::TimeZone[timezone] || 'UTC'` (fed by a resolver that discards
# `source`) parsed the naive local "YYYY-MM-DDTHH:MM" against UTC whenever the
# tz collapsed, so due_at landed 3h early in BR. And when NOTHING resolves
# (source :none) the callback must fail-closed (not scheduled) rather than fire
# at a wrong local hour.
RSpec.describe Crm::FollowUps::CallbackScheduler do
  let(:requested_at) { '2026-07-14T09:00' } # a future Tuesday, 9h LOCAL, naive

  def build_card(account:, user:)
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead Callback', phone_number: '+5511987650000')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead Callback'
    )
  end

  def callback_payload
    { 'detected' => true, 'confidence' => 0.9, 'requested_at' => requested_at,
      'requested_at_text' => 'me liga terça 9h' }
  end

  around do |example|
    travel_to(Time.utc(2026, 7, 1, 12, 0, 0)) { example.run }
  end

  describe 'operational timezone resolution' do
    it 'schedules due_at at 09:00 Sao_Paulo (12:00 UTC), not 09:00 UTC' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      card = build_card(account: account, user: user)

      follow_up = with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        described_class.new(card: card, callback: callback_payload).perform
      end

      expect(follow_up).to be_present
      expect(follow_up.due_at.utc).to eq(Time.utc(2026, 7, 14, 12, 0, 0))
      expect(follow_up.due_at.utc).not_to eq(Time.utc(2026, 7, 14, 9, 0, 0))
      expect(follow_up.timezone).to eq('America/Sao_Paulo')
    end

    it 'uses ENV DEFAULT_OPERATIONAL_TIMEZONE when reporting_timezone is nil' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: nil)
      card = build_card(account: account, user: user)

      follow_up = with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'America/Sao_Paulo' do
        described_class.new(card: card, callback: callback_payload).perform
      end

      expect(follow_up).to be_present
      expect(follow_up.due_at.utc).to eq(Time.utc(2026, 7, 14, 12, 0, 0))
      expect(follow_up.timezone).to eq('America/Sao_Paulo')
    end

    it 'fail-closed: does NOT schedule when nothing resolves (source :none)' do
      account, user = create_account_and_user
      account.update!(reporting_timezone: nil)
      card = build_card(account: account, user: user)

      follow_up = with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        described_class.new(card: card, callback: callback_payload).perform
      end

      expect(follow_up).to be_nil
      expect(card.follow_ups.reload).to be_empty
    end
  end
end
