require 'rails_helper'

# Comentário novo no Instagram (#2196, campo `comments` do webhook, roteado pela infra #2200): vira o evento comum
# `meta_ads.comment_received` para quem cuida dos comentários (#2212). Contrato único: (instagram_id, field, value_ids,
# time), com o hash que o enqueue_comment do #2287 monta. O evento sai só com ids (#2327): quem consome lê o texto e o
# autor na Graph. O eco da própria conta,
# Instagram sem caixa, conta sem a flag e o mesmo comentário repetido ficam de fora. Nada do comentário é gravado.
RSpec.describe Webhooks::InstagramCommentJob do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: ig_id) }
  let(:ig_id) { '17841400000000000' }
  let(:comment_id) { '17865799348089039' }
  let(:time) { 1_761_000_000 }
  # Exatamente o que Webhooks::InstagramEventsJob#enqueue_comment (#2287) manda.
  let(:value_ids) do
    { 'id' => comment_id, 'parent_id' => '17800000000000001', 'from' => { 'id' => '232323' },
      'media' => { 'id' => '123123', 'ad_id' => '999' } }
  end
  let(:graph) { %r{graph\.instagram\.com/v22\.0/#{comment_id}\?} }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:graph_comment) do
    { id: comment_id, text: 'Tem M?', timestamp: '2026-10-27T12:00:00+0000', parent_id: '17800000000000001',
      from: { id: '232323', username: 'carla.dias' }, media: { id: '123123' } }
  end

  before do
    account.enable_features!('meta_ads_comentarios_instagram')
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    stub_request(:get, graph).to_return(status: 200, headers: json, body: graph_comment.to_json)
  end

  after { Redis::Alfred.delete("instagram:comment_received:#{ig_id}:#{comment_id}") }

  it 'não grava os argumentos no log' do
    expect(described_class.log_arguments?).to be(false)
  end

  it 'contrato do #2287: lê o comentário na Graph e publica só os ids, com a caixa e o anúncio' do
    described_class.perform_now(ig_id, 'comments', value_ids, time)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      Events::Types::META_ADS_COMMENT_RECEIVED, kind_of(Time),
      {
        network: 'instagram', account_id: account.id, inbox_id: channel.inbox.id, instagram_id: ig_id,
        media_id: '123123', ad_id: '999', comment_id: comment_id, parent_id: '17800000000000001',
        from_id: '232323', created_time: Time.zone.at(time)
      }
    )
  end

  it 'transição (#2291): o value completo antigo ainda vale, só pelos ids' do
    described_class.perform_now(ig_id, 'comments', value_ids.merge('text' => 'ignorado', 'from' => { 'id' => '232323', 'username' => 'x' }),
                                time.to_s)

    expected = hash_including(comment_id: comment_id, ad_id: '999')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(anything, anything, expected)
  end

  # #2327: o payload vai aos argumentos do EventDispatcherJob (Redis e, às vezes, log). Texto e autor não entram.
  it 'o evento não leva o texto nem o username de quem comentou' do
    described_class.perform_now(ig_id, 'comments', value_ids.merge('text' => 'Tem M?'), time)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch) do |_name, _time, payload|
      expect(payload.keys).not_to include(:text, :from_name)
      expect(payload.values.map(&:to_s)).not_to include('Tem M?', 'carla.dias')
    end
  end

  it 'o mesmo comentário repetido (webhook reenviado) lê a Graph e publica uma vez só' do
    2.times { described_class.perform_now(ig_id, 'comments', value_ids, time) }

    expect(a_request(:get, graph)).to have_been_made.once
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once
  end

  it 'falha depois do dedupe solta a chave: o retry lê e publica' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_raise(RuntimeError).once
    expect { described_class.new.perform(ig_id, 'comments', value_ids, time) }.to raise_error(RuntimeError)

    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    described_class.new.perform(ig_id, 'comments', value_ids, time)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).twice
  end

  it 'desligamento do Sidekiq no meio (exceção fora de StandardError) também solta a chave' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_raise(Interrupt)
    expect { described_class.new.perform(ig_id, 'comments', value_ids, time) }.to raise_error(Interrupt)

    expect(Redis::Alfred.get("instagram:comment_received:#{ig_id}:#{comment_id}")).to be_nil
  end

  it 'Graph fora do ar sobe para o retry; sem permissão ou comentário apagado não publica e não prende a chave' do
    stub_request(:get, graph).to_return(status: 503, body: '{}').then
                             .to_return(status: 400, body: { error: { code: 190 } }.to_json).then
                             .to_return(status: 200, headers: json, body: graph_comment.to_json)

    expect { described_class.new.perform(ig_id, 'comments', value_ids, time) }.to raise_error(Instagram::CommentsClient::Unavailable)
    described_class.new.perform(ig_id, 'comments', value_ids, time)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)

    described_class.new.perform(ig_id, 'comments', value_ids, time)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).once
  end

  it 'ignora o eco da própria conta sem ler a Graph' do
    described_class.perform_now(ig_id, 'comments', value_ids.merge('from' => { 'id' => ig_id }), time)

    expect(a_request(:get, graph)).not_to have_been_made
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'ignora mentions, Instagram sem caixa e conta sem a flag, sem ler a Graph' do
    described_class.perform_now(ig_id, 'mentions', { 'comment_id' => '1', 'media_id' => '2' }, time)
    described_class.perform_now('17841499999999999', 'comments', value_ids, time)
    account.disable_features!('meta_ads_comentarios_instagram')
    described_class.perform_now(ig_id, 'comments', value_ids, time)

    expect(a_request(:get, graph)).not_to have_been_made
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'descarta ids fora do formato (comentário ou anúncio que não é só dígitos, tempo que não é número)' do
    [value_ids.merge('id' => 'c1?x=1'), value_ids.merge('media' => { 'ad_id' => '9?x' }), 'texto'].each do |body|
      described_class.perform_now(ig_id, 'comments', body, time)
    end
    described_class.perform_now(ig_id, 'comments', value_ids, 'ontem')

    expect(a_request(:get, /graph\.instagram\.com/).with { |r| !r.uri.path.end_with?('subscribed_apps') }).not_to have_been_made
  end
end
