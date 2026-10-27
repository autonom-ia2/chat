require 'rails_helper'

# Comentário novo no Instagram (#2196, campo `comments` do webhook, roteado pela infra #2200): vira o evento comum
# `meta_ads.comment_received` para quem cuida dos comentários (#2212). Do webhook só valem os ids; o texto e o autor vêm
# da Graph. O eco da própria conta, Instagram sem caixa e conta sem a flag ficam de fora. Nada do comentário é gravado.
RSpec.describe Webhooks::InstagramCommentJob do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: '17841400000000001') }
  let(:time) { 1_761_600_000 }
  let(:value) { { 'id' => 'c1', 'from' => { 'id' => '501' }, 'media' => { 'id' => '17900000000000001', 'ad_id' => '120254710382770416' } } }
  let(:graph_comment) do
    { id: 'c1', text: 'Tem M?', timestamp: '2026-10-27T12:00:00+0000', parent_id: 'c0', from: { id: '501', username: 'carla.dias' },
      media: { id: '17900000000000001' } }
  end

  before do
    account.enable_features!('meta_ads_comentarios_instagram')
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    stub_request(:get, %r{graph\.instagram\.com/v22\.0/c1\?})
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: graph_comment.to_json)
  end

  def graph_read
    a_request(:get, %r{graph\.instagram\.com/v22\.0/c1\?})
  end

  it 'não grava os argumentos no log' do
    expect(described_class.log_arguments?).to be(false)
  end

  it 'lê o texto e o autor na Graph e publica no evento comum, com a caixa e o anúncio do webhook' do
    described_class.perform_now('17841400000000001', 'comments', value, time)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      Events::Types::META_ADS_COMMENT_RECEIVED, kind_of(Time),
      {
        network: 'instagram', account_id: account.id, inbox_id: channel.inbox.id, instagram_id: '17841400000000001',
        media_id: '17900000000000001', ad_id: '120254710382770416', comment_id: 'c1', parent_id: 'c0',
        from_id: '501', from_name: 'carla.dias', text: 'Tem M?', created_time: Time.zone.at(time)
      }
    )
  end

  it 'aceita o value só com o id do comentário' do
    described_class.perform_now('17841400000000001', 'comments', { 'id' => 'c1' }, time.to_s)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(anything, anything, hash_including(text: 'Tem M?', ad_id: nil, media_id: '17900000000000001', created_time: Time.zone.at(time)))
  end

  it 'ignora o eco da própria conta sem ler a Graph' do
    described_class.perform_now('17841400000000001', 'comments', value.merge('from' => { 'id' => '17841400000000001' }), time)

    expect(graph_read).not_to have_been_made
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'ignora Instagram sem caixa, conta sem a flag e outros campos, sem ler a Graph' do
    described_class.perform_now('17841499999999999', 'comments', value, time)
    described_class.perform_now('17841400000000001', 'mentions', value, time)
    account.disable_features!('meta_ads_comentarios_instagram')
    described_class.perform_now('17841400000000001', 'comments', value, time)

    expect(graph_read).not_to have_been_made
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'descarta corpo fora do formato sem quebrar' do
    [['texto', time], [value, { 'a' => 1 }], [value.except('id'), time]].each do |body, at|
      described_class.perform_now('17841400000000001', 'comments', body, at)
    end

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'comentário que a Graph não acha (apagado) não publica; Graph fora do ar sobe para o retry' do
    stub_request(:get, %r{graph\.instagram\.com/v22\.0/c1\?}).to_return(status: 400, body: { error: { code: 100 } }.to_json)
    described_class.perform_now('17841400000000001', 'comments', value, time)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)

    stub_request(:get, %r{graph\.instagram\.com/v22\.0/c1\?}).to_return(status: 503, body: '{}')
    expect { described_class.new.perform('17841400000000001', 'comments', value, time) }
      .to raise_error(Instagram::CommentsClient::Unavailable)
  end
end
