require 'rails_helper'

# "Teve anúncio" sem depender de abrir Anúncios (#2804): de hora em hora, todos os anúncios criados aqui a partir de um
# post e ainda esperando ativar (não só os 20 da lista de pausados) são lidos na Meta; ligado lá, ganha `activated_at`.
# A mídia do anúncio no Instagram fica guardada para o "Esperando você".
RSpec.describe Crm::MetaAds::Creation::ActivationSweep do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  def boosted(ad_id, network: 'instagram', at: 1.day.ago, **attributes)
    Crm::MetaAdsCreatedObject.create!({ account: account, idempotency_key: "k#{ad_id}", status: 'created', name: "Anúncio #{ad_id}", ad_id: ad_id,
                                        ad_account_id: connection.ad_account_id, source_post_id: "p#{ad_id}", source_post_network: network,
                                        created_at: at }.merge(attributes))
  end

  def stub_ad(ad_id, status, http: 200, media: "77#{ad_id}")
    body = if http == 200
             { id: ad_id, status: status, effective_status: status, creative: { effective_instagram_media_id: media } }
           else
             meta_graph_error(2)
           end
    stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                             .to_return(status: http, body: body.to_json, headers: json)
  end

  it 'lê mais que os 20 da lista de pausados: o ligado no Gerenciador ganha activated_at, o pausado não' do
    records = (1..25).map { |n| boosted(n.to_s, at: n.hours.ago) }
    (1..24).each { |n| stub_ad(n.to_s, 'PAUSED') }
    stub_ad('25', 'ACTIVE')

    described_class.new(connection).perform

    expect(records.last.reload.activated_at).to be_present
    expect(records.first(24).map { |record| record.reload.activated_at }).to all(be_nil)
  end

  it 'guarda a mídia do anúncio do Instagram, também do já ativado que ainda não a tem, e não relê quem já tem' do
    waiting = boosted('1')
    activated = boosted('2', activated_at: 1.hour.ago)
    known = boosted('3', activated_at: 1.hour.ago)
    Crm::MetaAds::Creation::AdMedia.remember(known, { 'creative' => { 'effective_instagram_media_id' => '773' } })
    stub_ad('1', 'PAUSED')
    stub_ad('2', 'ACTIVE')

    described_class.new(connection).perform

    expect(Crm::MetaAds::Creation::AdMedia.of(account.id, [waiting.ad_id, activated.ad_id, known.ad_id]))
      .to eq('1' => '771', '2' => '772', '3' => '773')
    expect(a_request(:get, meta_graph_url('3')).with(query: hash_including({}))).not_to have_been_made
  end

  it 'rodízio: anúncio lido não é lido de novo na rodada seguinte; o de mais de 2 dias espera mais' do
    novo = boosted('1', at: 1.day.ago)
    velho = boosted('2', at: 10.days.ago)
    stub_ad('1', 'PAUSED')
    stub_ad('2', 'PAUSED')

    described_class.new(connection).perform
    described_class.new(connection).perform
    expect(a_request(:get, meta_graph_url(novo.ad_id)).with(query: hash_including({}))).to have_been_made.once

    travel 1.hour do
      described_class.new(connection).perform
    end
    expect(a_request(:get, meta_graph_url(novo.ad_id)).with(query: hash_including({}))).to have_been_made.twice
    expect(a_request(:get, meta_graph_url(velho.ad_id)).with(query: hash_including({}))).to have_been_made.once
  end

  it 'com um clique de Ativar ou Pausar em andamento, não lê; travado há mais de 3 minutos, lê' do
    boosted('1', switching_at: 1.minute.ago)
    boosted('2', switching_at: 10.minutes.ago)
    stub_ad('2', 'PAUSED')

    described_class.new(connection).perform

    expect(a_request(:get, meta_graph_url('1')).with(query: hash_including({}))).not_to have_been_made
    expect(a_request(:get, meta_graph_url('2')).with(query: hash_including({}))).to have_been_made.once
  end

  it 'token recusado para a rodada' do
    boosted('1', at: 1.hour.ago)
    boosted('2', at: 2.hours.ago)
    stub_request(:get, meta_graph_url('1')).with(query: hash_including({}))
                                           .to_return(status: 400, body: meta_graph_error(190).to_json, headers: json)

    described_class.new(connection).perform

    expect(a_request(:get, meta_graph_url('2')).with(query: hash_including({}))).not_to have_been_made
  end

  it 'mídia que não é um id da Graph não é guardada' do
    boosted('1')
    stub_ad('1', 'PAUSED', media: '../me')

    described_class.new(connection).perform

    expect(Crm::MetaAds::Creation::AdMedia.of(account.id, ['1'])).to eq({})
  end

  it 'Facebook: grava a ativação, sem mídia do Instagram; já ativado nem é lido' do
    waiting = boosted('1', network: 'facebook')
    boosted('2', network: 'facebook', activated_at: 1.hour.ago)
    stub_ad('1', 'ACTIVE')

    described_class.new(connection).perform

    expect(waiting.reload.activated_at).to be_present
    expect(Crm::MetaAds::Creation::AdMedia.of(account.id, ['1'])).to eq({})
    expect(a_request(:get, meta_graph_url('2')).with(query: hash_including({}))).not_to have_been_made
  end

  it 'fora: outra conta de anúncios, sem post de origem, não criado e mais velho que 90 dias' do
    boosted('1', ad_account_id: 'act_outra')
    boosted('2', source_post_id: nil)
    boosted('3', status: 'rolled_back')
    boosted('4', at: 91.days.ago)

    allow(Meta::AdsGraphClient).to receive(:new).and_call_original

    described_class.new(connection).perform

    expect(Meta::AdsGraphClient).not_to have_received(:new)
  end

  it 'Meta fora para a rodada: o seguinte nem é lido, e a próxima rodada tenta de novo' do
    first = boosted('1', at: 1.hour.ago)
    boosted('2', at: 2.hours.ago)
    stub_ad('1', nil, http: 503)

    described_class.new(connection).perform

    expect(first.reload.activated_at).to be_nil
    expect(a_request(:get, meta_graph_url('2')).with(query: hash_including({}))).not_to have_been_made
  end

  it 'falha ao gravar vai ao rastreador e a rodada segue' do
    boosted('1', at: 1.hour.ago)
    boosted('2', at: 2.hours.ago)
    stub_ad('1', 'ACTIVE')
    stub_ad('2', 'ACTIVE')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow_any_instance_of(Crm::MetaAdsCreatedObject).to receive(:update!).and_raise(ActiveRecord::StatementInvalid) # rubocop:disable RSpec/AnyInstance

    described_class.new(connection).perform

    expect(tracker).to have_received(:capture_exception).twice
  end
end
