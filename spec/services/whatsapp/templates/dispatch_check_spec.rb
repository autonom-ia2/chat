require 'rails_helper'

RSpec.describe Whatsapp::Templates::DispatchCheck, :aggregate_failures do
  let(:account) { create(:account) }
  let(:channel) { journey_cloud_channel(account) }
  let(:template) { CampaignJourneyHelpers::JOURNEY_TEMPLATE.deep_dup }
  let(:campaign) do
    create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params, message: 'Olá')
  end

  def check
    described_class.new(campaign).call
  end

  context 'when Meta answers' do
    it 'asks Meta once, by name, for status, category and components, and accepts the matching template' do
      requests = stub_meta_template_lookup([template])

      verdict = check

      expect(verdict).to be_ok
      expect(verdict.details[:lookup_source]).to eq('meta')
      expect(requests.size).to eq(1)
      query = Rack::Utils.parse_query(requests.first.uri.query)
      expect(query['name']).to eq('renovacao')
      expect(query['fields'].split(',')).to include('status', 'category', 'components')
      expect(requests.first.uri.path).to end_with("/#{channel.provider_config['business_account_id']}/message_templates")
    end

    it 'trusts Meta over a stale cache: a template paused at Meta is not approved' do
      stub_meta_template_lookup([template.merge('status' => 'PAUSED')])

      verdict = check

      expect(verdict.reason_code).to eq('template_not_approved')
      expect(verdict.source).to eq('template')
      expect(verdict.details).to include(status: 'PAUSED', template_name: 'renovacao', lookup_source: 'meta')
    end

    it 'says the template is missing when Meta has no template with that name and language' do
      stub_meta_template_lookup([template.merge('language' => 'en_US')])

      expect(check.reason_code).to eq('template_missing')
    end

    it 'pauses when the category changed since the campaign was created' do
      stub_meta_template_lookup([template.merge('category' => 'UTILITY')])

      verdict = check

      expect(verdict.reason_code).to eq('template_category_changed')
      expect(verdict.details).to include(recorded_category: 'MARKETING', current_category: 'UTILITY')
    end

    it 'pauses when the variables changed, naming only the keys (no values)' do
      edited = template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, vence {{2}}. {{4}}' }])
      stub_meta_template_lookup([edited])

      verdict = check

      expect(verdict.reason_code).to eq('template_structure_changed')
      expect(verdict.details).to include(missing_keys: ['3'], extra_keys: ['4'], header_changed: false, buttons_changed: false)
    end

    it 'pauses when a media header was added after the campaign was created' do
      edited = template.merge('components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }] + template['components'])
      stub_meta_template_lookup([edited])

      expect(check.details).to include(header_changed: true)
    end

    it 'pauses a format the engines cannot send yet' do
      edited = template.merge('components' => template['components'] + [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE' }] }])
      stub_meta_template_lookup([edited])

      verdict = check

      expect(verdict.reason_code).to eq('template_format_unsupported')
      expect(verdict.details).to include(format_code: 'copy_code')
    end

    it 'accepts a Flow template and logs the flow_without_token warning' do
      flow = template.merge('components' => template['components'] + [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'FLOW' }] }])
      stub_meta_template_lookup([flow])
      allow(Rails.logger).to receive(:warn)

      verdict = check

      expect(verdict).to be_ok
      expect(verdict.details[:warnings]).to eq(['flow_without_token'])
      expect(Rails.logger).to have_received(:warn).with(include('flow_without_token'))
    end

    it 'accepts a copy-code template when the campaign recorded the code (legacy dialog), and pauses it otherwise' do
      copy = template.merge('components' => template['components'] + [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE' }] }])
      stub_meta_template_lookup([copy])
      params = journey_template_params
      params['processed_params']['buttons'] = [{ 'type' => 'copy_code', 'parameter' => 'PROMO10' }]
      campaign.update!(template_params: params)

      expect(check).to be_ok

      params['processed_params']['buttons'] = [{ 'type' => 'copy_code', 'parameter' => '' }]
      campaign.update!(template_params: params)
      expect(check.details).to include(format_code: 'copy_code')
    end

    it 'does not break on a legacy positional array of parameters' do
      campaign.update!(template_params: journey_template_params.merge('processed_params' => %w[Ana 10/2026]))
      stub_meta_template_lookup([template])

      expect(check).to be_ok
    end

    it 'does not compare the structure of a campaign kept in the legacy flat format' do
      campaign.update!(template_params: journey_template_params.merge('processed_params' => { '1' => 'Ana' }))
      stub_meta_template_lookup([template])

      expect(check).to be_ok
    end

    it 'accepts a recorded media header without media_type for any media header' do
      with_image = template.merge('components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }] + template['components'])
      params = journey_template_params
      params['processed_params']['header'] = { 'media_url' => 'https://a.com/x.png' }
      campaign.update!(template_params: params)
      stub_meta_template_lookup([with_image])

      expect(check).to be_ok
    end
  end

  context 'when Meta does not answer' do
    it 'falls back to the inbox cache and logs the source' do
      stub_meta_template_lookup(503)
      allow(Rails.logger).to receive(:warn)

      verdict = check

      expect(verdict).to be_ok
      expect(verdict.details[:lookup_source]).to eq('cache')
      expect(Rails.logger).to have_received(:warn).with(include('meta_unavailable source=cache'))
    end

    it 'falls back to the cache on a timeout' do
      stub_request(:get, WhatsappTemplateLookupHelpers::TEMPLATE_LOOKUP).to_timeout
      channel.update!(message_templates: [template.merge('status' => 'REJECTED')])

      expect(check.reason_code).to eq('template_not_approved')
    end

    it 'says templates_not_synced (system) when the cache was emptied by an account switch' do
      stub_meta_template_lookup(500)
      channel.update_columns(message_templates: [], message_templates_last_updated: nil) # rubocop:disable Rails/SkipsModelValidations

      verdict = check

      expect(verdict.reason_code).to eq('templates_not_synced')
      expect(verdict.source).to eq('system')
    end

    it 'says template_unverifiable (system) when there is no cache to read' do
      stub_meta_template_lookup(500)
      channel.update_columns(message_templates: [], message_templates_last_updated: Time.current) # rubocop:disable Rails/SkipsModelValidations

      verdict = check

      expect(verdict.reason_code).to eq('template_unverifiable')
      expect(verdict.source).to eq('system')
    end
  end
end
