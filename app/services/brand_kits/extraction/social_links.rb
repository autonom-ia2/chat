# Perfis da marca nas redes (#1076): links da página e `sameAs` do JSON-LD. Fica o primeiro perfil de
# cada rede, sem query/fragmento (rastreamento, texto pronto do WhatsApp). Links de compartilhar/curtir
# e a página inicial da rede não são perfil.
class BrandKits::Extraction::SocialLinks
  MAX_ANCHORS = 500
  SHARE_PATHS = %w[/sharer /share /intent /dialog /plugins /sharearticle /home].freeze
  WHATSAPP_SEND_PATHS = %w[/send /send/].freeze

  def initialize(document, same_as:)
    @document = document
    @same_as = same_as
  end

  def perform
    found = {}
    (@same_as + anchors).each do |href|
      network, url = profile(href)
      found[network] ||= url if url
    end
    BrandKits::WebAddress::NETWORKS.filter_map { |network| { 'network' => network, 'url' => found[network] } if found[network] }
  end

  private

  def profile(href)
    uri = BrandKits::WebAddress.parse(href)
    network = uri && BrandKits::WebAddress.network_for(uri)
    network ? [network, profile_url(network, uri)] : nil
  end

  def anchors
    @document.css('a[href]').first(MAX_ANCHORS).map { |node| node['href'].to_s.strip }
  end

  def profile_url(network, uri)
    path = uri.path.to_s
    return whatsapp_url(uri, path) if network == 'whatsapp'

    lowered = path.downcase
    return nil if lowered.delete_suffix('/').empty? || SHARE_PATHS.any? { |share| lowered.start_with?(share) }

    "https://#{uri.host.downcase}#{path}"
  end

  def whatsapp_url(uri, path)
    number = if uri.host.casecmp?('wa.me') then path.delete_prefix('/').delete_suffix('/')
             elsif WHATSAPP_SEND_PATHS.include?(path) then phone_param(uri)
             end
    digits = number.to_s.each_char.select { |char| char.between?('0', '9') }.join
    digits.length >= 8 ? "https://wa.me/#{digits}" : nil
  end

  def phone_param(uri)
    URI.decode_www_form(uri.query.to_s).to_h['phone']
  rescue ArgumentError
    nil
  end
end
