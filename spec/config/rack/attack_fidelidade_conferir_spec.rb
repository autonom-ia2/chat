require 'rails_helper'

# O limite do Conferir cupom (#3100): por login, nunca pelo uid, que é o e-mail e chega antes da autenticação.
RSpec.describe Rack::Attack do
  let(:caminho) { '/api/v1/accounts/7/fidelidade/cupons/conferir' }

  def chave(nome, metodo: 'POST', cabecalhos: {})
    env = Rack::MockRequest.env_for(caminho, { method: metodo }.merge(cabecalhos))
    Rack::Attack.throttles.fetch(nome).block.call(Rack::Attack::Request.new(env))
  end

  it 'conta pelo token do painel, guardado em hash, e não pelo uid' do
    de_ana = chave('fidelidade_conferir/minuto', cabecalhos: { 'HTTP_ACCESS_TOKEN' => 'tok-ana', 'HTTP_UID' => 'ana@x.com' })
    uid_da_ana_com_outro_token = chave('fidelidade_conferir/minuto',
                                       cabecalhos: { 'HTTP_ACCESS_TOKEN' => 'tok-bruno', 'HTTP_UID' => 'ana@x.com' })

    expect(de_ana).to eq(Digest::SHA256.hexdigest('tok-ana'))
    expect(uid_da_ana_com_outro_token).not_to eq(de_ana)
  end

  it 'conta pelo token da API quando não há o do painel' do
    expect(chave('fidelidade_conferir/hora', cabecalhos: { 'HTTP_API_ACCESS_TOKEN' => 'api-tok' }))
      .to eq(Digest::SHA256.hexdigest('api-tok'))
  end

  it 'sem token (só o uid) ou fora do POST, não conta', :aggregate_failures do
    expect(chave('fidelidade_conferir/minuto', cabecalhos: { 'HTTP_UID' => 'ana@x.com' })).to be_nil
    expect(chave('fidelidade_conferir/minuto', metodo: 'GET', cabecalhos: { 'HTTP_ACCESS_TOKEN' => 'tok-ana' })).to be_nil
  end
end
