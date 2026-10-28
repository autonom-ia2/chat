require 'rails_helper'

# Webhook `feed` da Página (#2197): comentário novo em post da Página vira o evento comum `meta_ads.comment_received`
# (consumido pelo #2212), uma vez por conta dona da Página com a flag ligada. Nos argumentos do job e no payload do
# evento vão só ids: o texto e o nome de quem comentou nunca entram (o evento passa pelo EventDispatcherJob, que o
# Sidekiq guarda no Redis). Quem consome lê por Crm::MetaAds::FacebookComments#comment. Eco da própria Página, outros
# itens (curtida, post), edição/remoção, Página desconhecida e webhook reenviado são ignorados.
RSpec.describe Webhooks::FacebookFeedJob do
  let(:account) { create(:account) }
  let(:page_id) { '100000000000001' }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:comment_id) { '200000000000002_300000000000003' }
  let(:dispatcher) { instance_double(Dispatcher, dispatch: true) }
  let(:webhook) do
    {
      'item' => 'comment', 'verb' => 'add', 'post_id' => post_id, 'parent_id' => post_id, 'comment_id' => comment_id,
      'created_time' => 1_761_566_400, 'from' => { 'id' => '555', 'name' => 'Mariana Costa' }, 'message' => 'Ainda tem no M?'
    }
  end
  let(:value) { described_class.webhook_value(webhook) }

  before do
    account.enable_features!('meta_ads_comentarios_facebook')
    simulate_meta_ads_comment_pieces(account: account, page_id: page_id)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
  end

  after { Redis::Alfred.delete("facebook:comment_received:#{account.id}:#{comment_id}") }

  it 'nos argumentos do job vão só os ids: nem o texto nem o nome de quem comentou' do
    expect(value).to eq('item' => 'comment', 'verb' => 'add', 'post_id' => post_id, 'parent_id' => post_id,
                        'comment_id' => comment_id, 'created_time' => 1_761_566_400, 'from_id' => '555')
    expect(described_class.log_arguments?).to be(false)
  end

  it 'comentário de primeiro nível vira meta_ads.comment_received só com ids, uma vez só, sem chamar a Meta' do
    described_class.perform_now(page_id, value, 1_761_566_401)
    described_class.perform_now(page_id, value, 1_761_566_401)

    expect(dispatcher).to have_received(:dispatch).with(
      'meta_ads.comment_received', kind_of(Time),
      network: 'facebook', account_id: account.id, inbox_id: nil, page_id: page_id, post_id: post_id, ad_id: nil,
      comment_id: comment_id, parent_id: nil, from_id: '555', created_time: Time.zone.at(1_761_566_400)
    ).once
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'o texto e o nome de quem comentou nunca entram no payload (passa pelo Redis do Sidekiq)' do
    described_class.perform_now(page_id, value.merge('message' => 'Ainda tem no M?', 'from_name' => 'Mariana Costa'), 0)

    expect(dispatcher).to have_received(:dispatch) do |_, _, payload|
      expect(payload.keys).not_to include(:text, :from_name, :message)
      expect(payload.to_json).not_to include('Ainda tem', 'Mariana')
    end
  end

  it 'resposta leva o comentário pai; com caixa do Messenger da Página, leva o inbox_id' do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe)
    inbox = create(:channel_facebook_page, account: account, page_id: page_id).inbox

    described_class.perform_now(page_id, value.merge('parent_id' => '200000000000002_9'), 0)

    expect(dispatcher).to have_received(:dispatch).with(
      'meta_ads.comment_received', anything, hash_including(parent_id: '200000000000002_9', inbox_id: inbox.id)
    )
  end

  it 'erro numa conta não tira o evento das outras, vai ao rastreador e solta o dedupe dela' do
    other = create(:account)
    other.enable_features!('meta_ads_comentarios_facebook')
    Crm::MetaAdsPage.create!(account: other, page_id: page_id)
    allow(dispatcher).to receive(:dispatch) { |_, _, payload| raise 'listener caiu' if payload[:account_id] == account.id }
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(page_id, value, 0)

    expect(dispatcher).to have_received(:dispatch).with(anything, anything, hash_including(account_id: other.id))
    expect(tracker).to have_received(:capture_exception).once
    expect(Redis::Alfred.get("facebook:comment_received:#{account.id}:#{comment_id}")).to be_nil
    Redis::Alfred.delete("facebook:comment_received:#{other.id}:#{comment_id}")
  end

  it 'ignora o eco da própria Página, outros itens e verbos, Página sem dono e conta sem a flag' do
    described_class.perform_now(page_id, value.merge('from_id' => page_id), 0)
    described_class.perform_now(page_id, value.merge('item' => 'reaction'), 0)
    described_class.perform_now(page_id, value.merge('verb' => 'remove'), 0)
    described_class.perform_now(page_id, 'não é hash', 0)
    described_class.perform_now('999', value, 0)

    account.disable_features!('meta_ads_comentarios_facebook')
    described_class.perform_now(page_id, value, 0)

    expect(dispatcher).not_to have_received(:dispatch)
  end
end
