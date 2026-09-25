require 'rails_helper'

# Guarda anti-SSRF da ingestão de link e do scraper da Prospecção (#476, #678). Endereços IPv6 que carregam um IPv4
# dentro (compatível, NAT64, 6to4) chegam ao IPv4 embutido quando a rede traduz; a guarda confere esse IPv4.
RSpec.describe Autonomia::Agents::Knowledge::UrlGuard do
  describe '.blocked_ip?' do
    it 'bloqueia IPv4 interno escondido em IPv6 compatível, NAT64 e 6to4' do
      [
        '::127.0.0.1', '::a9fe:a9fe',
        '64:ff9b::a9fe:a9fe', '64:ff9b::a00:5', '64:ff9b:1::a9fe:a9fe',
        '2002:a9fe:a9fe::1', '2002:7f00:1::'
      ].each { |address| expect(described_class.blocked_ip?(address)).to be(true), address }
    end

    it 'bloqueia faixas especiais de IPv4 e IPv6 que não são internet pública' do
      %w[
        198.18.0.1 198.19.255.254 192.0.0.8 224.0.0.1 239.255.255.250 240.0.0.1 255.255.255.255
        fec0::1 ff02::1
      ].each { |address| expect(described_class.blocked_ip?(address)).to be(true), address }
    end

    it 'continua liberando endereço público, inclusive público dentro de NAT64 e 6to4' do
      %w[
        93.184.216.34 8.8.8.8 2606:4700:4700::1111
        64:ff9b::808:808 2002:808:808::1
      ].each { |address| expect(described_class.blocked_ip?(address)).to be(false), address }
    end
  end

  describe '#validate!' do
    it 'recusa URL com IPv6 literal que embute IPv4 interno' do
      ['http://[64:ff9b::a9fe:a9fe]/', 'http://[::127.0.0.1]/', 'http://[2002:a9fe:a9fe::1]/'].each do |url|
        expect { described_class.new(url).validate! }.to raise_error(described_class::BlockedUrl, 'blocked_host')
      end
    end
  end
end
