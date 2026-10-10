# Endereços web da identidade visual (#1076): o que é um link http(s) aceitável e a que rede social ele
# pertence. Lido com URI e métodos de String, sem expressão regular.
module BrandKits::WebAddress
  MAX_LENGTH = 2048
  SCHEMES = %w[http https].freeze
  NETWORK_HOSTS = {
    'facebook' => %w[facebook.com fb.com],
    'instagram' => %w[instagram.com],
    'linkedin' => %w[linkedin.com],
    'youtube' => %w[youtube.com youtu.be],
    'tiktok' => %w[tiktok.com],
    'x' => %w[x.com twitter.com],
    'whatsapp' => %w[wa.me whatsapp.com]
  }.freeze
  NETWORKS = NETWORK_HOSTS.keys.freeze

  module_function

  # URI http(s) absoluta, sem usuário/senha, ou nil.
  def parse(value)
    text = value.to_s.strip
    return nil if text.empty? || text.length > MAX_LENGTH

    uri = URI.parse(text)
    web_uri?(uri) ? uri : nil
  rescue URI::InvalidURIError
    nil
  end

  def web_uri?(uri)
    SCHEMES.include?(uri.scheme.to_s.downcase) && uri.host.present? && uri.userinfo.nil?
  end

  def http?(value)
    parse(value).present?
  end

  def https_host?(value, host)
    uri = parse(value)
    uri.present? && uri.scheme.casecmp?('https') && uri.host.casecmp?(host)
  end

  def network_for(value)
    uri = value.is_a?(URI::Generic) ? value : parse(value)
    return nil if uri.nil?

    host = uri.host.downcase
    NETWORK_HOSTS.find { |_network, hosts| hosts.any? { |domain| host == domain || host.end_with?(".#{domain}") } }&.first
  end

  # Junta um endereço relativo ao da página; só devolve http(s).
  def join(base, value)
    text = value.to_s.strip
    return nil if text.empty? || text.length > MAX_LENGTH || text.start_with?('data:', 'javascript:', 'mailto:', 'tel:')

    joined = URI.join(base.to_s, text)
    parse(joined.to_s)&.to_s
  rescue URI::Error, ArgumentError
    nil
  end

  def origin(uri)
    default_port = uri.port == uri.default_port
    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless default_port}"
  end

  # Mesmo site: mesmo host, ou subdomínio do domínio da página (sem o "www.").
  def same_site?(uri, page_uri)
    host = uri.host.downcase
    site = page_uri.host.downcase.delete_prefix('www.')
    host == site || host.end_with?(".#{site}")
  end
end
