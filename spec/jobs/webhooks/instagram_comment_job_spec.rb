require 'rails_helper'

# Comentário novo no Instagram (#2196, campo `comments` do webhook, roteado pela infra #2200): vira o evento comum
# `meta_ads.comment_received` para quem cuida dos comentários (#2212). O eco da própria conta e o comentário de
# Instagram sem caixa ficam de fora. Nada do comentário é gravado.
RSpec.describe Webhooks::InstagramCommentJob do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: '17841400000000001') }
  let(:time) { 1_761_600_000 }
  let(:value) do
    { 'from' => { 'id' => '501', 'username' => 'carla.dias' }, 'id' => 'c1', 'parent_id' => 'c0', 'text' => 'Tem M?',
      'media' => { 'id' => '17900000000000001', 'media_product_type' => 'FEED', 'ad_id' => '120254710382770416' } }
  end

  before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

  it 'não grava os argumentos (texto e autor do comentário) no log' do
    expect(described_class.log_arguments?).to be(false)
  end

  it 'publica o comentário no evento comum, com a caixa e o anúncio' do
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

  it 'ignora o eco da própria conta' do
    described_class.perform_now('17841400000000001', 'comments', value.merge('from' => { 'id' => '17841400000000001', 'username' => 'loja' }), time)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'ignora Instagram sem caixa na plataforma' do
    described_class.perform_now('17841499999999999', 'comments', value, time)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'descarta corpo fora do formato sem quebrar' do
    [['comments', 'texto', time], ['comments', value.merge('from' => 'x'), time], ['comments', value, { 'a' => 1 }],
     ['comments', value.except('id'), time]].each do |field, body, at|
      described_class.perform_now('17841400000000001', field, body, at)
    end

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'aceita o tempo em texto, como pode chegar pelo relay' do
    described_class.perform_now('17841400000000001', 'comments', value, time.to_s)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(anything, anything, hash_including(created_time: Time.zone.at(time)))
  end

  it 'ignora outros campos (mentions)' do
    described_class.perform_now('17841400000000001', 'mentions', value, time)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end

  it 'comentário sem anúncio e sem resposta segue com ad_id e parent_id nulos' do
    described_class.perform_now('17841400000000001', 'comments', value.except('parent_id').merge('media' => { 'id' => '1790' }), time)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(anything, anything, hash_including(ad_id: nil, parent_id: nil, media_id: '1790'))
  end
end
