require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientPreflightJob do # rubocop:disable RSpec/SpecFilePathFormat -- lease integration for this job
  let(:campaign) { create(:email_campaign) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    clear_enqueued_jobs
  end

  it 'coalesces enqueues and duplicate execution, then aggregates once at the end of a pass' do
    create_list(:email_campaign_recipient, 201, email_campaign: campaign)
    expect(described_class.enqueue(campaign.id)).to be true
    expect(described_class.enqueue(campaign.id)).to be false
    aggregates = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      sql = args.last.fetch(:sql)
      aggregates << sql if sql.include?('GROUP BY') && sql.include?('preflight_status')
    end
    first = enqueued_jobs.last.fetch(:args)
    described_class.perform_now(*first)
    expect(campaign.reload.preflight_summary).to eq({})
    count = enqueued_jobs.size
    described_class.perform_now(*first)
    expect(enqueued_jobs.size).to eq(count)
    described_class.perform_now(*enqueued_jobs.last.fetch(:args))
    expect(campaign.reload.preflight_summary).to eq({})
    described_class.perform_now(*enqueued_jobs.last.fetch(:args))
    expect(campaign.reload.preflight_summary).to eq('unknown' => 201)
    expect([campaign.preflight_lease_token, aggregates.size]).to eq([nil, 1])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it 'does no unchanged work across repeated maintenance cycles with DNS disabled' do
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') do
      create_list(:email_campaign_recipient, 101, email_campaign: campaign)
      perform_enqueued_jobs { described_class.enqueue(campaign.id) }
      timestamps = campaign.email_campaign_recipients.pluck(:preflight_checked_at)
      3.times do
        travel 10.minutes
        expect { EmailCampaigns::RecipientImportMaintenanceJob.perform_now }.not_to have_enqueued_job(described_class)
      end
      expect(campaign.email_campaign_recipients.pluck(:preflight_checked_at)).to eq(timestamps)
      expect(campaign.reload.preflight_summary).to eq('unknown' => 101)
    end
  end

  it 'recovers expired leases and fences stale holders from completing or replacing a summary' do
    create(:email_campaign_recipient, email_campaign: campaign)
    described_class.enqueue(campaign.id)
    stale = enqueued_jobs.last.fetch(:args)
    travel 6.minutes
    expect(described_class.enqueue(campaign.id)).to be true
    current = enqueued_jobs.last.fetch(:args)
    described_class.perform_now(*stale)
    expect(campaign.reload.preflight_summary).to eq({})
    described_class.perform_now(*current)
    expect(campaign.reload.preflight_summary).to eq('unknown' => 1)
    described_class.perform_now(*stale)
    expect(campaign.reload.preflight_summary).to eq('unknown' => 1)
  end

  it 'rechecks local results only after explicit request or DNS configuration changes' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign)
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') do
      perform_enqueued_jobs { described_class.enqueue(campaign.id) }
      expect(described_class.due.where(id: recipient.id)).not_to exist
      expect(described_class.enqueue(campaign.id, recheck: true)).to be true
      described_class.perform_now(*enqueued_jobs.last.fetch(:args))
    end
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'true') do
      expect(described_class.due.where(id: recipient.id)).to exist
    end
  end

  it 'fences a running holder after expiry and recovers a crash just before the final summary' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign)
    lease = EmailCampaigns::PreflightLease.new(campaign)
    queued = lease.acquire
    running = lease.claim(*queued).first
    recipient.update!(preflight_status: 'unknown', preflight_reason_code: 'dns_disabled', preflight_checked_at: Time.current)
    travel 6.minutes
    expect { EmailCampaigns::RecipientImportMaintenanceJob.perform_now }.to have_enqueued_job(described_class)
    expect(lease.advance(running, recipient.id)).to be_nil
    expect(campaign.reload.preflight_summary).to eq({})
    described_class.perform_now(*enqueued_jobs.last.fetch(:args))
    expect(campaign.reload.preflight_summary).to eq('unknown' => 1)
  end

  it 'resumes from the durable cursor after a continuation is lost' do
    create_list(:email_campaign_recipient, 101, email_campaign: campaign)
    described_class.enqueue(campaign.id)
    described_class.perform_now(*enqueued_jobs.last.fetch(:args))
    cursor = campaign.reload.preflight_cursor
    expect(cursor).to be_positive
    travel 6.minutes
    expect(described_class.enqueue(campaign.id)).to be true
    expect(enqueued_jobs.last.fetch(:args).last).to eq(cursor)
    described_class.perform_now(*enqueued_jobs.last.fetch(:args))
    expect(campaign.reload.preflight_summary).to eq('unknown' => 101)
  end

  it 'only schedules expired external evidence when DNS is enabled' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid',
                                                  preflight_reason_code: 'mx', preflight_valid_until: 1.minute.ago)
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') do
      expect(described_class.due.where(id: recipient.id)).not_to exist
    end
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'true') do
      expect(described_class.due.where(id: recipient.id)).to exist
    end
  end
end
