require 'rails_helper'

RSpec.describe Crm::MetaCapi::BackfillJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  let(:campaign_attributes) { { 'campaign' => { 'ctwa_clid' => 'CLID123' } } }
  let(:meta_sync) { { 'enabled' => true, 'events' => { 'won' => true, 'moved' => true } } }

  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  # Clicks without touched_at date from the conversation start, and only clicks made by the
  # event count (#2799): the conversation starts before the events under test, as in real life.
  let(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, additional_attributes: campaign_attributes, created_at: 1.day.ago)
  end
  let(:pipeline) { account.crm_pipelines.create!(name: 'P', created_by: user, status: :active, metadata: { 'meta_sync' => meta_sync }) }
  let(:stage) do
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'S', position: 0, metadata: { 'funnel_stage_type' => 'qualified' })
  end
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL',
                              value_cents: 50_000, status: :won, primary_conversation: conversation)
  end

  let!(:won_activity) { Crm::Activity.create!(account: account, card: card, event_type: 'won') }
  let!(:move_activity) { Crm::Activity.create!(account: account, card: card, event_type: 'move') }

  let(:won_event_id) { "crm-#{card.id}-won-#{won_activity.id}" }
  let(:moved_event_id) { "crm-#{card.id}-moved-#{move_activity.id}" }

  before do
    # Silence the activity->webhook bridge so creating fixture activities does not
    # enqueue unrelated listener jobs and pollute the dispatch assertions.
    allow(Crm::Webhooks::Emitter).to receive(:emit)
    allow(Crm::MetaCapi::DispatchJob).to receive(:perform_later)
  end

  describe 'dry run (default)' do
    it 'reports what would be sent without writing a ledger row or enqueuing a dispatch' do
      report = nil
      expect { report = described_class.perform_now(account.id) }.not_to change(Crm::MetaConversionEvent, :count)

      expect(report[:dry_run]).to be(true)
      expect(report[:would_send]).to eq(2)
      expect(report[:by_event_type]).to eq('won' => 1, 'moved' => 1)
      expect(report[:enqueued]).to eq(0)
      expect(Crm::MetaCapi::DispatchJob).not_to have_received(:perform_later)
    end

    context 'when the click lives only in a linked conversation (#1940)' do
      let(:card) do
        created = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL', value_cents: 50_000, status: :won)
        Crm::CardConversation.create!(account: account, card: created, conversation: conversation)
        created
      end

      it 'still counts the card' do
        expect(described_class.perform_now(account.id)[:would_send]).to eq(2)
      end
    end

    context 'when the card has no ctwa_clid' do
      let(:campaign_attributes) { {} }

      it 'counts the card as skipped and would send nothing' do
        report = described_class.perform_now(account.id)

        expect(report[:skipped_no_clid]).to eq(1)
        expect(report[:would_send]).to eq(0)
      end
    end
  end

  # #2799: the same cut as the live send (#2738). A click made after the event did not bring
  # it, so the report must not count it as something that would be sent.
  describe 'click made after the event' do
    let(:campaign_attributes) { { 'campaign' => { 'ctwa_clid' => 'CLID123', 'touched_at' => 1.hour.ago.iso8601 } } }

    before do
      card.update_columns(closed_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
      won_activity.update_columns(created_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'does not count an event whose only click came after it' do
      report = described_class.perform_now(account.id)

      expect(report[:by_event_type]).to eq('moved' => 1)
      expect(report[:would_send]).to eq(1)
      expect(report[:skipped_click_after_event]).to eq(1)
      expect(report[:skipped_no_clid]).to eq(0)
    end

    it 'still counts the event when website signals made before it would carry it, as the live send does' do
      link = create(:ctwa_tracked_link, account: account, inbox: channel.inbox, usage: 'website', allowed_origins: ['https://placement.com.br'])
      create(:ctwa_tracked_link_click, account: account, tracked_link: link, conversation: conversation,
                                       meta_signals: { 'fbp' => 'fb.1.1759650000000.123456789' }, created_at: 2.days.ago)

      expect(described_class.perform_now(account.id)[:by_event_type]).to eq('won' => 1, 'moved' => 1)
    end

    it 'uses the time of the win when the card has no close instant' do
      card.update_columns(closed_at: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.perform_now(account.id)[:by_event_type]).to eq('moved' => 1)
    end
  end

  describe 'real run (dry_run: false)' do
    it 'enqueues a dispatch tagged source:backfill for each candidate event' do
      report = described_class.perform_now(account.id, dry_run: false)

      expect(Crm::MetaCapi::DispatchJob).to have_received(:perform_later)
        .with(account.id, card.id, won_activity.id, 'won', source: 'backfill')
      expect(Crm::MetaCapi::DispatchJob).to have_received(:perform_later)
        .with(account.id, card.id, move_activity.id, 'moved', source: 'backfill')
      expect(report[:enqueued]).to eq(2)
    end

    it 'never re-enqueues an event already accepted (idempotent re-run)' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: won_event_id, event_type: 'won', status: :accepted)
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: moved_event_id, event_type: 'moved', status: :accepted)

      report = described_class.perform_now(account.id, dry_run: false)

      expect(Crm::MetaCapi::DispatchJob).not_to have_received(:perform_later)
      expect(report[:already_sent]).to eq(2)
      expect(report[:would_send]).to eq(0)
      expect(report[:enqueued]).to eq(0)
    end

    it 'enqueues only the events that have not been accepted yet' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: won_event_id, event_type: 'won', status: :accepted)

      report = described_class.perform_now(account.id, dry_run: false)

      expect(Crm::MetaCapi::DispatchJob).to have_received(:perform_later)
        .with(account.id, card.id, move_activity.id, 'moved', source: 'backfill').once
      expect(report[:already_sent]).to eq(1)
      expect(report[:enqueued]).to eq(1)
    end

    # #2799: Meta may have kept it, and DispatchJob never posts it again, so it is not "would send".
    it 'does not enqueue an event whose outcome at Meta is unknown, but does a refused one' do
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: won_event_id, event_type: 'won',
                                       status: :error, error_message: 'unknown_outcome')
      Crm::MetaConversionEvent.create!(account: account, card: card, event_id: moved_event_id, event_type: 'moved',
                                       status: :error, error_message: 'refused')

      report = described_class.perform_now(account.id, dry_run: false)

      expect(Crm::MetaCapi::DispatchJob).to have_received(:perform_later)
        .with(account.id, card.id, move_activity.id, 'moved', source: 'backfill').once
      expect(report).to include(already_sent: 1, enqueued: 1)
    end
  end

  describe 'gating' do
    it 'returns an empty report when the account does not exist' do
      report = described_class.perform_now(0)

      expect(report[:account_id]).to eq(0)
      expect(report[:would_send]).to eq(0)
    end

    context 'when meta_sync is disabled on the pipeline' do
      let(:meta_sync) { { 'enabled' => false, 'events' => { 'won' => true, 'moved' => true } } }

      it 'skips the pipeline entirely' do
        card # ensure the card/activities exist
        report = described_class.perform_now(account.id)

        expect(report[:would_send]).to eq(0)
      end
    end

    context 'when only the won event is subscribed' do
      let(:meta_sync) { { 'enabled' => true, 'events' => { 'won' => true }, 'dataset_id' => 'DS123' } }

      it 'considers only the subscribed event' do
        report = described_class.perform_now(account.id)

        expect(report[:by_event_type]).to eq('won' => 1)
        expect(report[:would_send]).to eq(1)
      end
    end
  end
end
