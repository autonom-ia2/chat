require 'rails_helper'

# Agendador da coleta de insights (#1073): escopos, flag, trava e carga de 90 dias no lugar.
RSpec.describe Crm::MetaAds::InsightsScheduleJob do
  include_context 'with a meta ads insights connection'

  it 'hoje: um job por conexão, com a trava do escopo' do
    connection

    expect { described_class.perform_now('today') }
      .to have_enqueued_job(Crm::MetaAds::InsightsSyncJob).with(connection.id, 'today').exactly(:once)
    expect { described_class.perform_now('today') }.not_to have_enqueued_job(Crm::MetaAds::InsightsSyncJob)
  end

  it 'pula conta sem Anúncios da Meta ligado e conexão inválida' do
    connection
    account.disable_features!('meta_ads_hub')
    other = create(:account)
    other.enable_features!('meta_ads_hub')
    create_meta_ads_insights_connection(other, ad_account_id: '999').update!(status: 'invalid')

    expect { described_class.perform_now('today') }.not_to have_enqueued_job(Crm::MetaAds::InsightsSyncJob)
  end

  it 'recentes: sem a carga de 90 dias, enfileira a carga no lugar da leitura' do
    connection

    expect { described_class.perform_now('recent') }.to have_enqueued_job(Crm::MetaAds::InsightsBackfillJob).with(connection.id)
    expect { described_class.perform_now('recent') }.not_to have_enqueued_job(Crm::MetaAds::InsightsBackfillJob)
  end

  it 'recentes: com a carga feita, lê os 3 dias' do
    connection.update!(insights_backfilled_at: 1.day.ago)

    expect { described_class.perform_now('recent') }
      .to have_enqueued_job(Crm::MetaAds::InsightsSyncJob).with(connection.id, 'recent')
  end

  it 'escopo desconhecido é erro' do
    expect { described_class.perform_now('ontem') }.to raise_error(ArgumentError)
  end
end
