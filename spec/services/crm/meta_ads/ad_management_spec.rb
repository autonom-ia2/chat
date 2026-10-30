require 'rails_helper'

# Gestão mínima do anúncio (#2161): situação, pausar/ativar só com ads_management e só em anúncio da conta da
# conexão, post da Página (com o token da Página quando o do cliente não lê) e Páginas concedidas.
RSpec.describe Crm::MetaAds::AdManagement do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_id) { '120254710382770416' }
  let(:post_id) { '100000000000001_200000000000002' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_permissions(*granted)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: granted.map { |name| { permission: name, status: 'granted' } } }.to_json, headers: json)
  end

  def stub_ad(account_id: connection.ad_account_id, status: 'ACTIVE', effective: 'ACTIVE', story: post_id, http: 200)
    body = if http == 200
             { id: ad_id, name: 'Capa', account_id: account_id, status: status, effective_status: effective,
               creative: { id: '9', effective_object_story_id: story }.compact }
           else
             meta_graph_error(http == 500 ? 1 : 100)
           end
    stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                             .to_return(status: http, body: body.to_json, headers: json)
  end

  def post_body
    { message: 'Seu orçamento em 2 minutos.', created_time: '2026-10-01T17:20:00+0000', permalink_url: 'https://www.facebook.com/p/1',
      from: { name: 'Loja Exemplo' }, shares: { count: 6 },
      reactions: { data: [], summary: { total_count: 128 } }, comments: { data: [], summary: { total_count: 14 } } }
  end

  def stub_post(status: 200, token: MetaAdsHelpers::TEST_TOKEN)
    body = status == 200 ? post_body : meta_graph_error(10, 'pages_read_engagement')
    stub_request(:get, meta_graph_url(post_id)).with(query: { fields: Meta::AdsGraphClient::PAGE_POST_FIELDS },
                                                     headers: { 'Authorization' => "Bearer #{token}" })
                                               .to_return(status: status == 200 ? 200 : 403, body: body.to_json, headers: json)
  end

  describe '#payload' do
    it 'pede o nome do anúncio à Meta (o detalhe sem números não tem outro lugar de onde tirar, #2335)' do
      expect(Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS.split(',')).to include('name')
    end

    it 'traz a situação, a entrega, o post da Página e se pode mudar' do
      stub_permissions('ads_read', 'ads_management')
      stub_ad(effective: 'ADSET_PAUSED')
      stub_post

      expect(described_class.new(connection).payload(ad_id)).to eq(
        name: 'Capa', status: 'ACTIVE', effective_status: 'ADSET_PAUSED', in_review: false, mode: 'token', can_change: true,
        needs_login: false,
        post: { message: 'Seu orçamento em 2 minutos.', created_time: '2026-10-01T17:20:00+0000',
                permalink_url: 'https://www.facebook.com/p/1', page_name: 'Loja Exemplo', reactions: 128, comments: 14, shares: 6 }
      )
    end

    # #2354: o topo do detalhe usa o mesmo in_review da lista de pausados para não oferecer um Ativar que o servidor recusa.
    it 'anúncio pausado em análise da Meta vem com in_review; ligado em análise, não' do
      stub_permissions('ads_read', 'ads_management')
      stub_post

      stub_ad(status: 'PAUSED', effective: 'PENDING_REVIEW')
      expect(described_class.new(connection).payload(ad_id)).to include(in_review: true)
      stub_ad(status: 'PAUSED', effective: 'IN_PROCESS')
      expect(described_class.new(connection).payload(ad_id)).to include(in_review: true)
      stub_ad(status: 'ACTIVE', effective: 'IN_PROCESS')
      expect(described_class.new(connection).payload(ad_id)).to include(in_review: false)
      stub_ad(status: 'PAUSED', effective: 'PAUSED')
      expect(described_class.new(connection).payload(ad_id)).to include(in_review: false)
    end

    it 'sem ads_management no token: não muda e pede para entrar de novo' do
      stub_permissions('ads_read')
      stub_ad(story: nil)

      expect(described_class.new(connection).payload(ad_id)).to include(can_change: false, needs_login: true, post: nil)
    end

    it 'modo parceiro nunca muda, mesmo com ads_management no token da plataforma' do
      connection.update!(mode: 'partner', access_token: nil)
      allow(Crm::MetaAds::Platform).to receive(:token).and_return(MetaAdsHelpers::TEST_TOKEN)
      stub_permissions('ads_management')
      stub_ad(story: nil)

      expect(described_class.new(connection).payload(ad_id)).to include(can_change: false, needs_login: false, mode: 'partner')
    end

    it 'anúncio de outra conta de anúncios não aparece' do
      stub_ad(account_id: '999')

      expect(described_class.new(connection).payload(ad_id)).to be_nil
    end

    it 'post que o token do cliente não lê é lido com o token da Página' do
      stub_permissions('ads_management')
      stub_ad
      stub_post(status: 403)
      stub_request(:get, meta_graph_url('100000000000001')).with(query: { fields: 'access_token' })
                                                           .to_return(status: 200, body: { access_token: 'PAGETOKEN123' }.to_json, headers: json)
      stub_post(token: 'PAGETOKEN123')

      expect(described_class.new(connection).payload(ad_id)[:post]).to include(page_name: 'Loja Exemplo', reactions: 128)
    end

    it 'id que não é só dígitos não chega à Meta (sem parâmetro nem caminho extra)' do
      management = described_class.new(connection)

      ['123?method=post&status=PAUSED', '123/insights', 'me', '', nil].each do |bad|
        expect(management.payload(bad)).to be_nil
        expect { management.change!(bad, 'PAUSED') }.to raise_error(described_class::Error, 'ad_not_found')
      end
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'a Meta devolvendo outro id (campanha, conjunto) não vale como o anúncio pedido' do
      stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                               .to_return(status: 200, headers: json,
                                                          body: { id: '777', account_id: connection.ad_account_id }.to_json)

      expect(described_class.new(connection).payload(ad_id)).to be_nil
    end

    it 'post que volta como "não pode ser lido" (100) também tenta com o token da Página' do
      stub_permissions('ads_management')
      stub_ad
      stub_request(:get, meta_graph_url(post_id)).with(query: { fields: Meta::AdsGraphClient::PAGE_POST_FIELDS },
                                                       headers: { 'Authorization' => "Bearer #{MetaAdsHelpers::TEST_TOKEN}" })
                                                 .to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      stub_request(:get, meta_graph_url('100000000000001')).with(query: { fields: 'access_token' })
                                                           .to_return(status: 200, body: { access_token: 'PAGETOKEN123' }.to_json, headers: json)
      stub_post(token: 'PAGETOKEN123')
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(connection).payload(ad_id)[:post]).to include(comments: 14)
    end

    it 'falha passageira da Meta vira meta_unavailable, não anúncio sumido' do
      stub_ad(http: 500)

      expect { described_class.new(connection).payload(ad_id) }
        .to raise_error(described_class::Error) { |error| expect(error.code).to eq('meta_unavailable') }
    end
  end

  describe '#change!' do
    let(:update) do
      stub_request(:post, meta_graph_url(ad_id)).with(body: { status: 'PAUSED' })
                                                .to_return(status: 200, body: { success: true }.to_json, headers: json)
    end

    it 'pausa o anúncio da conta da conexão' do
      stub_permissions('ads_management')
      stub_ad
      update

      expect(described_class.new(connection).change!(ad_id, 'PAUSED')).to eq('PAUSED')
      expect(update).to have_been_requested.once
    end

    # #2354: anúncio de fora do Chat2You segue a mesma regra do criado aqui.
    it 'recusa ligar anúncio pausado em análise da Meta, sem chamar a Meta para mudar; pausar segue' do
      stub_permissions('ads_management')
      stub_ad(status: 'PAUSED', effective: 'IN_PROCESS')

      expect { described_class.new(connection).change!(ad_id, 'ACTIVE') }.to raise_error(described_class::Error, 'in_review')
      expect(a_request(:post, meta_graph_url(ad_id))).not_to have_been_made

      stub_ad(status: 'ACTIVE', effective: 'IN_PROCESS')
      update
      expect(described_class.new(connection).change!(ad_id, 'PAUSED')).to eq('PAUSED')
    end

    it 'recusa situação fora de ACTIVE/PAUSED, token sem permissão e anúncio de outra conta, sem chamar a Meta para mudar' do
      management = described_class.new(connection)
      expect { management.change!(ad_id, 'DELETED') }.to raise_error(described_class::Error, 'invalid_status')

      stub_permissions('ads_read')
      expect { described_class.new(connection).change!(ad_id, 'PAUSED') }.to raise_error(described_class::Error, 'cannot_change')

      stub_permissions('ads_management')
      stub_ad(account_id: '999')
      expect { described_class.new(connection).change!(ad_id, 'PAUSED') }.to raise_error(described_class::Error, 'ad_not_found')
      expect(update).not_to have_been_requested
    end

    it 'recusa da Meta ao mudar vira meta_refused' do
      stub_permissions('ads_management')
      stub_ad
      stub_request(:post, meta_graph_url(ad_id)).to_return(status: 400, body: meta_graph_error(270).to_json, headers: json)
      allow(Rails.logger).to receive(:warn)

      expect { described_class.new(connection).change!(ad_id, 'PAUSED') }.to raise_error(described_class::Error, 'meta_refused')
    end
  end

  describe '#pages' do
    it 'lista as Páginas concedidas; sem permissão, nenhuma' do
      stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including('fields' => 'id,name'))
                                                       .to_return(status: 200, body: { data: [{ id: '1', name: 'Loja Exemplo' }] }.to_json,
                                                                  headers: json)
      expect(described_class.new(connection).pages).to eq([{ id: '1', name: 'Loja Exemplo' }])

      WebMock.reset!
      stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                       .to_return(status: 403, body: meta_graph_error(10).to_json, headers: json)
      allow(Rails.logger).to receive(:warn)
      expect(described_class.new(connection).pages).to eq([])
    end

    it 'modo parceiro não lista Páginas (o token é o da plataforma)' do
      connection.update!(mode: 'partner', access_token: nil)

      expect(described_class.new(connection).pages).to eq([])
      expect(a_request(:get, meta_graph_url('me/accounts'))).not_to have_been_made
    end
  end
end
