require 'rails_helper'

# Instagram pelo login único (#2406): a Página dona do token se inscreve no webhook com os campos do Messenger.
RSpec.describe Instagram::PageSubscribeJob do
  let(:channel) { create(:channel_instagram, login: 'facebook', page_id: '104000000000001') }
  let(:subscription) { instance_double(Crm::MetaAds::PageSubscription) }

  before { allow(Crm::MetaAds::PageSubscription).to receive(:new).and_return(subscription) }

  it 'soma os campos do Messenger na Página, com o token da caixa' do
    allow(subscription).to receive(:add!)

    described_class.perform_now(channel.id)

    expect(Crm::MetaAds::PageSubscription).to have_received(:new).with(page_id: '104000000000001', access_token: channel[:access_token])
    expect(subscription).to have_received(:add!).with(Channel::FacebookPage::MESSENGER_FIELDS)
  end

  it 'erro passageiro tenta de novo; recusa não' do
    allow(subscription).to receive(:add!).and_raise(Crm::MetaAds::PageSubscription::Error.new('lento', http_code: 503))
    expect { described_class.perform_now(channel.id) }.to have_enqueued_job(described_class).with(channel.id, attempt: 2)

    allow(subscription).to receive(:add!).and_raise(Crm::MetaAds::PageSubscription::Error.new('recusa', code: 10, http_code: 400))
    expect { described_class.perform_now(channel.id) }.not_to have_enqueued_job(described_class)
  end

  it 'caixa do login do Instagram não mexe na Página' do
    described_class.perform_now(create(:channel_instagram).id)

    expect(Crm::MetaAds::PageSubscription).not_to have_received(:new)
  end
end
