require 'rails_helper'

# Reassinatura das Páginas antigas (#2521): soma só `messaging_referrals`; erro passageiro tenta de novo, recusa fica
# no log.
RSpec.describe Crm::MetaAds::MessagingReferralsSubscribeJob do
  let(:page) { create(:channel_facebook_page) }
  let(:subscription) { instance_double(Crm::MetaAds::PageSubscription) }

  before do
    allow(Crm::MetaAds::PageSubscription).to receive(:new).with(page_id: page.page_id, access_token: page.page_access_token)
                                                          .and_return(subscription)
  end

  it 'soma messaging_referrals na Página' do
    allow(subscription).to receive(:add!)

    described_class.perform_now(page.id)

    expect(subscription).to have_received(:add!).with(%w[messaging_referrals])
  end

  it 'erro passageiro reenfileira; recusa não' do
    allow(subscription).to receive(:add!).and_raise(Crm::MetaAds::PageSubscription::Error.new('5xx', http_code: 500))

    expect { described_class.perform_now(page.id) }.to have_enqueued_job(described_class).with(page.id, 2)
    expect { described_class.perform_now(page.id, 3) }.not_to have_enqueued_job(described_class)

    allow(subscription).to receive(:add!).and_raise(Crm::MetaAds::PageSubscription::Error.new('token', code: 190, http_code: 400))
    expect { described_class.perform_now(page.id) }.not_to have_enqueued_job(described_class)
  end
end
