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
          IPAddr.new('::/128'),
          IPAddr.new('::1/128'),
          IPAddr.new('fc00::/7'),
          IPAddr.new('fe80::/10')
        ].freeze

        # Classifica um endereço JÁ resolvido. Quem conecta num IP fixado (Prospecting::WebsiteScraper, #476) checa o
        # endereço em que vai conectar com esta mesma regra, em vez de confiar numa segunda resolução do DNS.
        def self.blocked_ip?(address)
          ip = IPAddr.new(address.to_s)
          ip = ip.native if ip.ipv4_mapped?
          BLOCKED_IP_RANGES.any? { |range| range.include?(ip) }
        rescue IPAddr::InvalidAddressError
          true
        end

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
