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

  # #2781: o mesmo Instagram em mais de uma conta, como a Página do Facebook; na mesma conta, uma vez só.
  describe 'uniqueness of instagram_id' do
    it 'allows the same Instagram in another account and refuses it twice in the same account' do
      first = create(:channel_instagram, instagram_id: 'ig-shared')

      expect(build(:channel_instagram, instagram_id: 'ig-shared', account: create(:account))).to be_valid
      expect(build(:channel_instagram, instagram_id: 'ig-shared', account: first.account)).not_to be_valid
    end

    it 'keeps the webhook subscription while another account still uses the same Instagram' do
      first = create(:channel_instagram, instagram_id: 'ig-shared')
      second = create(:channel_instagram, instagram_id: 'ig-shared')

      first.destroy!
      expect(a_request(:delete, %r{graph\.instagram\.com/v22\.0/ig-shared/subscribed_apps})).not_to have_been_made

      second.destroy!
      expect(a_request(:delete, %r{graph\.instagram\.com/v22\.0/ig-shared/subscribed_apps})).to have_been_made.once
    end
  end

  it 'has a valid name' do
    expect(channel.name).to eq('Instagram')
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
