require 'uri'

# Endereço de proxy como o motor guarda (`host:porta`, às vezes com `http://`), normalizado para comparar (#1516).
module WhatsappProxy::Server
  module_function

  # "http://10.0.0.1:6000" e "10.0.0.1:6000" → "10.0.0.1:6000"; inválido ou vazio → nil.
  def normalize(server)
    uri = parse(server)
    uri && "#{uri.host}:#{uri.port}"
  end

  def host(server)
    parse(server)&.host
  end

  def same?(left, right)
    normalized = normalize(left)
    normalized.present? && normalized == normalize(right)
  end

  def parse(server)
    text = server.to_s.strip
    return if text.empty?

    uri = URI.parse(text.include?('://') ? text : "http://#{text}")
    uri if uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
end
