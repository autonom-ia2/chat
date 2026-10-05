require 'rails_helper'

# #999 adversarial review (M1–M3, B5, B6, B8–B10): each example failed before its fix.
RSpec.describe CampaignJourney::EmailAudienceGate, :aggregate_failures do
  around do |example|
    with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  let(:locked_tables) { %w[campaign_imports accounts email_campaigns] }
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:identity) { create(:email_sender_identity, account: account, domain: 'empresa.com.br', from_email: 'ola@empresa.com.br') }
  let(:audience) do
    saved_audience(account: account, user: user, mapping: { 'name' => 0, 'email' => 1 },
                   content: "Nome,Email\nAna Souza,ana@alfa.com.br\nCaio Reis,caio@gama.com.br\n")
  end
  let(:campaign) do
    created = CampaignJourney::EmailCampaignCreator.new(
      account: account, campaign_import: audience,
      attributes: { title: 'Novidades', sender_identity_id: identity.id, from_email: 'ola@empresa.com.br' }
    ).perform
    created.update!(subject: 'Oi', body_html: '<p>Oi</p>')
    created.email_campaign_recipients.update_all(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now) # rubocop:disable Rails/SkipsModelValidations
    created.reload
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
  end

  def caio
    account.contacts.find_by(name: 'Caio Reis')
  end

  def locked_tables_in_order(&)
    sql = []
    subscriber = ->(*args) { sql << args.last[:sql] if args.last[:sql].to_s.include?('FOR UPDATE') }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
    sql.filter_map { |statement| locked_tables.find { |table| statement.include?("\"#{table}\"") } }
  end

  # M1 + M3: the sync and the channel check run inside the delivery locks, taken in a fixed order:
  # the audience first (as the channel switch and the delete do), then the account.
  it 'locks the audience before the account on schedule and send now' do
    campaign
    order = locked_tables_in_order { expect(campaign.schedule!(scheduled_at: 1.day.from_now)).to be_truthy }
    expect(order.first(2)).to eq(%w[campaign_imports accounts])

    campaign.update_columns(status: EmailCampaign.statuses[:draft]) # rubocop:disable Rails/SkipsModelValidations
    order = locked_tables_in_order { expect(campaign.claim_for_sending!).to be(true) }
    expect(order.first(2)).to eq(%w[campaign_imports accounts])
  end

  # M1: a concurrent writer that added the same address cannot make the sync raise.
  it 'never raises on an address another writer already added' do
    campaign
    caio.update!(email: 'caio@novo.com.br')
    caio.update!(email: 'caio@gama.com.br')
    syncer = CampaignJourney::EmailAudienceRecipients.new(campaign)
    allow(syncer).to receive(:existing_emails).and_return(Set.new)

    expect(syncer.sync!).to eq(added: 0, removed: 0)
    expect(campaign.email_campaign_recipients.count).to eq(2)
  end

  # M1: a database error never puts an e-mail address in last_error.
  it 'keeps e-mail addresses out of last_error when the scheduler fails' do
    campaign.update!(status: :scheduled, scheduled_at: 1.minute.ago)
    error = ActiveRecord::RecordNotUnique.new('Key (email_campaign_id, lower(email))=(1, ana@alfa.com.br) already exists')
    allow(EmailCampaigns::PreflightDecision).to receive(:new).and_raise(error)

    EmailCampaigns::Scheduler.new.perform

    expect(campaign.reload).to be_failed
    expect(campaign.last_error).to include('<EMAIL>')
    expect(campaign.last_error).not_to include('@')
  end

  # M2: the scheduler syncs first; new people get the hygiene check and the send waits a tick.
  it 'defers a scheduled campaign whose list grew, without pausing it, and sends on the next tick' do
    campaign.update!(status: :scheduled, scheduled_at: 1.minute.ago)
    campaign.email_campaign_recipients.find_by!(email: 'caio@gama.com.br').delete
    allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)

    with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce') { EmailCampaigns::Scheduler.new.perform }

    expect(campaign.reload).to be_scheduled
    expect(campaign.hygiene_pause_reason).to be_nil
    expect(campaign.email_campaign_recipients.pluck(:email)).to include('caio@gama.com.br')
    expect(EmailCampaigns::RecipientPreflightJob).to have_received(:enqueue).with(campaign.id).at_least(:once)

    with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce') { EmailCampaigns::Scheduler.new.perform }
    expect(campaign.reload).to be_scheduled

    campaign.email_campaign_recipients.update_all(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now) # rubocop:disable Rails/SkipsModelValidations
    with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce') { EmailCampaigns::Scheduler.new.perform }
    expect(campaign.reload).to be_sending
    expect(EmailCampaigns::DeliveryJob).to have_received(:perform_later).with(campaign.id)
  end

  # M2: the readiness list says the list will change before the send.
  it 'tells in the readiness list how the audience list will change' do
    campaign.email_campaign_recipients.find_by!(email: 'caio@gama.com.br').delete

    result = EmailCampaigns::Presentation::SendReadiness.new(campaign.reload).call

    expect(result[:audience_list]).to eq(to_add: 1, to_remove: 0)
  end

  # B5: the domain's reply inbox must be an e-mail inbox of the same account.
  it 'refuses a domain reply inbox from another account or that is not e-mail' do
    other = create(:channel_email).inbox
    api_inbox = create(:inbox, account: account)

    expect(identity.update(reply_to_inbox_id: other.id)).to be(false)
    expect(identity.update(reply_to_inbox_id: api_inbox.id)).to be(false)
    expect(identity.update(reply_to_inbox_id: create(:channel_email, account: account).inbox.id)).to be(true)
  end

  # B6: an inbox address that is not a valid e-mail is never used as Reply-To.
  it 'ignores a reply inbox whose address is not a valid e-mail' do
    inbox = create(:channel_email, account: account).inbox
    campaign.update!(reply_to_inbox: inbox)
    inbox.channel.update_column(:email, 'not an address') # rubocop:disable Rails/SkipsModelValidations

    expect(EmailCampaigns::ReplyTo.for(campaign.reload)).to eq('ola@empresa.com.br')
  end

  # B8: values go into the HTML escaped and into the subject as plain text, old and journey campaigns.
  it 'escapes personalization values in the HTML body only' do
    old = create(:email_campaign, account: account, sender_identity: identity, status: :sending, from_email: 'ola@empresa.com.br',
                                  subject: 'Oi {{ empresa }}', body_html: '<p>{{ empresa }} {{ nome }}</p>')
    old_recipient = create(:email_campaign_recipient, email_campaign: old, name: 'Ana <b>', custom_data: { 'empresa' => 'A&B <script>' })
    renderer = EmailCampaigns::TemplateRenderer.new(old_recipient)
    expect(renderer.render(old.body_html, html: true)).to eq('<p>A&amp;B &lt;script&gt; Ana &lt;b&gt;</p>')
    expect(renderer.render(old.subject)).to eq('Oi A&B <script>')

    audience.update!(extra_columns: ['Plano'])
    caio.update!(name: 'Caio <i>')
    campaign.email_campaign_recipients.delete_all
    CampaignJourney::EmailAudienceRecipients.new(campaign.reload).sync!
    journey_recipient = campaign.email_campaign_recipients.find_by!(email: 'caio@gama.com.br')
    expect(EmailCampaigns::TemplateRenderer.new(journey_recipient).render('{{ primeiro_nome }}', html: true)).to eq('Caio')
    expect(EmailCampaigns::TemplateRenderer.new(journey_recipient).render('{{ nome }}', html: true)).to eq('Caio &lt;i&gt;')
  end

  it 'sends the escaped body through the delivery engine' do
    sender = instance_double(EmailCampaigns::Ses::Sender)
    delivered = []
    allow(sender).to receive(:deliver) { |**args| delivered << args and 'ses-1' }
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)
    allow(EmailCampaigns::Tracking::Injector).to receive(:new) do |_recipient, html|
      instance_double(EmailCampaigns::Tracking::Injector, perform: html)
    end
    campaign
    campaign.update!(body_html: '<p>{{ nome }}</p>', subject: '{{ nome }}')
    campaign.email_campaign_recipients.find_by!(email: 'caio@gama.com.br').update!(name: 'Caio <i>')
    campaign.update_columns(status: EmailCampaign.statuses[:sending]) # rubocop:disable Rails/SkipsModelValidations
    engine = EmailCampaigns::DeliveryEngine.new(campaign)
    allow(engine).to receive(:sleep)

    engine.perform

    caio_mail = delivered.find { |mail| mail[:to] == 'caio@gama.com.br' }
    expect(caio_mail[:html_body]).to include('<p>Caio &lt;i&gt;</p>')
    expect(caio_mail[:subject]).to eq('Caio <i>')
  end

  # B9: deleting the audience removes the pending recipients of the drafts that used it.
  it 'removes the pending recipients of linked drafts when the audience is deleted' do
    campaign
    sent = create(:email_campaign, account: account, sender_identity: identity, status: :sent, from_email: 'ola@empresa.com.br')
    CampaignAudienceLink.create!(account: account, campaign: sent, campaign_import: audience)
    kept = create(:email_campaign_recipient, email_campaign: sent, status: :sent, sent_at: 1.day.ago)
    expect(campaign.email_campaign_recipients.count).to eq(2)

    CampaignImports::AudienceDeletion.new(audience).perform

    expect(campaign.email_campaign_recipients.count).to eq(0)
    expect(kept.reload).to be_present
  end

  # B10: the "has events" check only looks at this campaign's recipients.
  it 'restricts the events subquery to the campaign recipients' do
    campaign
    sql = []
    subscriber = ->(*args) { sql << args.last[:sql] if args.last[:sql].to_s.include?('email_events') }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      CampaignJourney::EmailAudienceRecipients.new(campaign).sync!
    end

    expect(sql).not_to be_empty
    # The outer query filters by campaign; the events subquery must too (two filters, not one).
    expect(sql.map { |statement| statement.scan('email_campaign_id').size }).to all(be >= 2)
  end
end
