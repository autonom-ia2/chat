require 'rails_helper'

# Os tetos da busca inteligente da Central (#977): cada pedido que passa é uma chamada paga ao Jev.
RSpec.describe Rack::Attack do
  let(:caminho) { '/api/v1/accounts/7/central-de-ajuda/busca_inteligente' }

  # O caminho entra cru no PATH_INFO, como chega do servidor: `//api` numa URL seria lido como host.
  def chave(nome, caminho, metodo: 'GET', cabecalhos: {})
    env = Rack::MockRequest.env_for('/', { method: metodo }.merge(cabecalhos)).merge('PATH_INFO' => caminho)
    Rack::Attack.throttles.fetch(nome).block.call(Rack::Attack::Request.new(env))
  end

  def por_pessoa(caminho, **) = chave('/api/v1/accounts/:account_id/central-de-ajuda/busca_inteligente/user', caminho, **)
  def por_conta(caminho, **) = chave('/api/v1/accounts/:account_id/central-de-ajuda/busca_inteligente/account', caminho, **)

  it 'conta GET e HEAD (o Rails atende HEAD com a rota GET)' do
    expect(por_pessoa(caminho, cabecalhos: { 'HTTP_UID' => 'a@b.com' })).to eq('a@b.com:7')
    expect(por_pessoa(caminho, metodo: 'HEAD', cabecalhos: { 'HTTP_UID' => 'a@b.com' })).to eq('a@b.com:7')
    expect(por_pessoa(caminho, metodo: 'POST', cabecalhos: { 'HTTP_UID' => 'a@b.com' })).to be_nil
  end

  it 'normaliza o caminho como o roteador: barra duplicada, barra no fim e extensão não escapam' do
    ['/api//v1/accounts/7/central-de-ajuda/busca_inteligente', "#{caminho}/", "#{caminho}.json",
     '//api/v1/accounts/7//central-de-ajuda//busca_inteligente'].each do |grafia|
      expect(por_conta(grafia)).to eq('7')
    end
    expect(por_conta('/api/v1/accounts/7/central-de-ajuda/busca')).to be_nil
  end

  it 'com token de API, identifica pelo token: uid inventado não abre chave nova' do
    com_token = ->(uid) { por_pessoa(caminho, cabecalhos: { 'HTTP_API_ACCESS_TOKEN' => 'tok', 'HTTP_UID' => uid }) }

    expect([com_token.call('x1'), com_token.call('x2')]).to all(eq('tok:7'))
  end

  it 'tem teto por conta, qualquer que seja a pessoa' do
    expect(por_conta(caminho, cabecalhos: { 'HTTP_UID' => 'a' })).to eq('7')
    expect(por_conta(caminho, cabecalhos: { 'HTTP_API_ACCESS_TOKEN' => 'tok' })).to eq('7')
  end
end
