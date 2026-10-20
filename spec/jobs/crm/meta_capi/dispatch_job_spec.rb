require 'rails_helper'

RSpec.describe Crm::MetaCapi::DispatchJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:activity_id) { 42 }

  let(:campaign_attributes) { { 'campaign' => { 'ctwa_clid' => 'CLID123' } } }
  let(:pipeline_metadata) { { 'meta_sync' => { 'enabled' => true } } }
  let(:provider_config) do
    { 'api_key' => 'test_key', 'business_account_id' => '111', 'meta_dataset' => { 'waba_id' => '111', 'id' => 'DS123' } }
  end

  # The factory merges its own api_key/business_account_id over provider_config, so the
  # config under test is written after creation.
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      .tap { |created| created.update_columns(provider_config: provider_config) } # rubocop:disable Rails/SkipsModelValidations
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, additional_attributes: campaign_attributes) }
  let(:pipeline) { account.crm_pipelines.create!(name: 'P', created_by: user, status: :active, metadata: pipeline_metadata) }
  let(:stage) do
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'S', position: 0, metadata: { 'funnel_stage_type' => 'qualified' })
  end
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL',
                              value_cents: 50_000, primary_conversation: conversation)
  end

  let(:event_id) { "crm-#{card.id}-won-#{activity_id}" }

  def perform
    described_class.perform_now(account.id, card.id, activity_id, 'won')
  end

  it 'returns without a ledger row when the card no longer exists' do
    expect { described_class.perform_now(account.id, 0, activity_id, 'won') }
      .not_to change(Crm::MetaConversionEvent, :count)
  end

  describe 'skip paths' do
    context 'when the conversation carries no ctwa_clid' do
      let(:campaign_attributes) { {} }

      it 'marks the ledger row skipped and never calls the Meta client' do
        expect(Meta::ConversionsApiClient).not_to receive(:new)

        perform
        row = Crm::MetaConversionEvent.find_by(event_id: event_id)

        expect(row.status).to eq('skipped')
        expect(row.error_message).to eq('missing_ctwa_clid')
      end
    end

    context 'when the dataset lookup fails at Meta (#1940)' do
      let(:provider_config) { { 'api_key' => 'test_key', 'business_account_id' => '111' } }

      before do
        result = Meta::WabaDatasetClient::Result.new(error: 'rate limited', transient: true)
        allow(Meta::WabaDatasetClient).to receive(:new).and_return(instance_double(Meta::WabaDatasetClient, find_or_create: result))
      end

      it 'records an error row and re-raises so the retry can claim it again' do
        expect(Meta::ConversionsApiClient).not_to receive(:new)

        expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)
        row = Crm::MetaConversionEvent.find_by(event_id: event_id)

        expect(row.status).to eq('error')
        expect(row.error_message).to eq('dataset_lookup: rate limited')
      end
    end

    context 'when Meta refuses the token or the permission (#1940)' do
      let(:provider_config) { { 'api_key' => 'test_key', 'business_account_id' => '111' } }

      before do
        result = Meta::WabaDatasetClient::Result.new(error: 'meta_error_190: expired', transient: false, access_denied: true)
        allow(Meta::WabaDatasetClient).to receive(:new).and_return(instance_double(Meta::WabaDatasetClient, find_or_create: result))
      end

      it 'skips as missing_credentials, without retrying' do
        expect { perform }.not_to raise_error

        expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'skipped', error_message: 'missing_credentials')
      end
    end

    context 'when Meta fails the lookup for good for another reason (#1940)' do
      let(:provider_config) { { 'api_key' => 'test_key', 'business_account_id' => '111' } }

      before do
        result = Meta::WabaDatasetClient::Result.new(error: 'meta_error_100: unsupported', transient: false)
        allow(Meta::WabaDatasetClient).to receive(:new).and_return(instance_double(Meta::WabaDatasetClient, find_or_create: result))
      end

      it 'skips with missing_dataset instead of retrying for weeks' do
        expect { perform }.not_to raise_error

        expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'skipped', error_message: 'missing_dataset')
      end
    end

    context 'when Meta answers without a dataset (#1940)' do
      let(:provider_config) { { 'api_key' => 'test_key', 'business_account_id' => '111' } }

      before do
        allow(Meta::WabaDatasetClient).to receive(:new)
          .and_return(instance_double(Meta::WabaDatasetClient, find_or_create: Meta::WabaDatasetClient::Result.new))
      end

      it 'marks the ledger row skipped for a missing dataset, not missing credentials' do
        expect(Meta::ConversionsApiClient).not_to receive(:new)

        perform
        row = Crm::MetaConversionEvent.find_by(event_id: event_id)

        expect(row.status).to eq('skipped')
        expect(row.error_message).to eq('missing_dataset')
      end

      it 'persists the deterministic card context on the skipped row' do
        perform
        row = Crm::MetaConversionEvent.find_by(event_id: event_id)

        expect(row).to have_attributes(
          account_id: account.id,
          card_id: card.id,
          pipeline_id: pipeline.id,
          event_type: 'won',
          source: 'live',
          funnel_stage_type: 'qualified',
          value_cents: 50_000,
          currency: 'BRL'
        )
      end
    end

    context 'when the WhatsApp channel has no WABA id' do
      let(:provider_config) { { 'api_key' => 'test_key' } }

      it 'marks the ledger row skipped for missing credentials' do
        perform

        expect(Crm::MetaConversionEvent.find_by(event_id: event_id).error_message).to eq('missing_credentials')
      end
    end

    context 'when the linked channel exposes no access token' do
      # Only an official WhatsApp inbox carries a Meta token; a click seen in an API inbox cannot be reported.
      let(:conversation) do
        inbox = create_crm_inbox(account: account)
        create(:conversation, account: account, inbox: inbox, additional_attributes: campaign_attributes)
      end

      it 'marks the ledger row skipped for missing credentials' do
        perform
        row = Crm::MetaConversionEvent.find_by(event_id: event_id)

        expect(row.status).to eq('skipped')
        expect(row.error_message).to eq('missing_credentials')
      end
    end
  end

  describe 'idempotency' do
    it 'short-circuits when a row for the same event_id is already accepted' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: event_id, event_type: 'won',
                                       status: :accepted, http_code: 200)
      expect(Meta::ConversionsApiClient).not_to receive(:new)

      expect { perform }.not_to change(Crm::MetaConversionEvent, :count)
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).status).to eq('accepted')
    end

    it 'short-circuits when a row is still pending (another worker owns the in-flight POST)' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: event_id, event_type: 'won',
                                       status: :pending)
      expect(Meta::ConversionsApiClient).not_to receive(:new)

      perform

      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).status).to eq('pending')
    end
  end

  describe 'delivery' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }

    before { allow(Meta::ConversionsApiClient).to receive(:new).and_return(client) }

    it 'posts the built event and records an accepted ledger row' do
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok', error: nil))

      perform
      row = Crm::MetaConversionEvent.find_by(event_id: event_id)

      expect(client).to have_received(:post_events) do |events|
        payload = events.first
        expect(payload['event_name']).to eq('Purchase')
        expect(payload['event_id']).to eq(event_id)
        expect(payload['user_data']).to include('ctwa_clid' => 'CLID123')
      end
      expect(row.status).to eq('accepted')
      expect(row.http_code).to eq(200)
      expect(row.sent_at).to be_present
    end

    it 'records an error row and re-raises when Meta rejects the event' do
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: false, http_code: 400, body: 'bad', error: 'invalid dataset'))

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)
      row = Crm::MetaConversionEvent.find_by(event_id: event_id)

      expect(row.status).to eq('error')
      expect(row.http_code).to eq(400)
      expect(row.error_message).to eq('invalid dataset')
    end

    it 'resolves the ctwa_clid from campaign touches when there is no origin campaign' do
      conversation.update!(additional_attributes: { 'campaign_touches' => [{ 'ctwa_clid' => 'TOUCH9' }] })
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok', error: nil))

      perform

      expect(client).to have_received(:post_events) do |events|
        expect(events.first['user_data']).to include('ctwa_clid' => 'TOUCH9')
      end
    end

    it "anchors 'moved' on the activity's destination stage and transition time, not the card's current stage" do
      destination = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Q', position: 1,
                                                        metadata: { 'funnel_stage_type' => 'negotiation' })
      activity = Crm::Activity.create!(account: account, card: card, event_type: 'move',
                                       payload: { 'to_stage_id' => destination.id }, created_at: 2.hours.ago)
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok', error: nil))

      described_class.perform_now(account.id, card.id, activity.id, 'moved')

      row = Crm::MetaConversionEvent.find_by(event_id: "crm-#{card.id}-moved-#{activity.id}")
      expect(row.funnel_stage_type).to eq('negotiation')
      expect(client).to have_received(:post_events) do |events|
        expect(events.first['event_name']).to eq('InitiateCheckout')
        expect(events.first['event_time']).to eq(activity.created_at.to_i)
      end
    end
  end

  describe 'dataset and inbox per conversation (#1940)' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }
    let(:ok) { Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok', error: nil) }

    def whatsapp_inbox(token:, waba:, dataset:)
      created = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      config = { 'api_key' => token, 'business_account_id' => waba, 'meta_dataset' => { 'waba_id' => waba, 'id' => dataset } }
      created.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
      created.inbox
    end

    before do
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events).and_return(ok)
    end

    it 'sends each card of the same funnel to the dataset of its own inbox WABA' do
      other_inbox = whatsapp_inbox(token: 'other_key', waba: '222', dataset: 'DS2')
      other_conversation = create(:conversation, account: account, inbox: other_inbox,
                                                 additional_attributes: { 'campaign' => { 'ctwa_clid' => 'CLID2' } })
      other_card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'B', currency: 'BRL',
                                             primary_conversation: other_conversation)

      perform
      described_class.perform_now(account.id, other_card.id, activity_id, 'won')

      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'test_key', dataset_id: 'DS123')
      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'other_key', dataset_id: 'DS2')
      expect(Crm::MetaConversionEvent.find_by(event_id: "crm-#{other_card.id}-won-#{activity_id}").dataset_id).to eq('DS2')
    end

    it 'goes out through the linked conversation that carries the click when the primary has none' do
      conversation.update!(additional_attributes: {})
      ad_inbox = whatsapp_inbox(token: 'ad_key', waba: '222', dataset: 'DS2')
      linked = create(:conversation, account: account, inbox: ad_inbox,
                                     additional_attributes: { 'campaign' => { 'ctwa_clid' => 'LINKED' } })
      Crm::CardConversation.create!(account: account, card: card, conversation: linked)

      perform

      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'ad_key', dataset_id: 'DS2')
      expect(client).to have_received(:post_events) do |events|
        expect(events.first['user_data']).to include('ctwa_clid' => 'LINKED', 'whatsapp_business_account_id' => '222')
      end
    end

    it 'looks the dataset up once and keeps it on the inbox' do
      channel.update_columns(provider_config: { 'api_key' => 'test_key', 'business_account_id' => '111', 'other' => 'kept' }) # rubocop:disable Rails/SkipsModelValidations
      dataset_client = instance_double(Meta::WabaDatasetClient, find_or_create: Meta::WabaDatasetClient::Result.new(dataset_id: 'NEW1'))
      allow(Meta::WabaDatasetClient).to receive(:new).and_return(dataset_client)

      perform
      described_class.perform_now(account.id, card.id, activity_id + 1, 'won')

      expect(Meta::WabaDatasetClient).to have_received(:new).with(access_token: 'test_key', waba_id: '111').once
      expect(channel.reload.provider_config).to include('meta_dataset' => { 'waba_id' => '111', 'id' => 'NEW1' }, 'other' => 'kept')
      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'test_key', dataset_id: 'NEW1').twice
    end
  end

  describe 'retry after a failed dataset lookup (#1940)' do
    let(:provider_config) { { 'api_key' => 'test_key', 'business_account_id' => '111' } }

    it 're-claims the error row and posts the event once' do
      client = instance_double(Meta::ConversionsApiClient)
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events).and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok'))
      dataset_client = instance_double(Meta::WabaDatasetClient)
      allow(Meta::WabaDatasetClient).to receive(:new).and_return(dataset_client)
      allow(dataset_client).to receive(:find_or_create).and_return(
        Meta::WabaDatasetClient::Result.new(error: 'timeout', transient: true),
        Meta::WabaDatasetClient::Result.new(dataset_id: 'DS1')
      )

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)
      perform

      expect(client).to have_received(:post_events).once
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'accepted', dataset_id: 'DS1')
    end
  end

  describe 'reauthorized onto another WABA (#1940)' do
    let(:provider_config) do
      { 'api_key' => 'test_key', 'business_account_id' => '333', 'meta_dataset' => { 'waba_id' => '111', 'id' => 'OLD' } }
    end

    it 'does not reuse the dataset kept for the previous WABA' do
      client = instance_double(Meta::ConversionsApiClient)
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events).and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok'))
      allow(Meta::WabaDatasetClient).to receive(:new)
        .and_return(instance_double(Meta::WabaDatasetClient, find_or_create: Meta::WabaDatasetClient::Result.new(dataset_id: 'DS333')))

      perform

      expect(Meta::WabaDatasetClient).to have_received(:new).with(access_token: 'test_key', waba_id: '333')
      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'test_key', dataset_id: 'DS333')
    end
  end

  describe 'security: token redaction' do
    let(:secret_token) { "EAAG#{'z' * 40}" }

    it 'never leaks a token-shaped secret into the log or the re-raised error' do
      allow(Crm::MetaConversionEvent).to receive(:find_or_initialize_by)
        .and_raise(StandardError.new("db down token=#{secret_token}"))
      # Replace Rails.logger wholesale so the job's Rails.logger.error writes to a buffer we
      # own, regardless of the app's custom logger proxy (identity-based stubs miss it).
      io = StringIO.new
      allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(io))

      raised = nil
      begin
        perform
      rescue StandardError => e
        raised = e
      end

      expect(raised.class.name).to eq('Crm::MetaCapi::DispatchJob::DispatchError')
      expect(raised.message).not_to include(secret_token)
      expect(io.string).to include('<REDACTED>')
      expect(io.string).not_to include(secret_token)
    end
  end
end
