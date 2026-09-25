require 'ipaddr'
require 'resolv'

module Autonomia
  module Agents
    module Knowledge
      # Guarda anti-SSRF para ingestão de `link` (entrada de usuário). Replica a lógica de bloqueio
      # de host/IP do Crm::Ai::ResponsesClient: só aceita http(s), rejeita hosts locais, faixas de IP
      # privadas/loopback/link-local e qualquer host que RESOLVA para esses ranges. Obrigatório antes
      # de qualquer GET na fonte de link.
      class UrlGuard
        class BlockedUrl < StandardError; end

        BLOCKED_HOSTS = %w[localhost localhost.localdomain].freeze
        BLOCKED_IP_RANGES = [
          IPAddr.new('0.0.0.0/8'),
          IPAddr.new('10.0.0.0/8'),
          IPAddr.new('100.64.0.0/10'),
          IPAddr.new('127.0.0.0/8'),
          IPAddr.new('169.254.0.0/16'),
          IPAddr.new('172.16.0.0/12'),
          IPAddr.new('192.168.0.0/16'),
          IPAddr.new('192.0.0.0/24'),
          IPAddr.new('198.18.0.0/15'),
          IPAddr.new('224.0.0.0/4'),
          IPAddr.new('240.0.0.0/4'),
          IPAddr.new('::/128'),
          IPAddr.new('::1/128'),
          IPAddr.new('64:ff9b:1::/48'),
          IPAddr.new('fc00::/7'),
          IPAddr.new('fe80::/10'),
          IPAddr.new('fec0::/10'),
          IPAddr.new('ff00::/8')
        ].freeze
        # IPv6 que carrega um IPv4 dentro e chega nele quando a rede traduz (#678): prefixo => deslocamento em bits do
        # IPv4 embutido. IPv4 compatível (::a.b.c.d), NAT64 (64:ff9b::/96) e 6to4 (2002:AABB:CCDD::).
        EMBEDDED_IPV4_PREFIXES = {
          IPAddr.new('::/96') => 0,
          IPAddr.new('64:ff9b::/96') => 0,
          IPAddr.new('2002::/16') => 80
        }.freeze
        IPV4_MASK = 0xffff_ffff

        # Classifica um endereço JÁ resolvido. Quem conecta num IP fixado (Prospecting::WebsiteScraper, #476) checa o
        # endereço em que vai conectar com esta mesma regra, em vez de confiar numa segunda resolução do DNS.
        def self.blocked_ip?(address)
          ip = IPAddr.new(address.to_s)
          ip = ip.native if ip.ipv4_mapped?
          [ip, embedded_ipv4(ip)].compact.any? { |candidate| BLOCKED_IP_RANGES.any? { |range| range.include?(candidate) } }
        rescue IPAddr::InvalidAddressError
          true
        end

        def self.embedded_ipv4(ip)
          return unless ip.ipv6?

          shift = EMBEDDED_IPV4_PREFIXES.find { |prefix, _shift| prefix.include?(ip) }&.last
          IPAddr.new((ip.to_i >> shift) & IPV4_MASK, Socket::AF_INET) if shift
        end
        private_class_method :embedded_ipv4

        def initialize(url)
          @url = url.to_s.strip
        end

        # Levanta BlockedUrl se a url for inválida ou apontar p/ destino bloqueado. Retorna a url limpa.
        def validate!
          uri = URI.parse(@url)
          raise BlockedUrl, 'invalid_url' unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          raise BlockedUrl, 'invalid_url' if uri.host.blank? || uri.userinfo.present?
          raise BlockedUrl, 'blocked_host' if blocked_host?(uri.host)
          raise BlockedUrl, 'blocked_host' if blocked_resolved_host?(uri.host)

          @url
        rescue URI::InvalidURIError
          raise BlockedUrl, 'invalid_url'
        end

        private

        def blocked_host?(host)
          normalized = normalize_host(host)
          return true if BLOCKED_HOSTS.include?(normalized) || normalized.end_with?('.localhost')

          blocked_ip?(normalized)
        end

        def blocked_resolved_host?(host)
          normalized = normalize_host(host)
          return false if ip_address?(normalized)

          addresses = Resolv.getaddresses(normalized)
          return true if addresses.empty?

          addresses.any? { |address| blocked_ip?(address, reject_invalid: true) }
        rescue Resolv::ResolvError, ArgumentError
          true
        end

        def normalize_host(host)
          host.to_s.downcase.delete_suffix('.')
        end

        def ip_address?(address)
          IPAddr.new(address)
          true
        rescue IPAddr::InvalidAddressError
          false
        end

        def blocked_ip?(address, reject_invalid: false)
          return reject_invalid unless ip_address?(address)

          self.class.blocked_ip?(address)
        end
      end
    end
  end
end
