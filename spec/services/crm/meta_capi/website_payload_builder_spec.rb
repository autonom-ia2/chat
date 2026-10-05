require 'rails_helper'

# Evento do Pixel no modo site do funil de volta à Meta (#1011, seção 6).
RSpec.describe Crm::MetaCapi::WebsitePayloadBuilder do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { account.crm_pipelines.create!(name: 'P', created_by: user, status: :active) }
  let(:stage) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'S', position: 0) }
  let(:signals) do
    { 'fbc' => 'fb.1.1759650000000.IwAR123', 'fbp' => 'fb.1.1759650000000.123456789',
      'client_ip_address' => '200.1.2.3', 'client_user_agent' => 'Mozilla/5.0 iPhone' }
  end

  describe '.canonical_event_name' do
    it 'maps won to Purchase' do
      expect(described_class.canonical_event_name(event_type: 'won', stage_type: nil)).to eq('Purchase')
    end

    it 'sends nothing for lost' do
      expect(described_class.canonical_event_name(event_type: 'lost', stage_type: 'qualified')).to be_nil
    end

    it 'sends nothing for the lead stage (the page already fired Lead)' do
      expect(described_class.canonical_event_name(event_type: 'moved', stage_type: 'lead')).to be_nil
    end

    it 'maps the funnel stages to the Pixel events' do
      expect(described_class.canonical_event_name(event_type: 'moved', stage_type: 'qualified')).to eq('QualifiedLead')
      expect(described_class.canonical_event_name(event_type: 'moved', stage_type: 'opportunity')).to eq('AddToCart')
      expect(described_class.canonical_event_name(event_type: 'moved', stage_type: 'negotiation')).to eq('InitiateCheckout')
    end

    it 'returns nil for movements without stage type and for events without a mapping' do
      expect(described_class.canonical_event_name(event_type: 'moved', stage_type: nil)).to be_nil
      expect(described_class.canonical_event_name(event_type: 'reopen', stage_type: 'qualified')).to be_nil
    end
  end

  describe '.build' do
    it 'builds a system_generated Purchase of 377.80 BRL with the browser signals' do
      closed_at = 1.hour.ago.change(usec: 0)
      # The model stamps closed_at with "now" when the card is won, so win it at that instant.
      card = travel_to(closed_at) do
        account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL', value_cents: 37_780, status: :won)
      end

      payload = described_class.build(card: card, event_name: 'Purchase', event_type: 'won', event_id: 'crm-1-won-9',
                                      signals: signals)

      expect(payload).to eq(
        'event_name' => 'Purchase',
        'event_time' => closed_at.to_i,
        'event_id' => 'crm-1-won-9',
        'action_source' => 'system_generated',
        'user_data' => signals,
        'custom_data' => { 'value' => 377.8, 'currency' => 'BRL' }
      )
      expect(payload).not_to have_key('messaging_channel')
    end

    it 'keeps only present signals in user_data' do
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL')

      payload = described_class.build(card: card, event_name: 'QualifiedLead', event_type: 'moved', event_id: 'e1',
                                      signals: { 'fbc' => 'fb.1.1.abc', 'fbp' => nil, 'client_ip_address' => '' })

      expect(payload['user_data']).to eq('fbc' => 'fb.1.1.abc')
      expect(payload).not_to have_key('custom_data')
    end
  end
end
