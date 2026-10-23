# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::Instagram do
  let(:channel) { create(:channel_instagram) }

  it { is_expected.to validate_presence_of(:account_id) }
  it { is_expected.to validate_presence_of(:access_token) }
  it { is_expected.to validate_presence_of(:instagram_id) }
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_one(:inbox).dependent(:destroy_async) }

  it 'has a valid name' do
    expect(channel.name).to eq('Instagram')
  end

  describe 'inscrição nos campos do webhook (#2113)' do
    let(:url) { "https://graph.instagram.com/v22.0/#{channel.instagram_id}/subscribed_apps" }

    it 'inscreve as mensagens, as reações, o visto e a edição do cliente' do
      expect(described_class::SUBSCRIBED_FIELDS).to eq(%w[messages message_reactions messaging_seen message_edit])
    end

    it 'refaz a inscrição quando a caixa é reconectada com um token novo' do
      stub = stub_request(:post, url).with(query: { access_token: 'token-novo', subscribed_fields: described_class::SUBSCRIBED_FIELDS })

      channel.update!(access_token: 'token-novo')

      expect(stub).to have_been_requested.once
    end

    it 'não chama a Meta quando o token não muda' do
      channel
      WebMock.reset_executed_requests!
      stub = stub_request(:post, url).with(query: hash_including({}))

      channel.update!(provider_name: 'outro_nome')

      expect(stub).not_to have_been_requested
    end
  end

  describe 'concerns' do
    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for instagram' do
        admin_mailer = double
        mailer_double = double

        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:instagram_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        channel.prompt_reauthorization!
      end
    end
  end
end
