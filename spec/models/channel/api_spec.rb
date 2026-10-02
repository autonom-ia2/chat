# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Api do
  # This validation happens in ApplicationRecord
  describe 'WAHA cleanup' do
    let(:client) { instance_double(Waha::Client, delete_app: true, delete_session: true) }
    let(:channel_api) do
      create(
        :channel_api,
        additional_attributes: {
          'provider' => 'waha',
          'session' => '5511999999999',
          'app_id' => 'app_chatwoot',
          'phone_numbers_app_id' => 'br_numbers'
        }
      )
    end

    before do
      allow(Waha::Client).to receive(:new).and_return(client)
    end

    it 'removes both managed apps and the session when the channel is deleted' do
      channel_api.destroy!

      expect(client).to have_received(:delete_app).with('app_chatwoot').once
      expect(client).to have_received(:delete_app).with('br_numbers').once
      expect(client).to have_received(:delete_session).with('5511999999999').once
    end
  end

  describe 'length validations' do
    let(:channel_api) { create(:channel_api) }

    context 'when it validates webhook_url length' do
      it 'valid when within limit' do
        channel_api.webhook_url = 'a' * Limits::URL_LENGTH_LIMIT
        expect(channel_api.valid?).to be true
      end

      it 'invalid when crossed the limit' do
        channel_api.webhook_url = 'a' * (Limits::URL_LENGTH_LIMIT + 1)
        channel_api.valid?
        expect(channel_api.errors[:webhook_url]).to include("is too long (maximum is #{Limits::URL_LENGTH_LIMIT} characters)")
      end
    end
  end
end
