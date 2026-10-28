require 'rails_helper'

# Webhook `feed` da Página (#2197): comentário novo em post da Página vira o evento comum `meta_ads.comment_received`
# (consumido pelo #2212), uma vez por conta dona da Página com a flag ligada. Nos argumentos do job só vão os ids; o
# texto e o nome são lidos na Graph com o token da Página. Eco da própria Página, outros itens (curtida, post),
# edição/remoção, Página desconhecida e webhook reenviado são ignorados.
RSpec.describe Webhooks::FacebookFeedJob do
  let(:account) { create(:account) }
  let(:page_id) { '100000000000001' }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:comment_id) { '200000000000002_300000000000003' }
  let(:dispatcher) { instance_double(Dispatcher, dispatch: true) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:webhook) do
    {
      'item' => 'comment', 'verb' => 'add', 'post_id' => post_id, 'parent_id' => post_id, 'comment_id' => comment_id,
      'created_time' => 1_761_566_400, 'from' => { 'id' => '555', 'name' => 'Mariana Costa' }, 'message' => 'Ainda tem no M?'
    }
  end
  let(:value) { described_class.webhook_value(webhook) }

  before do
    account.enable_features!('meta_ads_comentarios_facebook')
    create_meta_ads_insights_connection(account)
    simulate_meta_ads_comment_pieces(account: account, page_id: page_id)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, headers: json, body: { data: [{ permission: 'pages_read_user_content', status: 'granted' }] }.to_json)
    stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token,name' })
                                               .to_return(status: 200, body: { access_token: 'PAGETOKEN123' }.to_json, headers: json)
  end

  after { Redis::Alfred.delete("facebook:comment_received:#{account.id}:#{comment_id}") }

  def stub_comment(status: 200, body: { id: comment_id, from: { id: '555', name: 'Mariana Costa' }, message: 'Ainda tem no M?' })
    stub_request(:get, meta_graph_url(comment_id)).with(query: hash_including({}))
                                                  .to_return(status: status, body: body.to_json, headers: json)
  end

  it 'nos argumentos do job vão só os ids: nem o texto nem o nome de quem comentou' do
    expect(value).to eq('item' => 'comment', 'verb' => 'add', 'post_id' => post_id, 'parent_id' => post_id,
                        'comment_id' => comment_id, 'created_time' => 1_761_566_400, 'from_id' => '555')
    expect(described_class.log_arguments?).to be(false)
  end

  it 'comentário de primeiro nível vira meta_ads.comment_received, com o texto lido na Graph, uma vez só' do
    read = stub_comment

    described_class.perform_now(page_id, value, 1_761_566_401)
    described_class.perform_now(page_id, value, 1_761_566_401)

    expect(dispatcher).to have_received(:dispatch).with(
      'meta_ads.comment_received', kind_of(Time),
      network: 'facebook', account_id: account.id, inbox_id: nil, page_id: page_id, post_id: post_id, ad_id: nil,
      comment_id: comment_id, parent_id: nil, from_id: '555', from_name: 'Mariana Costa',
      text: 'Ainda tem no M?', created_time: Time.zone.at(1_761_566_400)
    ).once
    expect(read).to have_been_requested.once
  end

  it 'resposta leva o comentário pai; com caixa do Messenger da Página, leva o inbox_id' do
    stub_comment
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe)
    inbox = create(:channel_facebook_page, account: account, page_id: page_id).inbox

    described_class.perform_now(page_id, value.merge('parent_id' => '200000000000002_9'), 0)

    expect(dispatcher).to have_received(:dispatch).with(
      'meta_ads.comment_received', anything, hash_including(parent_id: '200000000000002_9', inbox_id: inbox.id)
    )
  end

  it 'Meta fora do ar sobe para o retry e solta o dedupe, para a nova tentativa ler de novo' do
    stub_comment(status: 500, body: { error: { code: 1, message: 'x' } })
    allow(Rails.logger).to receive(:warn)

    expect { described_class.perform_now(page_id, value, 0) }
      .to raise_error(Crm::MetaAds::FacebookComments::Error, 'meta_unavailable')
    stub_comment
    described_class.perform_now(page_id, value, 0)

    expect(dispatcher).to have_received(:dispatch).once
  end

  it 'ignora o eco da própria Página, outros itens e verbos, Página sem dono, conta sem a flag ou sem conexão' do
    read = stub_comment
    described_class.perform_now(page_id, value.merge('from_id' => page_id), 0)
    described_class.perform_now(page_id, value.merge('item' => 'reaction'), 0)
    described_class.perform_now(page_id, value.merge('verb' => 'remove'), 0)
    described_class.perform_now(page_id, 'não é hash', 0)
    described_class.perform_now('999', value, 0)

    Crm::MetaAdsConnection.where(account_id: account.id).find_each { |connection| connection.update!(status: 'invalid') }
    described_class.perform_now(page_id, value, 0)

    account.disable_features!('meta_ads_comentarios_facebook')
    described_class.perform_now(page_id, value, 0)

    expect(dispatcher).not_to have_received(:dispatch)
    expect(read).not_to have_been_requested
  end
end
