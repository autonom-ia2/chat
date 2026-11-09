require 'rails_helper'

# #2307: o privado da Página sai quando a Meta concedeu a pages_messaging ao login da caixa (quem tem papel no app já
# tem; o cliente, quando a Meta aprovar), lido em /me/permissions com o token do login. Nunca rede real.
RSpec.describe Crm::MetaAds::ComentariosIa::Rede::PermissaoDoMessenger do
  include MetaAdsHelpers

  let(:account) { create(:account) }
  let(:channel) { create(:channel_facebook_page, account: account, user_access_token: 'token-do-login') }
  let(:permissao) { described_class.new(channel) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def stub_permissoes(status: 200, linhas: nil, body: nil)
    corpo = body || { data: linhas.map { |permission, estado| { permission: permission, status: estado } } }.to_json
    stub_request(:get, meta_graph_url('me/permissions'))
      .with(headers: { 'Authorization' => 'Bearer token-do-login' })
      .to_return(status: status, headers: json, body: corpo)
  end

  it 'libera com a pages_messaging concedida, lendo com o token do login só no cabeçalho' do
    pedido = stub_permissoes(linhas: [%w[pages_manage_metadata granted], %w[pages_messaging granted]])

    expect(permissao.liberada?).to be(true)
    expect(pedido).to have_been_made.once
  end

  it 'não libera com a pages_messaging recusada, vencida ou fora da lista' do
    stub_permissoes(linhas: [%w[pages_messaging declined]])
    expect(described_class.new(channel).liberada?).to be(false)

    cache.clear
    stub_permissoes(linhas: [%w[pages_messaging expired]])
    expect(described_class.new(channel).liberada?).to be(false)

    cache.clear
    stub_permissoes(linhas: [%w[pages_manage_metadata granted]])
    expect(described_class.new(channel).liberada?).to be(false)
  end

  it 'guarda a leitura: a segunda pergunta não chama a Meta; entrar de novo (a caixa muda) lê de novo' do
    pedido = stub_permissoes(linhas: [%w[pages_messaging granted]])

    2.times { described_class.new(channel).liberada? }
    expect(pedido).to have_been_made.once

    channel.update!(updated_at: 1.minute.from_now)
    described_class.new(channel).liberada?
    expect(pedido).to have_been_made.twice
  end

  it 'sem resposta da lista (login vencido, Meta fora do ar): libera, e quem decide é a chamada do privado' do
    stub_permissoes(status: 400, body: { error: { code: 190, message: 'expirado' } }.to_json)
    expect(described_class.new(channel).liberada?).to be(true)

    cache.clear
    stub_request(:get, meta_graph_url('me/permissions')).to_return(status: 503, body: 'fora')
    expect(described_class.new(channel).liberada?).to be(true)
  end

  it 'a Meta lenta: a leitura tem prazo curto, e sem resposta libera (a chamada do privado decide)' do
    stub_request(:get, meta_graph_url('me/permissions')).to_timeout

    expect(permissao.liberada?).to be(true)
  end

  it 'caixa que não é de Página, ou sem o token do login: nada de Meta' do
    instagram = create(:channel_instagram, account: account)
    expect(described_class.new(instagram).liberada?).to be(false)

    channel.user_access_token = ''
    expect(described_class.new(channel).liberada?).to be(true)
    expect(a_request(:get, meta_graph_url('me/permissions'))).not_to have_been_made
  end
end
