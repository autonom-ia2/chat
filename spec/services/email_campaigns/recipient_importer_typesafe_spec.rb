require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientImporter, :aggregate_failures do
  context 'with TypeSafe Jev integration' do
    let(:campaign) { create(:email_campaign) }
    let(:import) { campaign.email_campaign_imports.create! }

    it 'uses the TypeSafe client with a small semantic sample while masking all row values' do
      allow(TypesafeAi::Config).to receive_messages(
        enabled?: true, configured?: true, api_key: 'ts_mocked_http', model: 'jev-1.13.0'
      )
      requests = []
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
        body = JSON.parse(request.body)
        requests << body
        {
          status: 200,
          body: {
            model: 'jev-1.13.0',
            answers: {
              email_column: {
                type: 'choice', choice: 'column_1', probabilities: { 'column_1' => 1.0 }, confidence: 1.0
              },
              name_column: {
                type: 'choice', choice: 'column_0', probabilities: { 'column_0' => 1.0 }, confidence: 1.0
              },
              schema_valid: { type: 'noul', noul: 0.99 }
            },
            usage: { input_tokens: 100, output_tokens: 10 }
          }.to_json
        }
      end

      result = described_class.new(
        campaign,
        "SEGURADO;MAIL PRINCIPAL;BROKER\nAna Pessoa;ana@example.org;ABC\nBia Pessoa;bia@example.org;XYZ\n",
        filename: 'clientes.csv', import: import
      ).perform

      expect(result.imported).to eq(2)
      expect(campaign.email_campaign_recipients.order(:email).pluck(:name, :email, :custom_data)).to eq(
        [
          ['Ana Pessoa', 'ana@example.org', { 'broker' => 'ABC' }],
          ['Bia Pessoa', 'bia@example.org', { 'broker' => 'XYZ' }]
        ]
      )
      expect(import.reload.schema_resolution).to include('method' => 'jev', 'model' => 'jev-1.13.0')
      serialized_requests = requests.to_json
      expect(requests.first.fetch('state').fetch('profiles')[0].fetch('examples')).to eq(['Aaa Aaaaaa'])
      expect(serialized_requests).not_to include('Ana Pessoa', 'Bia Pessoa', 'ana@example.org', 'ABC', 'XYZ')
      expect(serialized_requests).not_to include('bia@example.org')
      expect(requests.size).to eq(1)
    end
  end
end
