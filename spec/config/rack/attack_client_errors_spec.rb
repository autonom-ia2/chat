require 'rails_helper'

# #1841: the browser error log has its own per-IP ceiling, whatever spelling of the path the router accepts.
RSpec.describe Rack::Attack do
  let(:caminho) { '/api/v1/accounts/7/client_errors' }

  def chave(caminho, metodo: 'POST')
    env = Rack::MockRequest.env_for('/', { method: metodo }.merge('REMOTE_ADDR' => '203.0.113.9')).merge('PATH_INFO' => caminho)
    Rack::Attack.throttles.fetch('client_errors/ip').block.call(Rack::Attack::Request.new(env))
  end

  it 'counts every spelling the router accepts: extension, trailing slash, doubled slash' do
    [caminho, "#{caminho}.json", "#{caminho}/", '/api/v1/accounts/7//client_errors'].each do |grafia|
      expect(chave(grafia)).to eq('203.0.113.9')
    end
  end

  it 'leaves other paths and other verbs alone' do
    expect(chave(caminho, metodo: 'GET')).to be_nil
    expect(chave('/api/v1/accounts/7/client_errors_x')).to be_nil
  end
end
