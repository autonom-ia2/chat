require 'rails_helper'

# Reassinatura das Páginas antigas (#2521): soma só `messaging_referrals`; a mesma Página em várias contas tenta o token
# de cada uma; erro passageiro tenta de novo mais tarde.
RSpec.describe Crm::MetaAds::MessagingReferralsSubscribeJob do
  let(:refused) { Crm::MetaAds::PageSubscription::Error.new('token', code: 190, http_code: 400) }
  let(:transient) { Crm::MetaAds::PageSubscription::Error.new('5xx', http_code: 500) }

  def subscription_for(channel)
    instance_double(Crm::MetaAds::PageSubscription).tap do |subscription|
      allow(Crm::MetaAds::PageSubscription).to receive(:new).with(page_id: channel.page_id, access_token: channel.page_access_token)
                                                            .and_return(subscription)
    end
  end

  it 'soma messaging_referrals com o token da primeira caixa que a Meta aceita' do
    first = create(:channel_facebook_page, page_id: 'page-1')
    second = create(:channel_facebook_page, page_id: 'page-1', account: create(:account))
    first_subscription = subscription_for(first)
    second_subscription = subscription_for(second)
    allow(first_subscription).to receive(:add!).and_raise(refused)
    allow(second_subscription).to receive(:add!)

    described_class.perform_now('page-1')

    expect(second_subscription).to have_received(:add!).with(%w[messaging_referrals])
  end

  it 'erro passageiro reenfileira até o limite' do
    page = create(:channel_facebook_page, page_id: 'page-1')
    allow(subscription_for(page)).to receive(:add!).and_raise(transient)

    expect { described_class.perform_now('page-1') }.to have_enqueued_job(described_class).with('page-1', 2)
    expect { described_class.perform_now('page-1', 3) }.not_to have_enqueued_job(described_class)
  end
end
