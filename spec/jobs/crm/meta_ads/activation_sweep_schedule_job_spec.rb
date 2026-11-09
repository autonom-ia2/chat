require 'rails_helper'

# "Teve anúncio" (#2804): de hora em hora, uma leitura por conexão com anúncio criado aqui a partir de um post.
RSpec.describe Crm::MetaAds::ActivationSweepScheduleJob do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    account.enable_features!('meta_ads_hub', 'seus_posts')
  end

  def boosted(at: 1.day.ago, **attributes)
    Crm::MetaAdsCreatedObject.create!({ account: account, idempotency_key: SecureRandom.uuid, status: 'created', ad_id: '901',
                                        ad_account_id: connection.ad_account_id, source_post_id: '1790', source_post_network: 'instagram',
                                        created_at: at }.merge(attributes))
  end

  it 'enfileira a leitura da conexão com anúncio de post; a rodada seguinte, com o job na fila, não enfileira outra' do
    boosted

    expect { described_class.perform_now }.to have_enqueued_job(Crm::MetaAds::ActivationSweepJob).with(connection.id).exactly(:once)
    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ActivationSweepJob)
  end

  it 'fora: sem anúncio de post, anúncio velho, Anúncios da Meta desligado ou conexão caída' do
    boosted(source_post_id: nil)
    boosted(at: 91.days.ago)
    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ActivationSweepJob)

    boosted
    %w[meta_ads_hub seus_posts].each do |flag|
      account.disable_features!(flag)
      expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ActivationSweepJob)
      account.enable_features!(flag)
    end

    connection.update!(status: 'invalid')
    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ActivationSweepJob)
  end

  it 'o job lê a conexão e solta a trava no fim' do
    sweep = instance_double(Crm::MetaAds::Creation::ActivationSweep, perform: nil)
    allow(Crm::MetaAds::Creation::ActivationSweep).to receive(:new).with(connection).and_return(sweep)
    cache.write(described_class.lock_key(connection.id), true)

    Crm::MetaAds::ActivationSweepJob.perform_now(connection.id)

    expect(sweep).to have_received(:perform)
    expect(cache.exist?(described_class.lock_key(connection.id))).to be(false)
  end
end
