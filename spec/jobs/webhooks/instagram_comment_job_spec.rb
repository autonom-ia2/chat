require 'rails_helper'

# Comentário novo no Instagram (#2196, campo `comments` do webhook, roteado pela infra #2200): vira o evento comum
# `meta_ads.comment_received` para quem cuida dos comentários (#2212). O job recebe só ids
# (instagram_id, comment_id, time, ad_id); o texto e o autor vêm da Graph. O eco da própria conta, Instagram sem caixa,
# conta sem a flag e o mesmo comentário repetido ficam de fora. Nada do comentário é gravado.
RSpec.describe Webhooks::InstagramCommentJob do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: '17841400000000001') }
  let(:ig_id) { '17841400000000001' }
  let(:comment_id) { '18000000000000001' }
  let(:time) { 1_761_600_000 }
  let(:graph) { %r{graph\.instagram\.com/v22\.0/#{comment_id}\?} }
  let(:graph_comment) do
    { id: comment_id, text: 'Tem M?', timestamp: '2026-10-27T12:00:00+0000', parent_id: '18000000000000000',
      from: { id: '501', username: 'carla.dias' }, media: { id: '17900000000000001' } }
  end

  before do
    account.enable_features!('meta_ads_comentarios_instagram')
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    stub_request(:get, graph).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: graph_comment.to_json)
  end

  after { Redis::Alfred.delete("instagram:comment_received:#{ig_id}:#{comment_id}") }

  it 'não grava os argumentos no log' do
    expect(described_class.log_arguments?).to be(false)
  end

  it 'contrato: só ids; lê texto e autor na Graph e publica com a caixa e o anúncio' do
    described_class.perform_now(ig_id, comment_id, time, '120254710382770416')

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      Events::Types::META_ADS_COMMENT_RECEIVED, kind_of(Time),
      {
        network: 'instagram', account_id: account.id, inbox_id: channel.inbox.id, instagram_id: ig_id,
        media_id: '17900000000000001', ad_id: '120254710382770416', comment_id: comment_id, parent_id: '18000000000000000',
        from_id: '501', from_name: 'carla.dias', text: 'Tem M?', created_time: Time.zone.at(time)
      }
    )
  end

  it 'formato antigo do roteador (field, value, time) ainda vale, só com os ids do value' do
    value = { 'id' => comment_id, 'text' => 'ignorado', 'media' => { 'id' => '1', 'ad_id' => '120254710382770416' } }
    described_class.perform_now(ig_id, 'comments', value, time.to_s)
    described_class.perform_now(ig_id, 'mentions', value, time)

    expected = hash_including(text: 'Tem M?', ad_id: '120254710382770416')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(anything, anything, expected)
  end

  it 'o mesmo comentário repetido (webhook reenviado) lê a Graph e publica uma vez só' do
    2.times { described_class.perform_now(ig_id, comment_id, time) }

    expect(a_request(:get, graph)).to have_been_made.once
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once
  end

  it 'ignora o eco da própria conta' do
    stub_request(:get, graph).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                        body: graph_comment.merge(from: { id: ig_id, username: 'loja' }).to_json)

    described_class.perform_now(ig_id, comment_id, time)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'ignora Instagram sem caixa e conta sem a flag, sem ler a Graph' do
    described_class.perform_now('17841499999999999', comment_id, time)
    account.disable_features!('meta_ads_comentarios_instagram')
    described_class.perform_now(ig_id, comment_id, time)

    expect(a_request(:get, graph)).not_to have_been_made
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'descarta ids fora do formato sem quebrar' do
    [['c1?x=1', time], [comment_id, 'ontem'], [nil, time]].each { |id, at| described_class.perform_now(ig_id, id, at) }

    expect(a_request(:get, /graph\.instagram\.com/).with { |r| !r.uri.path.end_with?('subscribed_apps') }).not_to have_been_made
  end

  it 'comentário apagado não publica; Graph fora do ar sobe para o retry e o retry lê de novo' do
    stub_request(:get, graph).to_return(status: 503, body: '{}').then
                             .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: graph_comment.to_json)

    expect { described_class.new.perform(ig_id, comment_id, time) }.to raise_error(Instagram::CommentsClient::Unavailable)
    described_class.new.perform(ig_id, comment_id, time)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once

    Redis::Alfred.delete("instagram:comment_received:#{ig_id}:#{comment_id}")
    stub_request(:get, graph).to_return(status: 400, body: { error: { code: 100 } }.to_json)
    described_class.new.perform(ig_id, comment_id, time)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once
  end
end
