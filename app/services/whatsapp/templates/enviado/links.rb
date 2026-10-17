# Os links que a foto do envio (#1717) grava: só http(s), com endereço e curtos. Qualquer outro esquema (`javascript:`,
# `data:`…) vira nil, e a tela não desenha link. Lido pelo parser de URI, nunca por padrão de texto.
module Whatsapp::Templates::Enviado::Links
  ESQUEMAS = %w[http https].freeze
  MAX = 512
  # Endereços de mídia da Meta e do WhatsApp: o link expira em minutos ou horas, então nunca é gravado.
  TEMPORARIOS = %w[fbcdn.net fbsbx.com whatsapp.net].freeze
  # Parâmetros de link assinado que expira (S3, Google Cloud Storage, CloudFront e o `oe` da Meta), comparados sem caixa.
  ASSINATURA = %w[x-amz-expires x-amz-signature x-goog-expires x-goog-signature expires signature oe].freeze

  module_function

  def link(url)
    url = url.to_s.strip
    return if url.empty? || url.length > MAX

    uri = URI.parse(url)
    url if ESQUEMAS.include?(uri.scheme&.downcase) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # Foto de produto: só https e fora dos endereços temporários da Meta.
  def foto(url)
    url = link(url)
    return unless url

    uri = URI.parse(url)
    url if uri.scheme.casecmp?('https') && !temporario?(uri.host.downcase) && !assinado?(uri.query)
  end

  def assinado?(query)
    return false if query.blank?

    URI.decode_www_form(query).any? { |chave, _valor| ASSINATURA.include?(chave.downcase) }
  rescue ArgumentError
    true
  end

  def temporario?(host)
    TEMPORARIOS.any? { |dominio| host == dominio || host.end_with?(".#{dominio}") }
  end
end
