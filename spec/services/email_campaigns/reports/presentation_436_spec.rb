require 'rails_helper'

# Epic integration spec groups both presenters in the assigned reports path.
RSpec.describe EmailCampaigns::Presentation do # rubocop:disable RSpec/SpecFilePathFormat
  describe EmailCampaigns::Presentation::Hygiene do
    let(:campaign) { create(:email_campaign) }

    it 'reconciles unsent classifications, historical sends and original issue rows without double counting' do
      create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid',
                                        preflight_checked_at: Time.current, preflight_valid_until: 1.day.from_now)
      protected_row = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
      EmailSuppression.create!(account: campaign.account, email: protected_row.email, reason: 'manual')
      %w[invalid review unknown unchecked].each do |status|
        create(:email_campaign_recipient, email_campaign: campaign, preflight_status: status)
      end
      create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.day.ago)
      create(:email_campaign_recipient, email_campaign: campaign, status: :sent, sent_at: 1.day.ago, preflight_status: 'valid')
      campaign.email_campaign_import_issues.create!(row_number: 2, raw_address: 'duplicate@example.org', reason_code: 'duplicate')
      result = described_class.new(campaign).call
      expect(result[:counts]).to eq(total: 7, ready: 1, protected: 1, invalid: 1, review: 1, unknown: 1, unchecked: 2)
      expect(result).to include(historical_sent: 1, recipients_total: 8, issues_count: 1, can_recheck: false)
    end

    it 'uses the exact blocked UI status for protected unsent recipients' do
      create(:email_campaign_recipient, email_campaign: campaign, status: :suppressed)
      expect(described_class.new(campaign).call).to include(status: 'blocked', counts: {
                                                              total: 1, ready: 0, protected: 1, invalid: 0, review: 0, unknown: 0, unchecked: 0
                                                            })
    end

    it 'does not describe preflight verdicts as enforcement in shadow or warning' do
      create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'invalid')
      %w[shadow warning].each do |mode|
        with_modified_env EMAIL_CAMPAIGN_HYGIENE_MODE: mode do
          expect(described_class.new(campaign).call).to include(mode: mode, status: 'review', analysis_only: true)
        end
      end
    end

    it 'only advertises rechecking to an administrator of this tenant' do
      admin = create(:user, account: campaign.account, role: :administrator)
      agent = create(:user, account: campaign.account, role: :agent)
      expect(described_class.new(campaign, actor: admin).call[:can_recheck]).to be(true)
      expect(described_class.new(campaign, actor: agent).call[:can_recheck]).to be(false)
      expect(described_class.new(campaign, actor: create(:user)).call[:can_recheck]).to be(false)
    end

    it 'keeps stable no-TTL verdicts for review and requires checked, unexpired evidence for ready' do
      create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.day.from_now)
      create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_checked_at: Time.current)
      { 'unknown' => 'dns_disabled', 'review' => 'provider_typo', 'invalid' => 'invalid_email' }.each do |status, reason|
        create(:email_campaign_recipient, email_campaign: campaign, preflight_status: status,
                                          preflight_reason_code: reason, preflight_checked_at: Time.current)
      end
      expect(EmailCampaigns::RecipientPreflightJob).not_to receive(:enqueue)
      with_modified_env EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false' do
        expect(described_class.new(campaign).call[:counts]).to eq(
          total: 5, ready: 0, protected: 0, invalid: 1, review: 1, unknown: 1, unchecked: 2
        )
      end
    end
  end

  describe EmailCampaigns::Presentation::Recipients do
    let(:campaign) { create(:email_campaign) }

    it 'uses batched classification, omits provider payload and other-tenant suppression' do
      recipient = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, custom_data: { private: 'never expose' })
      recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' }, private: 'never expose' })
      EmailSuppression.create!(account: create(:account), email: recipient.email, reason: 'hard_bounce')
      result = described_class.new(campaign, [recipient]).call.first
      expect(result).to include(delivery_outcome: 'permanent', reason_code: 'permanent_failure', suppression_reason: nil)
      expect(result).not_to have_key(:payload)
      expect(result).not_to have_key(:custom_data)
      expect(result).not_to have_key(:last_error)
      expect(result.to_json).not_to include('never expose')
    end

    it 'presents NoEmail and global Suppressed truthfully using the shared classifier' do
      rows = %w[NoEmail Suppressed UnsubscribedRecipient].map do |subtype|
        row = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced)
        row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
        row
      end
      outcomes = described_class.new(campaign, rows).call.map { |row| row.slice(:delivery_outcome, :reason_code) }
      expect(outcomes).to eq([
                               { delivery_outcome: 'permanent', reason_code: 'permanent_failure' },
                               { delivery_outcome: 'permanent', reason_code: 'provider_suppression' },
                               { delivery_outcome: 'unknown', reason_code: 'unsubscribe' }
                             ])
    end

    it 'does not expose expired temporary protection as active' do
      recipient = create(:email_campaign_recipient, email_campaign: campaign)
      EmailSuppressionState.create!(account: campaign.account, email: recipient.email, reason: 'temporary_failure',
                                    active: true, expires_at: 1.hour.ago)
      expect(described_class.new(campaign, [recipient]).call.first[:suppression_reason]).to be_nil
    end

    it 'keeps legacy strong reasons after a newer temporary state and bounds unknown legacy reasons' do
      rows = %w[unsubscribe complaint manual old_free_text].map do |reason|
        recipient = create(:email_campaign_recipient, email_campaign: campaign)
        EmailSuppression.create!(account: campaign.account, email: recipient.email, reason: reason)
        EmailSuppressionState.create!(account: campaign.account, email: recipient.email, reason: 'temporary_failure',
                                      active: true, expires_at: 1.day.from_now)
        recipient
      end
      expect(described_class.new(campaign, rows).call.pluck(:suppression_reason)).to eq(
        %w[unsubscribe complaint manual legacy_suppression]
      )
    end

    it 'reads suppression again per batch and never releases a legacy opt-out when temporary state expires' do
      recipient = create(:email_campaign_recipient, email_campaign: campaign)
      state = EmailSuppressionState.create!(account: campaign.account, email: recipient.email, reason: 'temporary_failure',
                                            active: true, expires_at: 1.day.from_now)
      presenter = described_class.new(campaign, [recipient])
      expect(presenter.call.first[:suppression_reason]).to eq('temporary_failure')
      EmailSuppression.create!(account: campaign.account, email: recipient.email, reason: 'unsubscribe')
      state.update!(expires_at: 1.hour.ago)
      expect(presenter.call.first[:suppression_reason]).to eq('unsubscribe')
    end

    it 'does not query suppression with an empty batch' do
      expect(EmailSuppression).not_to receive(:blocking_reasons_for)
      expect(described_class.new(campaign, []).call).to eq([])
    end

    it 'bounds batch reads without loading a belongs-to association per recipient' do
      rows = create_list(:email_campaign_recipient, 5, email_campaign: campaign)
      campaign.account
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i) && payload[:name] != 'SCHEMA'
      end
      begin
        described_class.new(campaign, rows).call
        expect(queries.length).to eq(4)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end
end
