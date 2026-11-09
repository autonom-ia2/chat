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
  # Clicks without touched_at date from the conversation start, and only clicks made by the
  # event count (#2738): the conversation starts before the events under test, as in real life.
  let(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, additional_attributes: campaign_attributes, created_at: 1.day.ago)
  end
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

    it 'ends an old pending row as an error without posting it again (#2738)' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: event_id, event_type: 'won',
                                       status: :pending, updated_at: 11.minutes.ago)
      expect(Meta::ConversionsApiClient).not_to receive(:new)

      expect { perform }.not_to raise_error

      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'error', error_message: 'unknown_outcome')
    end

    it 'never posts again an event whose outcome at Meta is unknown (#2738)' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: event_id, event_type: 'won',
                                       status: :error, error_message: 'unknown_outcome')
      expect(Meta::ConversionsApiClient).not_to receive(:new)

      perform

      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).status).to eq('error')
    end
  end

  describe 'answer from Meta that may or may not have arrived (#2738)' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }

    before do
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: false, error: 'Net::ReadTimeout', unknown_outcome: true))
    end

    it 'marks the row as an error with the reason and does not retry, so the sale is never counted twice' do
      expect { perform }.not_to raise_error

      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'error', error_message: 'unknown_outcome')

      perform

      expect(client).to have_received(:post_events).once
    end
  end

  # #2799 (Rodrigo, 09/11): a 5xx from Meta is a doubt like a read timeout. Meta may have kept
  # the event, and it does not dedup, so it is not sent again: the card says it is unknown.
  describe 'server error from Meta (5xx)' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }

    before do
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: false, http_code: 503, error: 'unavailable', error_code: 2, unknown_outcome: true))
    end

    it 'marks the outcome unknown, keeps the HTTP code and never posts it again' do
      expect { perform }.not_to raise_error

      expect(Crm::MetaConversionEvent.find_by(event_id: event_id))
        .to have_attributes(status: 'error', error_message: 'unknown_outcome', http_code: 503)

      perform

      expect(client).to have_received(:post_events).once
    end

    it 'does not look for another dataset nor post again when the 5xx body says 100/33' do
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: false, http_code: 500, error_code: 100, error_subcode: 33, unknown_outcome: true))
      allow(Crm::MetaCapi::WabaDataset).to receive(:replacement)

      expect { perform }.not_to raise_error

      expect(Crm::MetaCapi::WabaDataset).not_to have_received(:replacement)
      expect(client).to have_received(:post_events).once
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).error_message).to eq('unknown_outcome')
    end
  end

  # A won card without closed_at: the cut and event_time come from the activity that logged the
  # win, not from "now", which would move on every retry (#2799).
  describe 'won card without a close instant' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }
    let(:won_at) { 3.hours.ago.change(usec: 0) }
    let(:activity_id) { Crm::Activity.create!(account: account, card: card, event_type: 'won', created_at: won_at).id }

    before do
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events).and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200))
    end

    it 'sends the time of the win and ignores a click made after it' do
      later = { 'ctwa_clid' => 'LATER', 'touched_at' => 1.hour.ago.iso8601 }
      conversation.update!(additional_attributes: campaign_attributes.merge('campaign_touches' => [later]))
      card.update_columns(closed_at: nil) # rubocop:disable Rails/SkipsModelValidations

      perform

      expect(client).to have_received(:post_events) do |events|
        expect(events.sole).to include('event_time' => won_at.to_i)
        expect(events.sole['user_data']).to include('ctwa_clid' => 'CLID123')
      end
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

  describe 'unexpected failure after claiming the row (#2738)' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }
    let(:ok) { Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok') }

    before do
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events).and_return(ok)
    end

    it 'turns the row into an error with the reason, so the retry claims it and posts once' do
      calls = 0
      allow(Crm::MetaCapi::PayloadBuilder).to receive(:build).and_wrap_original do |original, **args|
        calls += 1
        raise NoMethodError, 'boom' if calls == 1

        original.call(**args)
      end

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id))
        .to have_attributes(status: 'error', error_message: 'unexpected: NoMethodError')
      expect(client).not_to have_received(:post_events)

      perform

      expect(client).to have_received(:post_events).once
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).status).to eq('accepted')
    end

    it 'keeps an event Meta already accepted as accepted, so the retry never posts it twice' do
      allow_any_instance_of(Crm::MetaConversionEvent).to receive(:update!).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
        raise ActiveRecord::ConnectionNotEstablished, 'db gone' if (args.first || kwargs)[:status] == :accepted

        original.call(*args, **kwargs)
      end

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'accepted', http_code: 200)

      perform

      expect(client).to have_received(:post_events).once
    end

    it 'keeps an unknown outcome when recording it fails, so the retry never posts it twice' do
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: false, error: 'Net::ReadTimeout', unknown_outcome: true))
      allow_any_instance_of(Crm::MetaConversionEvent).to receive(:update!).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
        raise ActiveRecord::ConnectionNotEstablished, 'db gone' if (args.first || kwargs)[:error_message] == 'unknown_outcome'

        original.call(*args, **kwargs)
      end

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'error', error_message: 'unknown_outcome')

      perform

      expect(client).to have_received(:post_events).once
    end
  end

  describe 'only clicks made up to the event choose the inbox (#2738)' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }

    def whatsapp_inbox(token:, waba:, dataset:)
      created = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      config = { 'api_key' => token, 'business_account_id' => waba, 'meta_dataset' => { 'waba_id' => waba, 'id' => dataset } }.compact
      created.update_columns(provider_config: config) # rubocop:disable Rails/SkipsModelValidations
      created.inbox
    end

    def link_click(inbox, clid, at)
      linked = create(:conversation, account: account, inbox: inbox,
                                     additional_attributes: { 'campaign' => { 'ctwa_clid' => clid, 'touched_at' => at.iso8601 } })
      Crm::CardConversation.create!(account: account, card: card, conversation: linked)
    end

    before do
      allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:post_events).and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok'))
      conversation.update!(additional_attributes: { 'campaign' => { 'ctwa_clid' => 'BEFORE_SALE', 'touched_at' => 5.days.ago.iso8601 } })
      card.update_columns(closed_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'ignores a click made after the sale, even when it is the newest one' do
      link_click(whatsapp_inbox(token: 'later_key', waba: '222', dataset: 'DS2'), 'AFTER_SALE', 1.day.ago)

      perform

      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'test_key', dataset_id: 'DS123')
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(ctwa_clid: 'BEFORE_SALE', dataset_id: 'DS123')
    end

    it 'does not send when every click came after the sale' do
      conversation.update!(additional_attributes: { 'campaign' => { 'ctwa_clid' => 'AFTER_SALE', 'touched_at' => 1.day.ago.iso8601 } })

      perform

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'skipped', error_message: 'missing_ctwa_clid')
    end

    it 'uses the move instant of a moved event as the cutoff' do
      activity = card.activities.create!(account: account, event_type: 'move', created_at: 3.days.ago,
                                         payload: { 'to_stage_id' => stage.id })
      link_click(whatsapp_inbox(token: 'later_key', waba: '222', dataset: 'DS2'), 'AFTER_MOVE', 60.hours.ago)

      described_class.perform_now(account.id, card.id, activity.id, 'moved')

      expect(Crm::MetaConversionEvent.find_by(event_id: "crm-#{card.id}-moved-#{activity.id}").ctwa_clid).to eq('BEFORE_SALE')
    end

    it 'skips a newer click in an inbox without a token for an older one in an official inbox' do
      link_click(whatsapp_inbox(token: nil, waba: '222', dataset: nil), 'NO_TOKEN', 3.days.ago)

      perform

      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'test_key', dataset_id: 'DS123')
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).ctwa_clid).to eq('BEFORE_SALE')
    end
  end

  describe 'dataset that Meta no longer knows (#2738)' do
    let(:client) { instance_double(Meta::ConversionsApiClient) }
    let(:gone) do
      Meta::ConversionsApiClient::Result.new(ok: false, http_code: 400, error: 'does not exist', error_code: 100, error_subcode: 33)
    end

    before { allow(Meta::ConversionsApiClient).to receive(:new).and_return(client) }

    def dataset_lookup_returns(dataset_id)
      dataset_client = instance_double(Meta::WabaDatasetClient, find_or_create: Meta::WabaDatasetClient::Result.new(dataset_id: dataset_id))
      allow(Meta::WabaDatasetClient).to receive(:new).and_return(dataset_client)
    end

    it 'looks the WABA dataset up again once, keeps the new one and sends to it' do
      allow(client).to receive(:post_events).and_return(gone, Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok'))
      dataset_lookup_returns('DS_NEW')

      perform

      expect(Meta::WabaDatasetClient).to have_received(:new).with(access_token: 'test_key', waba_id: '111').once
      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: 'test_key', dataset_id: 'DS_NEW')
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'accepted', dataset_id: 'DS_NEW')
      expect(channel.reload.provider_config['meta_dataset']).to eq('waba_id' => '111', 'id' => 'DS_NEW')
    end

    it 'does not post again when Meta answers with the same dataset' do
      allow(client).to receive(:post_events).and_return(gone)
      dataset_lookup_returns('DS123')

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)

      expect(client).to have_received(:post_events).once
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'error', http_code: 400)
    end

    it 'keeps the dataset for any other refusal' do
      allow(client).to receive(:post_events)
        .and_return(Meta::ConversionsApiClient::Result.new(ok: false, http_code: 400, error: 'bad', error_code: 100, error_subcode: 2804))
      allow(Meta::WabaDatasetClient).to receive(:new)

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)

      expect(Meta::WabaDatasetClient).not_to have_received(:new)
    end

    it 'leaves the row as an error for the retry when the new lookup fails' do
      allow(client).to receive(:post_events).and_return(gone)
      result = Meta::WabaDatasetClient::Result.new(error: 'timeout', transient: true)
      allow(Meta::WabaDatasetClient).to receive(:new).and_return(instance_double(Meta::WabaDatasetClient, find_or_create: result))

      expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)

      expect(Crm::MetaConversionEvent.find_by(event_id: event_id).status).to eq('error')
      expect(channel.reload.provider_config['meta_dataset']).to eq('waba_id' => '111', 'id' => 'DS123')
    end

    it 'asks to reconnect, without a retry, when the new lookup is refused for access' do
      allow(client).to receive(:post_events).and_return(gone)
      result = Meta::WabaDatasetClient::Result.new(error: 'token expired', access_denied: true)
      allow(Meta::WabaDatasetClient).to receive(:new).and_return(instance_double(Meta::WabaDatasetClient, find_or_create: result))

      expect { perform }.not_to raise_error

      expect(client).to have_received(:post_events).once
      expect(Crm::MetaConversionEvent.find_by(event_id: event_id)).to have_attributes(status: 'skipped', error_message: 'missing_credentials')
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
