require 'rails_helper'

# Imagem dos anúncios uma vez por dia por conexão (#1088).
RSpec.describe Crm::MetaAds::AdImagesJob do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:pause_key) { Crm::MetaAds::Insights::Usage.key(connection.ad_account_id) }

  def ttl
    Redis::Alfred.with { |conn| conn.ttl(described_class.key(connection.id)) }
  end

  after do
    Redis::Alfred.delete(described_class.key(connection.id))
    Redis::Alfred.delete(pause_key)
  end

  it 'start: uma vez por dia por conexão' do
    expect { described_class.start(connection) }.to have_enqueued_job(described_class).with(connection.id)
    expect { described_class.start(connection) }.not_to have_enqueued_job(described_class)
    expect(ttl).to be > described_class::RETRY_AFTER.to_i
  end

  it 'start: conta pausada por limite de uso não enfileira' do
    Redis::Alfred.set(pause_key, 1, ex: 60)

    expect { described_class.start(connection) }.not_to have_enqueued_job(described_class)
  end

  it 'avisa a tela quando alguma imagem foi renovada' do
    create(:user, account: account, role: :administrator)
    allow(Crm::MetaAds::AdImages).to receive(:new).and_return(instance_double(Crm::MetaAds::AdImages, refresh!: 2))
    Redis::Alfred.delete("#{Crm::MetaAds::Insights::Broadcaster::THROTTLE_PREFIX}:#{connection.id}")

    expect { described_class.perform_now(connection.id) }.to have_enqueued_job(ActionCableBroadcastJob)
  ensure
    Redis::Alfred.delete("#{Crm::MetaAds::Insights::Broadcaster::THROTTLE_PREFIX}:#{connection.id}")
  end

  it 'quando a Meta recusa, tenta de novo em RETRY_AFTER, não no dia seguinte' do
    described_class.start(connection)
    allow(Crm::MetaAds::AdImages).to receive(:new).and_return(instance_double(Crm::MetaAds::AdImages, refresh!: nil))

    described_class.perform_now(connection.id)

    expect(ttl).to be_between(1, described_class::RETRY_AFTER.to_i)
  end

  it 'quando quebra no meio, também tenta de novo em RETRY_AFTER' do
    described_class.start(connection)
    allow(Crm::MetaAds::AdImages).to receive(:new).and_raise(ArgumentError, 'falhou')

    expect { described_class.new.perform(connection.id) }.to raise_error(ArgumentError)
    expect(ttl).to be_between(1, described_class::RETRY_AFTER.to_i)
  end
end
