require 'rails_helper'

# #2520: ligar um cuidado de Facebook assina o `feed` da Página e grava a Página da conta (crm_meta_ads_pages), sem o
# que o Crm::MetaAds::FacebookFeed ignora o comentário. Antes, só a aba Facebook do anúncio fazia isso.
RSpec.describe Crm::MetaAds::ComentariosIa::AssinarFeedJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:canal) { create(:channel_facebook_page, account: account, page_id: '555') }
  let(:refused) { Crm::MetaAds::PageSubscription::Error.new('token', code: 190, http_code: 400) }
  let(:transient) { Crm::MetaAds::PageSubscription::Error.new('5xx', http_code: 500) }
  let(:assinatura) { instance_double(Crm::MetaAds::PageSubscription, add!: true) }

  before do
    allow(Crm::MetaAds::PageSubscription).to receive(:new).with(page_id: '555', access_token: canal.page_access_token).and_return(assinatura)
  end

  describe '.para!' do
    it 'cuidado de post do Facebook, ligado: uma Página, a da caixa' do
      care = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '555_1', post_ids: %w[555_1],
                                                network: 'facebook', inbox_id: canal.inbox.id)

      expect { described_class.para!(care) }.to have_enqueued_job(described_class).with(account.id, '555').exactly(:once)
    end

    it 'anúncio nas duas redes: a Página dos posts do criativo, sem o post do Instagram' do
      care = create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', post_ids: %w[17900 777_2],
                                                network: 'both')

      expect { described_class.para!(care) }.to have_enqueued_job(described_class).with(account.id, '777').exactly(:once)
    end

    it 'pausado ou só do Instagram: nada' do
      pausado = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '555_1', post_ids: %w[555_1],
                                                   network: 'facebook', status: 'paused')
      instagram = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '179', network: 'instagram')

      expect { described_class.para!(pausado) }.not_to have_enqueued_job(described_class)
      expect { described_class.para!(instagram) }.not_to have_enqueued_job(described_class)
    end
  end

  it 'assina o feed com o token da caixa e grava a Página da conta como recebendo' do
    described_class.perform_now(account.id, canal.page_id)

    expect(assinatura).to have_received(:add!).with(%w[feed])
    expect(Crm::MetaAdsPage.find_by(account_id: account.id, page_id: '555')).to have_attributes(feed_receiving: true)
    expect(Crm::MetaAdsPage.account_ids_for('555')).to eq([account.id])
  end

  it 'Página já assinada nesta conta: não chama a Meta; o nome guardado fica' do
    Crm::MetaAdsPage.create!(account: account, page_id: '555', name: 'Loja', feed_receiving: true)

    described_class.perform_now(account.id, canal.page_id)

    expect(assinatura).not_to have_received(:add!)
    expect(Crm::MetaAdsPage.find_by(account_id: account.id, page_id: '555').name).to eq('Loja')
  end

  it 'Página guardada sem o feed: assina e mantém o nome' do
    Crm::MetaAdsPage.create!(account: account, page_id: '555', name: 'Loja')

    described_class.perform_now(account.id, canal.page_id)

    expect(Crm::MetaAdsPage.find_by(account_id: account.id, page_id: '555')).to have_attributes(name: 'Loja', feed_receiving: true)
  end

  it 'sem caixa da Página nesta conta: nada' do
    described_class.perform_now(create(:account).id, canal.page_id)

    expect(assinatura).not_to have_received(:add!)
    expect(Crm::MetaAdsPage.count).to eq(0)
  end

  it 'erro passageiro tenta de novo mais tarde; recusa do token não, e a Página não fica como recebendo' do
    allow(assinatura).to receive(:add!).and_raise(transient)
    expect { described_class.perform_now(account.id, canal.page_id) }.to have_enqueued_job(described_class).with(account.id, '555', 2)

    allow(assinatura).to receive(:add!).and_raise(refused)
    expect { described_class.perform_now(account.id, canal.page_id) }.not_to have_enqueued_job(described_class)
    expect(Crm::MetaAdsPage.feed_receiving.count).to eq(0)
  end
end
