require 'rails_helper'

# Tetos por IP do link por cliente (#1190): abrir o convite (GET, por minuto) e registrar a abertura (POST, por hora).
RSpec.describe Rack::Attack do
  def chave(nome, caminho, metodo: 'GET')
    env = Rack::MockRequest.env_for('/', method: metodo).merge('PATH_INFO' => caminho, 'REMOTE_ADDR' => '203.0.113.9')
    Rack::Attack.throttles.fetch(nome).block.call(Rack::Attack::Request.new(env))
  end

  it 'conta GET e HEAD do convite por IP, em qualquer grafia do caminho, e só o convite' do
    nome = 'public_booking_invites/show_ip'
    ['/public/api/v2/invites/AB23cd45', '/public/api/v2/invites/AB23cd45/', '/public/api/v2/invites/AB23cd45.json',
     '/public//api/v2/invites/AB23cd45'].each do |grafia|
      expect(chave(nome, grafia)).to eq('203.0.113.9'), grafia
    end
    expect(chave(nome, '/public/api/v2/invites/AB23cd45', metodo: 'HEAD')).to eq('203.0.113.9')
    expect(chave(nome, '/public/api/v2/invites/AB23cd45', metodo: 'POST')).to be_nil
    expect(chave(nome, '/public/api/v2/invites/AB23cd45/viewed')).to be_nil
    expect(chave(nome, '/public/api/v1/booking/abc')).to be_nil
  end

  it 'conta o POST de abertura por IP e nada mais' do
    nome = 'public_booking_invites/viewed_ip'

    expect(chave(nome, '/public/api/v2/invites/AB23cd45/viewed', metodo: 'POST')).to eq('203.0.113.9')
    expect(chave(nome, '/public//api/v2/invites/AB23cd45/viewed/', metodo: 'POST')).to eq('203.0.113.9')
    expect(chave(nome, '/public/api/v2/invites/AB23cd45/viewed')).to be_nil
    expect(chave(nome, '/public/api/v2/invites/AB23cd45', metodo: 'POST')).to be_nil
    expect(chave(nome, '/public/api/v2/invites/AB23cd45/other', metodo: 'POST')).to be_nil
  end

  # #1192: gestão da reunião pelo mesmo link (confirmar, cancelar, remarcar, parar avisos), por hora.
  it 'conta os POST de gestão da reunião por IP e nada mais' do
    nome = 'public_booking_invites/manage_ip'

    %w[confirm cancel reschedule stop_notices].each do |acao|
      expect(chave(nome, "/public/api/v2/invites/AB23cd45/#{acao}", metodo: 'POST')).to eq('203.0.113.9'), acao
    end
    expect(chave(nome, '/public//api/v2/invites/AB23cd45/cancel/', metodo: 'POST')).to eq('203.0.113.9')
    expect(chave(nome, '/public/api/v2/invites/AB23cd45/cancel')).to be_nil
    expect(chave(nome, '/public/api/v2/invites/AB23cd45/viewed', metodo: 'POST')).to be_nil
    expect(chave(nome, '/public/api/v2/invites/AB23cd45', metodo: 'POST')).to be_nil
  end
end
