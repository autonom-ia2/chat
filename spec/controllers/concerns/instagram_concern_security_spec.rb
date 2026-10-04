require 'rails_helper'

RSpec.describe InstagramConcern do
  let(:integration) { Class.new { include InstagramConcern }.new }
  let(:marker) { 'synthetic-private-response-marker' }
  let(:token_endpoint) { 'https://graph.instagram.com/access_token' }
  let(:details_endpoint) { 'https://graph.instagram.com/v22.0/me' }

  before do
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_ID', nil).and_return('synthetic-client')
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return('synthetic-secret')
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_API_VERSION', 'v22.0').and_return('v22.0')
  end

  [200, 400].each do |http_status|
    context "with a sensitive body and HTTP #{http_status}" do
      let(:body) { http_status == 200 ? "{\"access_token\":\"#{marker}\"" : { 'access_token' => marker }.to_json }

      it 'sanitizes the real token-exchange error before any logger or tracker can see the response' do
        expect(Rails.logger).not_to receive(:error)
        expect(ChatwootExceptionTracker).not_to receive(:new)
        stub_request(:get, token_endpoint).with(query: { grant_type: 'ig_exchange_token', client_secret: 'synthetic-secret',
                                                         access_token: 'synthetic-short-token', client_id: 'synthetic-client' })
                                          .to_return(status: http_status, body: body)
        expect { integration.send(:exchange_for_long_lived_token, 'synthetic-short-token') }.to raise_error do |error|
          expect(error.class.name).to eq('CustomExceptions::InstagramApiError')
          expect(error).to have_attributes(code: http_status == 200 ? 'instagram_invalid_response' : 'instagram_token_exchange_failed',
                                           http_status: http_status == 200 ? 502 : http_status)
          expect(error.inspect).not_to include(marker)
          expect(error.cause).to be_nil
        end
      end

      it 'sanitizes the real user-details error without a raw parser cause' do
        expect(Rails.logger).not_to receive(:error)
        expect(ChatwootExceptionTracker).not_to receive(:new)
        stub_request(:get, details_endpoint).with(query: { fields: 'id,username,user_id,name,profile_picture_url,account_type',
                                                           access_token: 'synthetic-long-token' })
                                            .to_return(status: http_status, body: body)
        expect { Instagram::UserDetailsService.new(access_token: 'synthetic-long-token').perform }.to raise_error do |error|
          expect(error.class.name).to eq('Instagram::UserDetailsService::Error')
          expect(error).to have_attributes(code: http_status == 200 ? 'instagram_invalid_response' : 'instagram_user_details_failed',
                                           http_status: http_status == 200 ? 502 : http_status)
          expect(error.inspect).not_to include(marker)
          expect(error.cause).to be_nil
        end
      end
    end
  end
end
