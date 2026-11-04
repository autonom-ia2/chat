require 'rails_helper'

# Assinatura de `messaging_referrals` (#2521): soma só o campo; a mesma Página em várias contas tenta o token de cada uma,
# só das contas permitidas; erro passageiro tenta de novo mais tarde.
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

  it 'com contas permitidas, não usa o token de caixa de outra conta' do
    mine = create(:channel_facebook_page, page_id: 'page-1')
    other = create(:channel_facebook_page, page_id: 'page-1', account: create(:account))
    mine_subscription = subscription_for(mine)
    other_subscription = subscription_for(other)
    allow(mine_subscription).to receive(:add!).and_raise(refused)
    allow(other_subscription).to receive(:add!)

    described_class.perform_now('page-1', [mine.account_id])

    expect(other_subscription).not_to have_received(:add!)
  end

  it 'erro passageiro reenfileira até o limite, com as mesmas contas' do
    page = create(:channel_facebook_page, page_id: 'page-1')
    allow(subscription_for(page)).to receive(:add!).and_raise(transient)

    expect { described_class.perform_now('page-1', [page.account_id]) }
      .to have_enqueued_job(described_class).with('page-1', [page.account_id], 2)
    expect { described_class.perform_now('page-1', nil, 3) }.not_to have_enqueued_job(described_class)
  end
end
