require 'rails_helper'

# Imagem de cada anúncio no formato dele (#1088): imagem original do criativo; vídeo pede a miniatura grande.
RSpec.describe Crm::MetaAds::AdImages do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ads_url) { meta_graph_url("act_#{connection.ad_account_id}/ads") }
  let(:known_at) { Time.zone.parse('2026-10-05T10:00:00Z') }

  def stub_ads(rows, status: 200)
    body = status == 200 ? { data: rows } : meta_graph_error(100, 'Object does not exist')
    stub_request(:get, ads_url).with(query: hash_including('fields' => Meta::AdsGraphClient::AD_CREATIVE_FIELDS))
                               .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_video(creative_id, status: 200, url: nil)
    stub_request(:get, meta_graph_url(creative_id))
      .with(query: hash_including('fields' => 'thumbnail_url', 'thumbnail_width' => '1080', 'thumbnail_height' => '1080'))
      .to_return(status: status, body: (status == 200 ? { thumbnail_url: url } : {}).to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def ad(id, creative, name: "Anúncio #{id}")
    { id: id, name: name, adset_id: '120254710067060777', campaign_id: '120254710067060416', creative: creative }.compact
  end

  def known_ad(id)
    Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: 'ad', name: 'Capa', campaign_id: '1202547100',
                              preview_url: 'https://fb.me/adspreview/abc', thumbnail_url: 'https://scontent/64px.jpg', fetched_at: known_at)
  end

  it 'guarda a imagem original do anúncio e, para vídeo, a miniatura de 1080 px, sem apagar a prévia' do
    travel_to(Time.zone.parse('2026-10-07T12:00:00Z')) do
      known_ad('120254710362980416')
      stub_ads([ad('120254710362980416', { id: '9001', image_url: 'https://scontent/capa-1080x1350.jpg',
                                           thumbnail_url: 'https://scontent/64px.jpg' }),
                ad('120254710067050416', { id: '9002', thumbnail_url: 'https://scontent/video-64px.jpg' })])
      video = stub_video('9002', url: 'https://scontent/video-1080.jpg')

      expect(described_class.new(connection).refresh!).to eq(2)

      capa = Crm::MetaAdObject.find_by!(meta_object_id: '120254710362980416')
      expect(capa).to have_attributes(thumbnail_url: 'https://scontent/capa-1080x1350.jpg', preview_url: 'https://fb.me/adspreview/abc',
                                      name: 'Anúncio 120254710362980416', campaign_id: '120254710067060416', fetched_at: known_at)
      expect(Crm::MetaAdObject.find_by!(meta_object_id: '120254710067050416'))
        .to have_attributes(thumbnail_url: 'https://scontent/video-1080.jpg', object_type: 'ad', fetched_at: nil)
      expect(video).to have_been_requested.once
    end
  end

  it 'o que a Meta não mandou (nome, imagem grande) não apaga o que a linha já tinha' do
    known_ad('120254710067050416')
    stub_ads([ad('120254710067050416', { id: '9002', image_url: 'http://inseguro/x.jpg', thumbnail_url: 'https://scontent/outra.jpg' },
                 name: nil)])
    stub_video('9002', status: 500)
    allow(Rails.logger).to receive(:warn)

    expect(described_class.new(connection).refresh!).to eq(0)

    expect(Crm::MetaAdObject.find_by!(meta_object_id: '120254710067050416'))
      .to have_attributes(name: 'Capa', thumbnail_url: 'https://scontent/64px.jpg', fetched_at: known_at)
  end

  it 'pede a miniatura grande de no máximo MAX_VIDEO_THUMBNAILS vídeos por rodada' do
    stub_const("#{described_class}::MAX_VIDEO_THUMBNAILS", 1)
    stub_ads([ad('120254710067050416', { id: '9002' }), ad('120254710067050417', { id: '9003' })])
    first = stub_video('9002', url: 'https://scontent/v1.jpg')
    second = stub_video('9003', url: 'https://scontent/v2.jpg')

    expect(described_class.new(connection).refresh!).to eq(1)
    expect(first).to have_been_requested.once
    expect(second).not_to have_been_requested
  end

  it 'conta de anúncios sem acesso segue a regra da coleta' do
    allow(Rails.logger).to receive(:warn)
    stub_ads([], status: 400)

    expect(described_class.new(connection).refresh!).to be_nil
    expect(connection.reload).to have_attributes(status: 'invalid', last_error: 'ad_account_access_lost')
  end
end
