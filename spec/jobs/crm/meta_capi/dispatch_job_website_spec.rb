require 'rails_helper'

# Modo site do funil de volta à Meta (#1011, docs/crm/ponte-lp-atribuicao.md seção 6).
# O caminho CTWA continua coberto por dispatch_job_spec.rb, sem alteração.
RSpec.describe Crm::MetaCapi::DispatchJob do
  let(:account) { create(:account) }
  let(:pipeline_metadata) { { 'meta_sync' => { 'dataset_id' => 'DS123', 'pixel_id' => '2164882667623689' } } }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:pipeline) do
    account.crm_pipelines.create!(name: 'Viagem', created_by: create(:user, account: account, role: :administrator),
                                  status: :active, metadata: pipeline_metadata)
  end
  let(:stage_type) { 'qualified' }
  let(:stage) do
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'S', position: 0, metadata: { 'funnel_stage_type' => stage_type })
  end
  let(:closed_at) { 2.hours.ago.change(usec: 0) }
  # Won at closed_at: the model stamps closed_at with "now" on save, so the card is saved then.
  let(:card) do
    travel_to(closed_at) do
      account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL', value_cents: 37_780,
                                status: :won, primary_conversation: conversation)
    end
  end
  let(:signals) do
    { 'fbc' => 'fb.1.1759650000000.IwAR123', 'fbp' => 'fb.1.1759650000000.123456789',
      'client_ip_address' => '200.1.2.3', 'client_user_agent' => 'Mozilla/5.0 iPhone' }
  end
  let(:click_signals) { signals }
  let(:client) { instance_double(Meta::ConversionsApiClient) }

  before do
    link = create(:ctwa_tracked_link, account: account, inbox: channel.inbox, usage: 'website',
                                      allowed_origins: ['https://placement.com.br'])
    create(:ctwa_tracked_link_click, account: account, tracked_link: link, conversation: conversation, meta_signals: click_signals)
    allow(Meta::ConversionsApiClient).to receive(:new).and_return(client)
    allow(client).to receive(:post_events)
      .and_return(Meta::ConversionsApiClient::Result.new(ok: true, http_code: 200, body: 'ok', error: nil))
  end

  def activity_id = 77

  def perform(event_type = 'won', activity: activity_id)
    described_class.perform_now(account.id, card.id, activity, event_type)
  end

  def row(event_type = 'won', activity: activity_id)
    Crm::MetaConversionEvent.find_by(event_id: "crm-#{card.id}-#{event_type}-#{activity}")
  end

  it 'sends a won card to the funnel Pixel as Purchase 377.80 BRL with the browser signals' do
    perform

    expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: anything, dataset_id: '2164882667623689')
    expect(client).to have_received(:post_events) do |events|
      expect(events.sole).to eq(
        'event_name' => 'Purchase',
        'event_time' => closed_at.to_i,
        'event_id' => "crm-#{card.id}-won-#{activity_id}",
        'action_source' => 'system_generated',
        'user_data' => signals,
        'custom_data' => { 'value' => 377.8, 'currency' => 'BRL' }
      )
    end
    expect(row).to have_attributes(status: 'accepted', http_code: 200, attribution_mode: 'website',
                                   dataset_id: '2164882667623689', ctwa_clid: nil, error_message: nil)
    expect(row.sent_at).to be_present
  end

  it 'sends a qualified stage move as QualifiedLead anchored on the transition time' do
    activity = Crm::Activity.create!(account: account, card: card, event_type: 'move',
                                     payload: { 'to_stage_id' => stage.id }, created_at: 3.hours.ago)

    perform('moved', activity: activity.id)

    expect(client).to have_received(:post_events) do |events|
      expect(events.sole).to include('event_name' => 'QualifiedLead', 'event_time' => activity.created_at.to_i)
    end
    expect(row('moved', activity: activity.id).status).to eq('accepted')
  end

  context 'when the visitor gave no marketing consent (no signals on the click)' do
    let(:click_signals) { {} }

    it 'skips with a visible missing_signals reason and sends nothing (CA-3.4)' do
      perform

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(row).to have_attributes(status: 'skipped', error_message: 'missing_signals', attribution_mode: nil)
    end
  end

  context 'when the card has no website click at all (organic, no ctwa_clid)' do
    it 'keeps the missing_ctwa_clid skip' do
      Ctwa::TrackedLinkClick.where(conversation_id: conversation.id).update_all(conversation_id: nil) # rubocop:disable Rails/SkipsModelValidations

      perform

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(row).to have_attributes(status: 'skipped', error_message: 'missing_ctwa_clid', attribution_mode: nil)
    end
  end

  context 'when the funnel has no Pixel' do
    let(:pipeline_metadata) { { 'meta_sync' => { 'dataset_id' => 'DS123' } } }

    it 'skips with missing_pixel and sends nothing' do
      perform

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(row).to have_attributes(status: 'skipped', error_message: 'missing_pixel', attribution_mode: 'website')
    end
  end

  # #1034: the token that can reach the Pixel is the Meta Ads one (generated after the system
  # user got the Pixel); the WhatsApp token stays only as a fallback.
  describe 'which token reaches the Pixel' do
    it 'uses the active Meta Ads connection token when there is one' do
      create_meta_ads_connection(account, token: 'EAAGanunciostoken1234567890abcdefPIXEL')

      perform

      expect(Meta::ConversionsApiClient).to have_received(:new)
        .with(access_token: 'EAAGanunciostoken1234567890abcdefPIXEL', dataset_id: '2164882667623689')
    end

    it 'falls back to the WhatsApp connection token when the Meta Ads connection is invalid or missing' do
      create_meta_ads_connection(account, status: 'invalid', token: 'EAAGanunciostoken1234567890abcdefPIXEL')

      perform

      expect(Meta::ConversionsApiClient).to have_received(:new)
        .with(access_token: channel.provider_config['api_key'], dataset_id: '2164882667623689')
    end
  end

  context 'when the WhatsApp connection has no token' do
    let(:conversation) { create(:conversation, account: account, inbox: create_crm_inbox(account: account)) }

    it 'skips with missing_credentials' do
      perform

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(row).to have_attributes(status: 'skipped', error_message: 'missing_credentials', attribution_mode: 'website')
    end
  end

  it 'does not send lost (no website equivalent)' do
    perform('lost')

    expect(Meta::ConversionsApiClient).not_to have_received(:new)
    expect(row('lost')).to have_attributes(status: 'skipped', error_message: 'no_meta_event')
  end

  context 'when the card moves into the lead stage' do
    let(:stage_type) { 'lead' }

    it 'does not resend Lead (the page already sent it)' do
      perform('moved')

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(row('moved')).to have_attributes(status: 'skipped', error_message: 'no_meta_event')
    end
  end

  context 'when the event is older than 7 days at send time' do
    let(:closed_at) { 8.days.ago }

    it 'skips with event_too_old without raising, so Sidekiq does not retry' do
      expect { perform }.not_to raise_error

      expect(Meta::ConversionsApiClient).not_to have_received(:new)
      expect(row).to have_attributes(status: 'skipped', error_message: 'event_too_old')
    end
  end

  # CA-3.5: a venda que fecha 30 dias depois do clique é enviada normalmente. A retenção
  # (Ctwa::TrackedLinkClicksRetentionJob) roda de hora em hora nesse meio tempo e não pode
  # apagar os sinais de um card aberto nem de um que acabou de fechar.
  context 'when the sale closes 30 days after the click' do
    let(:closed_at) { Time.current.change(usec: 0) }
    let!(:card) do
      travel_to(30.days.ago) do
        account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL', value_cents: 37_780,
                                  status: :open, primary_conversation: conversation)
      end
    end

    it 'keeps the signals through retention runs and sends the Purchase (accepted)' do
      Ctwa::TrackedLinkClick.where(conversation_id: conversation.id).update_all(created_at: 30.days.ago) # rubocop:disable Rails/SkipsModelValidations
      Ctwa::TrackedLinkClicksRetentionJob.perform_now
      travel_to(closed_at) { card.update!(status: :won) }
      Ctwa::TrackedLinkClicksRetentionJob.perform_now

      perform

      expect(client).to have_received(:post_events) do |events|
        expect(events.sole).to include('event_name' => 'Purchase', 'event_time' => closed_at.to_i, 'user_data' => signals)
      end
      expect(row).to have_attributes(status: 'accepted', attribution_mode: 'website')
    end
  end

  it 'records the Meta error message on the ledger row and re-raises for retry' do
    allow(client).to receive(:post_events)
      .and_return(Meta::ConversionsApiClient::Result.new(ok: false, http_code: 400, body: 'x', error: '(#100) Missing Permission'))

    expect { perform }.to raise_error(Crm::MetaCapi::DispatchJob::DispatchError)

    expect(row).to have_attributes(status: 'error', http_code: 400, error_message: '(#100) Missing Permission',
                                   attribution_mode: 'website')
  end

  it 'does not double-send once the event was accepted' do
    perform
    perform

    expect(client).to have_received(:post_events).once
  end

  context 'when the card also carries a ctwa_clid' do
    let(:conversation) do
      create(:conversation, account: account, inbox: channel.inbox, additional_attributes: { 'campaign' => { 'ctwa_clid' => 'CLID1' } })
    end

    it 'keeps the CTWA path: business_messaging to the dataset with the click id' do
      perform

      expect(Meta::ConversionsApiClient).to have_received(:new).with(access_token: anything, dataset_id: 'DS123')
      expect(client).to have_received(:post_events) do |events|
        expect(events.sole).to include('action_source' => 'business_messaging', 'messaging_channel' => 'whatsapp')
        expect(events.sole['user_data']).to include('ctwa_clid' => 'CLID1')
        expect(events.sole['user_data']).not_to include('fbc')
      end
      expect(row).to have_attributes(status: 'accepted', attribution_mode: 'ctwa', ctwa_clid: 'CLID1', dataset_id: 'DS123')
    end
  end
end
