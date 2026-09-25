# Normalização do Orth (lib/services/research/company-owner/normalization.ts), sem regex (#679).
# Duas famílias, uma por uso:
# - chave da Receita (key): maiúsculas, sem acento, tudo que não é letra ou dígito vira espaço, espaços colapsados.
#   Compara qualificação, natureza jurídica e situação cadastral contra tabela fechada.
# - texto de identidade (text, business_name): minúsculo, sem acento, mesmo tratamento de separadores; o nome de empresa
#   descarta os sufixos societários da tabela fechada LEGAL_SUFFIXES. Serve ao matcher da descoberta do CNPJ.
# Sem regex, de propósito (regra do Rodrigo, 20/09/2026).
module Autonomia::Prospecting::Research::Normalization
  KEY_CHARS = (('A'..'Z').to_a + ('0'..'9').to_a).to_set.freeze
  DIGITS = ('0'..'9').to_set.freeze
  LEGAL_SUFFIXES = %w[ltda me eireli s a].freeze
  COMBINING_MARKS = (0x0300..0x036f)
  ALPHANUMERIC = [('a'..'z'), ('0'..'9')].freeze
  HTTPS = 'https'.freeze
  SCHEME_SEPARATOR = '://'.freeze

  module_function

  def key(value)
    ActiveSupport::Inflector.transliterate(value.to_s).upcase.each_char.map { |char| KEY_CHARS.include?(char) ? char : ' ' }.join.split.join(' ')
  end

  def digits(value)
    value.to_s.each_char.select { |char| DIGITS.include?(char) }.join
  end

  # Números inteiros na ordem em que aparecem ("Entre 13 a 20 anos" -> [13, 20]).
  def numbers(value)
    value.to_s.each_char.map { |char| DIGITS.include?(char) ? char : ' ' }.join.split.map(&:to_i)
  end

  # Texto aparado, com espaços colapsados, ou nil quando vazio. Mantém caixa e acento (é o que se mostra).
  def squish(value)
    return nil unless value.is_a?(String)

    squished = value.split.join(' ')
    squished.presence
  end

  def text(value)
    value.to_s.unicode_normalize(:nfd).downcase.each_char.filter_map do |char|
      next if COMBINING_MARKS.cover?(char.ord)

      ALPHANUMERIC.any? { |range| range.cover?(char) } ? char : ' '
    end.join.split.join(' ')
  end

  def business_name(value)
    text(value).split.reject { |token| LEGAL_SUFFIXES.include?(token) }.join(' ')
  end

  # Dígitos do E.164. Sem + é número brasileiro; com + é internacional, como no Orth.
  def phone(value)
    input = value.to_s.strip
    return if input.empty?

    Autonomia::Prospecting::PhoneContract.parse(input, region: 'BR')&.digits
  end

  def uf(value)
    candidate = value.to_s.strip.upcase
    candidate.length == 2 && candidate.each_char.all? { |char| char.between?('A', 'Z') } ? candidate : nil
  end

  # Domínio registrável (public suffix). Só https, sem usuário e senha, na porta padrão. Com require_https, o endereço
  # precisa trazer o esquema explícito (é o site do lead, que o Orth só aceita assim).
  def registrable_domain(value, require_https: false)
    uri = https_uri(value.to_s.strip, require_https)
    return unless uri && uri.userinfo.nil? && uri.port == uri.default_port && uri.host.present?

    PublicSuffix.domain(uri.host.downcase)
  rescue URI::InvalidURIError, PublicSuffix::Error
    nil
  end

  def https_uri(raw, require_https)
    has_scheme = raw.include?(SCHEME_SEPARATOR)
    return if raw.empty? || (require_https && !has_scheme)

    uri = URI.parse(has_scheme ? raw : "#{HTTPS}#{SCHEME_SEPARATOR}#{raw}")
    uri.scheme == HTTPS ? uri : nil
  end
end
