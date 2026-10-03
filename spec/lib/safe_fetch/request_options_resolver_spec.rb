require 'rails_helper'

# O ssrf_filter conecta num IP SORTEADO entre os do site (`public_addresses.sample`). Num servidor sem
# rota IPv6, um site com IPv4 e IPv6 falhava em metade das leituras ("No route to host" no IPv6) —
# visto em 03/10/2026 lendo https://example.com pelo Guia (#857). O resolvedor padrão prefere IPv4
# quando o site tem; a checagem de endereço privado do ssrf_filter continua valendo sobre o que ele
# devolver.
RSpec.describe SafeFetch::RequestOptions do
  let(:resolver) { described_class.new(url: 'https://exemplo.com.br').resolver }

  it 'fica só com IPv4 quando o site tem os dois' do
    allow(Resolv).to receive(:getaddresses).with('exemplo.com.br').and_return(['2606:4700:10::6814:179a', '93.184.216.34'])

    expect(resolver.call('exemplo.com.br').map(&:to_s)).to eq(['93.184.216.34'])
  end

  it 'usa IPv6 quando o site só tem IPv6' do
    allow(Resolv).to receive(:getaddresses).with('exemplo.com.br').and_return(['2606:4700:10::6814:179a'])

    expect(resolver.call('exemplo.com.br').map(&:to_s)).to eq(['2606:4700:10::6814:179a'])
  end
end
