require 'rails_helper'

# Tetos da página pública v2 (#1189). Por IP: reserva e pedido de contato por hora, horários por minuto, página e ICS
# por minuto. Por página (slug): reservas por hora e pedidos de contato por dia. Caminho normalizado e comparado em
# pedaços, sem regex.
RSpec.describe Rack::Attack do
  def chave(nome, caminho, metodo: 'GET')
    env = Rack::MockRequest.env_for('/', method: metodo).merge('PATH_INFO' => caminho, 'REMOTE_ADDR' => '203.0.113.9')
    Rack::Attack.throttles.fetch(nome).block.call(Rack::Attack::Request.new(env))
  end

  let(:slug) { '0f8e1c2a-1111-4c3d-9e2f-abcdefabcdef' }
  let(:ip) { '203.0.113.9' }

  it 'limita o POST de reserva por hora e nada mais' do
    nome = 'public_booking_v2/create_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 10, period: 3600)
    ["/public/api/v2/booking/#{slug}", "/public//api/v2/booking/#{slug}/", "/public/api/v2/booking/#{slug}.json"].each do |grafia|
      expect(chave(nome, grafia, metodo: 'POST')).to eq(ip), grafia
    end
    expect(chave(nome, "/public/api/v2/booking/#{slug}")).to be_nil
    expect(chave(nome, "/public/api/v2/booking/#{slug}/contact_request", metodo: 'POST')).to be_nil
    expect(chave(nome, "/public/api/v1/booking/#{slug}", metodo: 'POST')).to be_nil
  end

  it 'limita o pedido de contato por hora' do
    nome = 'public_booking_v2/contact_request_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 10, period: 3600)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/contact_request", metodo: 'POST')).to eq(ip)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/contact_request")).to be_nil
    expect(chave(nome, "/public/api/v2/booking/#{slug}", metodo: 'POST')).to be_nil
  end

  it 'limita reservas por página por hora, pela página e não pelo IP' do
    nome = 'public_booking_v2/create_page'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 40, period: 3600)
    ["/public/api/v2/booking/#{slug}", "/public//api/v2/booking/#{slug}/", "/public/api/v2/booking/#{slug}.json"].each do |grafia|
      expect(chave(nome, grafia, metodo: 'POST')).to eq(slug), grafia
    end
    expect(chave(nome, "/public/api/v2/booking/#{slug}")).to be_nil
    expect(chave(nome, "/public/api/v2/booking/#{slug}/contact_request", metodo: 'POST')).to be_nil
    expect(chave(nome, "/public/api/v1/booking/#{slug}", metodo: 'POST')).to be_nil
  end

  it 'limita pedidos de contato por página por dia' do
    nome = 'public_booking_v2/contact_request_page'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 20, period: 86_400)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/contact_request", metodo: 'POST')).to eq(slug)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/contact_request")).to be_nil
    expect(chave(nome, "/public/api/v2/booking/#{slug}", metodo: 'POST')).to be_nil
  end

  it 'limita horários e próximo horário por minuto' do
    nome = 'public_booking_v2/slots_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 60, period: 60)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/slots")).to eq(ip)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/next_slot")).to eq(ip)
    expect(chave(nome, "/public/api/v2/booking/#{slug}/other")).to be_nil
    expect(chave(nome, "/public/api/v2/booking/#{slug}/slots", metodo: 'POST')).to be_nil
    expect(chave(nome, "/public/api/v1/booking/#{slug}/slots")).to be_nil
  end

  it 'limita o GET da página e do arquivo de calendário por minuto' do
    nome = 'public_booking_v2/show_ip'
    expect(described_class.throttles.fetch(nome)).to have_attributes(limit: 60, period: 60)
    expect(chave(nome, "/public/api/v2/booking/#{slug}")).to eq(ip)
    expect(chave(nome, '/public/api/v2/ics/abc-DEF_123')).to eq(ip)
    expect(chave(nome, "/public/api/v2/booking/#{slug}", metodo: 'POST')).to be_nil
    expect(chave(nome, "/public/api/v2/booking/#{slug}/slots")).to be_nil
    expect(chave(nome, '/public/api/v2/invites/AB23cd45')).to be_nil
  end
end
