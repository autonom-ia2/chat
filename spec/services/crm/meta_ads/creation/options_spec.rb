require 'rails_helper'

# Opções de criar (#2198, pontos 8 e 12): o que a pessoa escolhe e só os destinos e lugares que a chamada real confirmou.
RSpec.describe Crm::MetaAds::Creation::Options do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_permissions(*granted)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: granted.map { |name| { permission: name, status: 'granted' } } }.to_json, headers: json)
  end

  def stub_pages(pages)
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including('fields' => Meta::AdsGraphClient::PAGES_FIELDS))
                                                     .to_return(status: 200, body: { data: pages }.to_json, headers: json)
  end

  def stub_images(status: 200)
    body = status == 200 ? { data: [{ hash: 'abc', url: 'https://scontent.example/abc.jpg', width: 600, height: 600 }] } : meta_graph_error(1)
    stub_request(:get, meta_graph_url("act_#{connection.ad_account_id}/adimages"))
      .with(query: hash_including('fields' => Meta::AdsGraphClient::IMAGE_FIELDS)).to_return(status: status, body: body.to_json, headers: json)
  end

  def stub_currency(status: 200)
    body = status == 200 ? { currency: 'BRL' } : meta_graph_error(1)
    stub_request(:get, meta_graph_url("act_#{connection.ad_account_id}")).with(query: hash_including({}))
                                                                         .to_return(status: status, body: body.to_json, headers: json)
  end

  before do
    create(:channel_whatsapp, account: account, phone_number: '+5511900002161', validate_provider_config: false, sync_templates: false)
    stub_currency
  end

  it 'traz Páginas, Instagram da Página, números da conta, fotos já usadas, limites, moeda, hoje no fuso da conta e só o confirmado' do
    travel_to Time.zone.parse('2026-10-28 01:30:00 UTC')
    stub_permissions('ads_read', 'ads_management', 'pages_manage_ads', 'pages_show_list')
    stub_pages([{ id: '110', name: 'Loja Exemplo', instagram_business_account: { id: '178', username: 'lojaexemplo' } }])
    stub_images

    payload = described_class.new(account, connection).payload

    expect(payload).to include(
      needs_login: false, pages: [{ id: '110', name: 'Loja Exemplo', instagram: { id: '178', username: 'lojaexemplo' } }],
      whatsapp_numbers: [{ id: '+5511900002161', name: account.inboxes.first.name, phone: '+5511900002161' }],
      images: [{ hash: 'abc', url: 'https://scontent.example/abc.jpg', width: 600, height: 600 }],
      currency: 'BRL', min_daily: 6, max_daily: 500, kinds: %w[ad post],
      # 01:30 UTC de 28/10 ainda é 27/10 no fuso da conta de anúncios (São Paulo).
      today: '2026-10-27',
      destinations: %w[WHATSAPP WEBSITE],
      placements_by_destination: { 'WHATSAPP' => %w[AUTO], 'WEBSITE' => %w[AUTO INSTAGRAM FACEBOOK] }
    )
    expect(payload[:facebook_login]).to eq(Crm::MetaAds::FacebookLogin.public_payload)
  end

  it 'sem pages_manage_ads: pede para entrar de novo e não lê Páginas nem fotos' do
    stub_permissions('ads_read', 'ads_management')

    payload = described_class.new(account, connection).payload

    expect(payload).to include(needs_login: true, pages: [], images: [], currency: nil, today: nil)
    expect(a_request(:get, meta_graph_url('me/accounts'))).not_to have_been_made
  end

  it 'queda da Meta ao ler permissões é erro, não pedido de entrar de novo' do
    stub_request(:get, meta_graph_url('me/permissions')).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)

    expect { described_class.new(account, connection).payload }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_unavailable') }
  end

  it 'sem conseguir ler a moeda: erro, nunca real presumido' do
    stub_permissions('ads_management', 'pages_manage_ads')
    stub_pages([])
    stub_images
    stub_currency(status: 500)

    expect { described_class.new(account, connection).payload }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_unavailable') }
  end

  it 'modo parceiro sempre pede para entrar com o Facebook' do
    connection.update!(mode: 'partner', access_token: nil)

    expect(described_class.new(account, connection).payload).to include(needs_login: true)
  end

  it 'falha ao ler as fotos não derruba as opções' do
    stub_permissions('ads_management', 'pages_manage_ads')
    stub_pages([])
    stub_images(status: 500)

    expect(described_class.new(account, connection).payload).to include(images: [], pages: [])
  end
end
