require 'rails_helper'

# Tetos do link curto e da prévia do link (#1282), por IP: a casca `/a/…`, a imagem de prévia e a conferência de
# nome livre no painel. Caminho normalizado e comparado em pedaços, sem regex.
RSpec.describe Rack::Attack do
  def chave(nome, caminho, metodo: 'GET')
    env = Rack::MockRequest.env_for('/', method: metodo).merge('PATH_INFO' => caminho, 'REMOTE_ADDR' => '203.0.113.9')
    Rack::Attack.throttles.fetch(nome).block.call(Rack::Attack::Request.new(env))
  end

  let(:ip) { '203.0.113.9' }
  let(:slug) { '0f8e1c2a-1111-4c3d-9e2f-abcdefabcdef' }

  it 'limita a casca do link curto, da página e da pessoa, por minuto' do
    nome = 'public_booking_short/show_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 60, period: 60)
    ['/a/clinica-viva', '/a/clinica-viva/ana', '//a/clinica-viva/', '/a/clinica-viva.html'].each do |grafia|
      expect(chave(nome, grafia)).to eq(ip), grafia
    end
    expect(chave(nome, '/a/clinica-viva', metodo: 'HEAD')).to eq(ip)
    expect(chave(nome, '/a/clinica-viva', metodo: 'POST')).to be_nil
    ['/a', '/a/', '/a/x/y/z', '/app/accounts/1/dashboard', '/api/v1/accounts/1', '/auth/sign_in', "/book/#{slug}"].each do |outro|
      expect(chave(nome, outro)).to be_nil, outro
    end
  end

  it 'limita a imagem de prévia por minuto' do
    nome = 'public_booking_preview/image_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 60, period: 60)
    expect(chave(nome, "/book/#{slug}/preview/abc123.png")).to eq(ip)
    expect(chave(nome, "/book//#{slug}/preview/abc123.png")).to eq(ip)
    expect(chave(nome, "/book/#{slug}/preview/abc123.png", metodo: 'HEAD')).to eq(ip)
    expect(chave(nome, "/book/#{slug}/preview/abc123.png", metodo: 'POST')).to be_nil
    ["/book/#{slug}", "/book/#{slug}/confirm", "/book/#{slug}/preview", "/book/#{slug}/outra/abc.png", '/a/clinica-viva'].each do |outro|
      expect(chave(nome, outro)).to be_nil, outro
    end
  end

  it 'limita a conferência de nome livre no painel por minuto' do
    nome = 'booking_short_name/check_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 30, period: 60)
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name')).to eq(ip)
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name.json')).to eq(ip)
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name', metodo: 'HEAD')).to eq(ip)
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name', metodo: 'POST')).to be_nil
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages')).to be_nil
    expect(chave(nome, '/outra/crm/booking_pages/short_name')).to be_nil
  end

  it 'limita a conferência de nome livre também por conta, não importa o IP' do
    nome = 'booking_short_name/check_account'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 120, period: 60)
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name')).to eq('7')
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name.json')).to eq('7')
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages/short_name', metodo: 'POST')).to be_nil
    expect(chave(nome, '/api/v1/accounts/7/crm/booking_pages')).to be_nil
    expect(chave(nome, '/api/v1/accounts/7/qualquer/coisa/crm/booking_pages/short_name')).to be_nil
  end
end
