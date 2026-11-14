require 'rails_helper'

# Guards the dispatch gate: CRM card lifecycle events reach the dispatcher when an
# account webhook subscribes them OR when a pipeline opted into Meta CAPI sync —
# without the second branch the Meta listener silently never fires.
RSpec.describe Crm::Webhooks::Emitter do
  # crm.card.* is only a valid webhook subscription when the CRM is enabled.
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline) do
    account.crm_pipelines.create!(name: 'P', created_by: user, status: :active, metadata: pipeline_metadata)
  end
  let(:pipeline_metadata) { {} }

  def emit(event_type: 'won')
    described_class.emit(
      account_id: account.id, card_id: 1, activity_id: 2, event_type: event_type, changed_attributes: nil
    )
  end

  # The dispatcher also receives unrelated model-lifecycle events from the test
  # setup, so every assertion targets the crm.card.* event explicitly.
  before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

  def expect_no_card_dispatch(event)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(event, any_args)
  end

  context 'when nothing subscribes the event' do
    it 'does not dispatch' do
      pipeline
      emit

      expect_no_card_dispatch('crm.card.won')
    end
  end

  context 'when an account webhook subscribes the event' do
    it 'dispatches' do
      create(:webhook, account: account, webhook_type: :account_type, subscriptions: ['crm.card.won'])
      emit

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with('crm.card.won', anything, hash_including(account_id: account.id, activity_id: 2))
    end
  end

  context 'when a non-sale funnel closes a card (#1144)' do
    it 'dispatches crm.card.resolved to the subscribing webhook' do
      create(:webhook, account: account, webhook_type: :account_type, subscriptions: ['crm.card.resolved'])
      emit(event_type: 'resolved')

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with('crm.card.resolved', anything, hash_including(account_id: account.id))
    end
  end

  context 'when a pipeline opted into Meta sync for the event' do
    let(:pipeline_metadata) { { 'meta_sync' => { 'enabled' => true, 'events' => { 'won' => true } } } }

    it 'dispatches even without any account webhook' do
      pipeline
      emit

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with('crm.card.won', anything, hash_including(account_id: account.id))
    end

    it 'does not dispatch an event the pipeline did not subscribe' do
      pipeline
      emit(event_type: 'lost')

      expect_no_card_dispatch('crm.card.lost')
    end
  end

  context 'when a pipeline opted into Google sync only' do
    let(:pipeline_metadata) { { 'google_sync' => { 'enabled' => true, 'events' => { 'won' => true } } } }

    it 'dispatches even without any account webhook or Meta sync' do
      pipeline
      emit

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with('crm.card.won', anything, hash_including(account_id: account.id))
    end

    it 'does not dispatch an event the pipeline did not subscribe' do
      pipeline
      emit(event_type: 'lost')

      expect_no_card_dispatch('crm.card.lost')
    end
  end

  context 'when Meta sync is configured but disabled' do
    let(:pipeline_metadata) { { 'meta_sync' => { 'enabled' => false, 'events' => { 'won' => true } } } }

    it 'does not dispatch' do
      pipeline
      emit

      expect_no_card_dispatch('crm.card.won')
    end
  end

  # #2898 (insurance portfolio, E5): the renewal card of a policy, in an account with no webhook, ad sync or automation.
  # Without this branch "Renovou" on the board would never reach the policy.
  context 'when the card is the renewal card of an insurance policy and nothing else subscribes' do
    # The account has the insurance portfolio (Carteira::Acesso): the gate asks that first, before any query.
    let(:account) { conta_com_carteira }
    let(:stage) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'A vencer', position: 0) }
    let(:renewal_card) { account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Renovação') }
    let(:other_card) { account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido') }
    let(:outcomes) do
      { 'won' => 'crm.card.won', 'lost' => 'crm.card.lost', 'resolved' => 'crm.card.resolved', 'cancelled' => 'crm.card.cancelled',
        'reopen' => 'crm.card.reopened', 'archive' => 'crm.card.archived' }
    end

    before { create(:carteira_apolice, account: account, crm_card: renewal_card) }

    def emit_for(card, event_type)
      described_class.emit(account_id: account.id, card_id: card.id, activity_id: 2, event_type: event_type, changed_attributes: nil)
    end

    it 'dispatches every outcome event of that card' do
      outcomes.each_key { |event_type| emit_for(renewal_card, event_type) }

      outcomes.each_value do |event|
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(event, anything, hash_including(card_id: renewal_card.id)).once
      end
    end

    it 'does not dispatch the outcome of a card with no policy, nor the creation or the move of the renewal card' do
      outcomes.each_key { |event_type| emit_for(other_card, event_type) }
      %w[create move].each { |event_type| emit_for(renewal_card, event_type) }

      (outcomes.values + %w[crm.card.created crm.card.moved]).each { |event| expect_no_card_dispatch(event) }
    end

    it 'does not dispatch for an account that no longer has the insurance portfolio' do
      account.disable_features!('carteira_seguros')

      outcomes.each_key { |event_type| emit_for(renewal_card, event_type) }

      outcomes.each_value { |event| expect_no_card_dispatch(event) }
    end
  end
end
