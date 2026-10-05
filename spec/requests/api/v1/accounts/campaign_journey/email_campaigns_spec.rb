require 'rails_helper'

# #999: e-mail inside the campaign journey (contract in docs/campaigns/publicos/api-999.md).
# POST /campaign_journey/campaigns with channel "email" creates a draft linked to the audience whose
# recipients come from the audience contacts (N2, PRD §8.6), and every e-mail lock of today still
# applies to it (§6.9, L1–L4). Senders are doubles: no real e-mail leaves.
RSpec.describe 'Campaign journey e-mail campaigns (#999)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:identity) { create(:email_sender_identity, account: account, domain: 'empresa.com.br', from_email: 'ola@empresa.com.br') }
  let(:replies_inbox) { create(:channel_email, account: account, email: 'respostas@empresa.com.br').inbox }
  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => 3 } }
  let(:content) do
    "Nome,Celular,Email,Empresa,Vencimento\n" \
      "Ana Souza,11987654321,ana@alfa.com.br,Alfa Corretora,10/2026\n" \
      "Bia Lima,21987654321,,Beta Seguros,\n" \
      "Caio Reis,,caio@gama.com.br,,\n" \
      "Dani Melo,,dani@sup.com.br,,\n" \
      "Eva Rocha,,eva@out.com.br,,\n"
  end
  let(:audience) { saved_audience(account: account, user: user, content: content, mapping: mapping) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
  end

  def create_email_campaign(audience_id: audience.id, **campaign)
    body = { campaign_import_id: audience_id, channel: 'email',
             campaign: { title: 'Novidades de outubro', delivery_mode: 'ses', sender_identity_id: identity.id,
                         from_name: 'Empresa', from_email: 'ola@empresa.com.br', reply_to_inbox_id: replies_inbox.id }.merge(campaign) }
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns", params: body, headers: { 'api_access_token' => user.access_token.token },
                                                                      as: :json
  end

  def created_campaign
    EmailCampaign.find(response.parsed_body['id'])
  end

  # Bia already existed with an e-mail of her own; her row only has a phone. Caio changed his
  # e-mail after the import. Dani unsubscribed. Eva refused active messages.
  def prepare_contacts
    create(:contact, account: account, name: 'Bia Lima', phone_number: '+5521987654321', email: 'bia@antigo.com.br')
    audience
    account.contacts.find_by(name: 'Caio Reis').update!(email: 'caio@novo.com.br')
    EmailSuppression.create!(account: account, email: 'dani@sup.com.br', reason: 'unsubscribe', source: 'link')
    account.contacts.find_by(name: 'Eva Rocha').update_columns(opted_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def make_ready(campaign)
    campaign.update!(subject: 'Oi {{ primeiro_nome }}', body_html: '<p>{{ empresa }}</p><a href="{{ unsubscribe_url }}">Sair</a>')
    campaign.email_campaign_recipients.update_all(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now) # rubocop:disable Rails/SkipsModelValidations
    campaign
  end

  describe 'creating the e-mail draft (N2, PRD §8.6)' do
    it 'links the audience and takes as recipients only the contacts whose row brought their current e-mail' do
      prepare_contacts
      # The audience e-mail count follows the same rule (rows that brought an e-mail; Bia's has none).
      expect(audience.reload.channels['email']).to eq('enabled' => true, 'count' => 4)

      create_email_campaign

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      campaign = created_campaign
      expect(payload).to include('channel' => 'email', 'title' => 'Novidades de outubro', 'status' => 'draft', 'delivery_mode' => 'ses',
                                 'reply_to_inbox_id' => replies_inbox.id, 'recipients_count' => 1, 'suppressed_count' => 1)
      expect(campaign).to be_draft
      expect(campaign.reply_to_inbox).to eq(replies_inbox)
      expect(CampaignAudienceLink.for_campaign(campaign).campaign_import).to eq(audience)

      rows = campaign.email_campaign_recipients.order(:email).map { |r| [r.email, r.status, r.contact&.name] }
      expect(rows).to eq([['ana@alfa.com.br', 'pending', 'Ana Souza'], ['dani@sup.com.br', 'suppressed', 'Dani Melo']])
      ana = campaign.email_campaign_recipients.find { |r| r.email == 'ana@alfa.com.br' }
      expect(ana.custom_data).to include('primeiro_nome' => 'Ana', 'empresa' => 'Alfa Corretora', 'vencimento' => '10/2026')
      expect(EmailCampaigns::TemplateValidator.new(campaign).available).to include('primeiro_nome', 'empresa', 'vencimento')
      expect(EmailCampaigns::RecipientPreflightJob).to have_received(:enqueue).with(campaign.id)
    end

    it 'materializes nothing when the audience e-mail channel is off (fails closed) and is idempotent' do
      create_email_campaign
      campaign = created_campaign
      expect(CampaignJourney::EmailAudienceRecipients.new(campaign).materialize!).to eq(0)

      audience.update!(channels: audience.channels.merge('email' => { 'enabled' => false, 'count' => 5 }))
      expect(CampaignJourney::EmailAudienceRecipients.candidates(audience)).to eq([])
    end

    # J4: the API refuses a channel the audience does not have.
    it 'refuses an audience without e-mail, or with the e-mail channel off, with channel_not_in_audience' do
      phones_only = saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\n")
      create_email_campaign(audience_id: phones_only.id)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('channel_not_in_audience')

      audience.update!(channels: audience.channels.merge('email' => { 'enabled' => false, 'count' => 4 }))
      create_email_campaign
      expect(response.parsed_body['code']).to eq('channel_not_in_audience')
      expect(EmailCampaign.where(account: account).count).to eq(0)
    end

    it 'refuses an invalid sender or reply inbox with invalid_campaign, and a disabled e-mail feature with channel_not_connected' do
      create_email_campaign(sender_identity_id: nil)
      expect(response.parsed_body['code']).to eq('invalid_campaign')

      create_email_campaign(reply_to_inbox_id: create(:inbox, account: account).id)
      expect(response.parsed_body['code']).to eq('invalid_campaign')

      allow(EmailCampaigns::Config).to receive(:enabled?).and_return(false)
      create_email_campaign
      expect(response.parsed_body['code']).to eq('channel_not_connected')
      expect(EmailCampaign.where(account: account).count).to eq(0)
      expect(CampaignAudienceLink.count).to eq(0)
    end

    it 'creates a direct inbox draft' do
      sender_inbox = create(:channel_email, account: account, email: 'vendas@empresa.com.br').inbox

      create_email_campaign(delivery_mode: 'direct_inbox', sender_inbox_id: sender_inbox.id, sender_identity_id: nil)

      expect(response).to have_http_status(:ok)
      expect(created_campaign).to have_attributes(delivery_mode: 'direct_inbox', sender_inbox: sender_inbox, from_email: 'vendas@empresa.com.br')
    end

    it 'refuses a spreadsheet of recipients on a campaign linked to an audience' do
      create_email_campaign
      campaign = created_campaign
      file = Rack::Test::UploadedFile.new(StringIO.new("email\nx@y.com\n"), 'text/csv', original_filename: 'lista.csv')

      post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/recipients",
           params: { import_file: file }, headers: { 'api_access_token' => user.access_token.token }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('email_campaign.audience_linked')
      expect(campaign.email_campaign_imports.count).to eq(0)
    end
  end

  # Fails closed: a draft whose audience e-mail channel was turned off cannot be sent or scheduled.
  describe 'audience e-mail channel turned off after the draft' do
    let(:campaign) do
      prepare_contacts
      create_email_campaign
      make_ready(created_campaign)
    end

    it 'blocks send_now, schedule and the readiness list; a scheduled campaign keeps the channel on' do
      expect(campaign.sendable?).to be(true)
      audience.update!(channels: audience.channels.merge('email' => { 'enabled' => false, 'count' => 4 }))

      expect(campaign.reload.sendable?).to be(false)
      expect(EmailCampaigns::Presentation::SendReadiness.new(campaign).call).to include(can_send: false)
      expect(EmailCampaigns::Presentation::SendReadiness.new(campaign).call[:checks]).to include(audience_channel: false)
      post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/send_now",
           headers: { 'api_access_token' => user.access_token.token }, as: :json
      expect(response.parsed_body['error']).to eq('email_campaign.not_sendable')

      audience.update!(channels: audience.channels.merge('email' => { 'enabled' => true, 'count' => 4 }))
      expect(campaign.reload.schedule!(scheduled_at: 1.day.from_now)).to be_truthy
      with_modified_env(CAMPAIGN_IMPORT_ENABLED: 'true') do
        patch "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}/channels",
              params: { email: false }, headers: { 'api_access_token' => user.access_token.token }, as: :json
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'audience_in_use',
                                              'campaigns' => [{ 'title' => 'Novidades de outubro', 'display_id' => nil }])
    end
  end

  # L1: each item of the readiness list blocks the journey campaign exactly as today.
  describe 'readiness locks on an audience campaign (L1)' do
    let(:campaign) do
      prepare_contacts
      create_email_campaign
      created_campaign
    end

    def checks(target = campaign)
      EmailCampaigns::Presentation::SendReadiness.new(target.reload).call
    end

    it 'is ready only with subject, content, sender, recipients, finished import, hygiene and provider' do
      expect(checks[:checks]).to include(subject: false, content: false, sender: true, recipients: true, import: true)
      expect(checks[:can_send]).to be(false)
      expect(campaign.sendable?).to be(false)

      make_ready(campaign)
      expect(checks).to include(can_send: true, eligible_recipients: 1)
    end

    it 'blocks on the sender, the recipients and an active import' do
      make_ready(campaign)

      identity.update!(status: :pending)
      expect(checks[:checks]).to include(sender: false)
      identity.update!(status: :verified)

      EmailSuppression.create!(account: account, email: 'ana@alfa.com.br', reason: 'hard_bounce', source: 'ses')
      expect(checks[:checks]).to include(recipients: false)
      EmailSuppression.where(account: account).delete_all

      campaign.email_campaign_imports.create!
      expect(checks[:checks]).to include(import: false)
      expect(campaign.reload.sendable?).to be(false)
    end

    it 'blocks on hygiene in enforce mode while an address is not validated' do
      make_ready(campaign)
      campaign.email_campaign_recipients.update_all(preflight_status: 'unchecked', preflight_valid_until: nil) # rubocop:disable Rails/SkipsModelValidations

      with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce') do
        expect(checks[:checks]).to include(hygiene: false)
        expect(checks[:can_send]).to be(false)
      end
    end

    it 'refuses send_now while not ready' do
      post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/send_now",
           headers: { 'api_access_token' => user.access_token.token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('email_campaign.not_sendable')
      expect(campaign.reload).to be_draft
    end
  end

  # L2: provider reputation blocks (bounce ≥ 5%, complaint ≥ 0.1%, or unknown data) and says why.
  describe 'provider reputation on an audience campaign (L2)' do
    let(:campaign) do
      prepare_contacts
      create_email_campaign
      make_ready(created_campaign)
    end

    def send_now
      post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/send_now",
           headers: { 'api_access_token' => user.access_token.token }, as: :json
    end

    it 'keeps the thresholds of today' do
      config = EmailCampaigns::Reputation::ProviderConfig.new
      expect([config.bounce_ratio, config.complaint_ratio, config.unknown_action]).to eq([0.05, 0.001, 'block'])
    end

    it 'blocks the send with the reason when the provider is blocked' do
      EmailProviderState.create!(provider_key: EmailCampaigns::Reputation::ProviderConfig.new.provider_key, status: 'blocked', blocked: true)

      send_now

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('email_campaign.protected')
      expect(response.parsed_body.dig('protection', 'code')).to eq('provider_blocked')
      expect(campaign.reload).to be_draft
    end

    it 'blocks the send when the provider data is unknown' do
      with_modified_env(EMAIL_REPUTATION_PROVIDER_MONITOR: 'true', EMAIL_REPUTATION_AWS_ACCOUNT_ID: '123456789012') { send_now }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('protection', 'code')).to eq('provider_telemetry_unknown')
    end

    it 'sends to the audience contacts when healthy, with the reply inbox and one-click unsubscribe (L3)' do
      delivered = []
      sender = instance_double(EmailCampaigns::Ses::Sender)
      allow(sender).to receive(:deliver) { |**args| delivered << args and 'ses-1' }
      allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)

      send_now
      expect(response).to have_http_status(:ok)
      engine = EmailCampaigns::DeliveryEngine.new(campaign)
      allow(engine).to receive(:sleep)
      engine.perform

      expect(delivered.size).to eq(1)
      mail = delivered.first
      expect(mail).to include(to: 'ana@alfa.com.br', subject: 'Oi Ana', reply_to: 'respostas@empresa.com.br')
      expect(mail[:headers]['List-Unsubscribe']).to include('/email_campaigns/u/')
      expect(mail[:headers]['List-Unsubscribe-Post']).to eq('List-Unsubscribe=One-Click')
      expect(mail[:html_body]).to include('Alfa Corretora')
      expect(campaign.reload).to be_sent
      expect(campaign.email_campaign_recipients.find { |r| r.email == 'ana@alfa.com.br' }.sent_at).to be_present
    end
  end

  # L3: the unsubscribe footer stays locked in what the editor and the AI produce.
  it 'keeps the locked unsubscribe footer in the e-mail designs (L3)' do
    mjml = '<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>'
    footer = EmailCampaigns::Ai::Sanitizer.new(mjml).perform
    expect(footer).to include('footer-locked', '{{ unsubscribe_url }}')
  end

  # L4: the direct inbox send keeps business hours, the daily cap and the automatic pause.
  describe 'direct inbox limits on an audience campaign (L4)' do
    let(:sender_inbox) { create(:channel_email, account: account, email: 'vendas@empresa.com.br').inbox }
    let(:campaign) do
      prepare_contacts
      create_email_campaign(delivery_mode: 'direct_inbox', sender_inbox_id: sender_inbox.id, sender_identity_id: nil)
      make_ready(created_campaign).tap { |c| c.update_columns(status: EmailCampaign.statuses[:sending]) } # rubocop:disable Rails/SkipsModelValidations
    end
    let(:direct_sender) { instance_double(EmailCampaigns::DirectInbox::Sender, deliver: 'direct-1') }

    before do
      allow(EmailCampaigns::DirectInbox::Sender).to receive(:new).and_return(direct_sender)
      allow(EmailCampaigns::DirectInbox::TickJob).to receive(:set).and_return(EmailCampaigns::DirectInbox::TickJob)
      allow(EmailCampaigns::DirectInbox::TickJob).to receive(:perform_later)
    end

    def tick
      EmailCampaigns::DirectInbox::DeliveryEngine.new(campaign).tick
    end

    it 'does not send outside business hours and sends inside them' do
      travel_to(Time.zone.parse('2026-10-04 12:00 -03:00')) { tick } # Sunday
      expect(direct_sender).not_to have_received(:deliver)

      travel_to(Time.zone.parse('2026-10-05 10:00 -03:00')) { tick } # Monday
      expect(direct_sender).to have_received(:deliver).once
    end

    it 'stops at the daily cap of the inbox' do
      other = create(:email_campaign, account: account, delivery_mode: :direct_inbox, sender_inbox: sender_inbox, sender_identity: nil,
                                      status: :sent)
      travel_to(Time.zone.parse('2026-10-05 10:00 -03:00')) do
        rows = Array.new(EmailCampaigns::DirectInbox::Limits::DEFAULT_DAILY_CAP) do |i|
          { email_campaign_id: other.id, email: "lote#{i}@x.com.br", status: 1, sent_at: 1.hour.ago, created_at: Time.current,
            updated_at: Time.current }
        end
        EmailCampaignRecipient.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations
        tick
      end
      expect(direct_sender).not_to have_received(:deliver)
    end

    it 'pauses by itself after consecutive failures' do
      3.times do |i|
        create(:email_campaign_recipient, email_campaign: campaign, email: "falha#{i}@x.com.br", status: :failed)
      end

      travel_to(Time.zone.parse('2026-10-05 10:00 -03:00')) { tick }

      expect(direct_sender).not_to have_received(:deliver)
      expect(campaign.reload).to be_paused
      expect(campaign.pause_reason).to include('code' => 'direct_inbox_autopause')
    end
  end
end
