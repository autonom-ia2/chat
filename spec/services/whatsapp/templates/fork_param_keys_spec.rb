require 'rails_helper'

# The Chatwoot converter reads a processed_params it does not recognize as the legacy format (body values). The fork
# keys (#1334) and the quick reply payload with gaps in buttons (#1473) must stay in the parts format.
RSpec.describe Whatsapp::Templates::ForkParamKeys do
  subject(:normalized) { Whatsapp::TemplateParameterConverterService.new(params, {}).normalize_to_enhanced['processed_params'] }

  let(:params) { { 'processed_params' => processed } }

  context 'with a quick reply payload and nil in the positions that carry nothing' do
    let(:processed) { { 'body' => { '1' => 'Ana' }, 'buttons' => [nil, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }] } }

    it 'keeps the parts format' do
      expect(normalized).to eq(processed)
      expect(params).not_to have_key('format_version')
    end
  end

  context 'with gaps in buttons and no quick reply payload' do
    let(:processed) { { 'body' => { '1' => 'Ana' }, 'buttons' => [nil, { 'type' => 'url', 'parameter' => 'x' }] } }

    it 'keeps the Chatwoot reading (legacy), as before #1473' do
      normalized

      expect(params['format_version']).to eq('legacy')
    end
  end

  context 'with gaps in buttons and an empty quick reply payload' do
    let(:processed) { { 'body' => { '1' => 'Ana' }, 'buttons' => [nil, { 'type' => 'quick_reply', 'payload' => ' ' }] } }

    it 'keeps the Chatwoot reading (legacy), as before #1473' do
      normalized

      expect(params['format_version']).to eq('legacy')
    end
  end
end
