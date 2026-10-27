require 'rails_helper'

# Webhook `feed` da Página (#2197): comentário novo em post da Página vira o evento comum `meta_ads.comment_received`
# (consumido pelo #2212), uma vez por conta dona da Página com a flag ligada. Eco da própria Página, outros itens
# (curtida, post), edição/remoção e Página desconhecida são ignorados.
RSpec.describe Webhooks::FacebookFeedJob do
  let(:account) { create(:account) }
  let(:page_id) { '100000000000001' }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:dispatcher) { instance_double(Dispatcher, dispatch: true) }
  let(:value) do
    {
      'item' => 'comment', 'verb' => 'add', 'post_id' => post_id, 'parent_id' => post_id,
      'comment_id' => '200000000000002_300000000000003', 'created_time' => 1_761_566_400,
      'from' => { 'id' => '555', 'name' => 'Mariana Costa' }, 'message' => 'Ainda tem no M?'
    }
  end

  before do
    account.enable_features!('meta_ads_comentarios_facebook')
    simulate_meta_ads_comment_pieces(account_ids: [account.id])
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
  end

  it 'comentário de primeiro nível vira meta_ads.comment_received para a conta da Página' do
    described_class.perform_now(page_id, value, 1_761_566_401)

    expect(dispatcher).to have_received(:dispatch).with(
      'meta_ads.comment_received', kind_of(Time),
      network: 'facebook', account_id: account.id, inbox_id: nil, page_id: page_id, post_id: post_id, ad_id: nil,
      comment_id: '200000000000002_300000000000003', parent_id: nil, from_id: '555', from_name: 'Mariana Costa',
      text: 'Ainda tem no M?', created_time: Time.zone.at(1_761_566_400)
    ).once
  end

  it 'resposta leva o comentário pai; com caixa do Messenger da Página, leva o inbox_id' do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe)
    inbox = create(:channel_facebook_page, account: account, page_id: page_id).inbox

    described_class.perform_now(page_id, value.merge('parent_id' => '200000000000002_9', 'comment_id' => '200000000000002_10'), 0)

    expect(dispatcher).to have_received(:dispatch).with(
      'meta_ads.comment_received', anything, hash_including(parent_id: '200000000000002_9', inbox_id: inbox.id)
    )
  end

  it 'ignora o eco da própria Página, outros itens e verbos, Página sem dono e conta sem a flag' do
    described_class.perform_now(page_id, value.merge('from' => { 'id' => page_id, 'name' => 'Loja' }), 0)
    described_class.perform_now(page_id, value.merge('item' => 'reaction'), 0)
    described_class.perform_now(page_id, value.merge('verb' => 'remove'), 0)
    described_class.perform_now(page_id, 'não é hash', 0)

    allow(Crm::MetaAdsPage).to receive(:account_ids_for).and_return([])
    described_class.perform_now(page_id, value, 0)

    allow(Crm::MetaAdsPage).to receive(:account_ids_for).and_return([account.id])
    account.disable_features!('meta_ads_comentarios_facebook')
    described_class.perform_now(page_id, value, 0)

    expect(dispatcher).not_to have_received(:dispatch)
  end
end
