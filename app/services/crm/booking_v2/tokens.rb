# Tokens do agendamento v2 (#1187). Cada uso tem o seu `purpose` e a sua chave (`crm_booking_v2_<purpose>`): um token
# de prévia não abre o formulário, nem o do ICS gere um convite. Não reaproveita o verificador `crm_public_booking` da
# página antiga.
#
# Assinados (o conteúdo é legível, só não dá para alterar): prévia, formulário e gestão do convite. CIFRADOS
# (ENCRYPTED_PURPOSES): os que carregam uma capacidade de acesso que não pode vazar de quem vê o token. O do ICS leva o
# código do convite, que é o link de gestão da reunião. A chave da cifra é derivada do `secret_key_base` com o mesmo
# nome por purpose. Sem links cifrados emitidos antes desta troca, não há formato antigo a aceitar.
#
# O token sai em Base64 URL-safe sem padding para viajar como segmento de caminho ou parâmetro de URL.
class Crm::BookingV2::Tokens
  PURPOSES = %w[preview form ics invite_manage].freeze
  ENCRYPTED_PURPOSES = %w[ics].freeze
  KEY_SALT_PREFIX = 'crm_booking_v2_'.freeze

  class UnknownPurpose < ArgumentError; end

  def self.generate(purpose, payload, expires_in:)
    codec = codec(purpose)
    raw = if encrypted?(purpose)
            codec.encrypt_and_sign(payload, purpose: purpose, expires_in: expires_in)
          else
            codec.generate(payload, purpose: purpose, expires_in: expires_in)
          end
    Base64.urlsafe_encode64(raw, padding: false)
  end

  # Devolve o payload, ou nil quando o token é de outro purpose, venceu, foi adulterado ou não é Base64.
  def self.verify(purpose, token)
    codec = codec(purpose)
    decode_and_verify(codec, purpose, token)
  end

  def self.decode_and_verify(codec, purpose, token)
    raw = Base64.urlsafe_decode64(token.to_s)
    return codec.verified(raw, purpose: purpose) unless encrypted?(purpose)

    codec.decrypt_and_verify(raw, purpose: purpose)
  rescue ArgumentError, ActiveSupport::MessageEncryptor::InvalidMessage
    # Base64 inválido ou cifra que não confere: token que não saiu daqui.
    nil
  end
  private_class_method :decode_and_verify

  def self.encrypted?(purpose)
    ENCRYPTED_PURPOSES.include?(purpose.to_s)
  end
  private_class_method :encrypted?

  def self.codec(purpose)
    raise UnknownPurpose, "unknown booking token purpose: #{purpose}" unless PURPOSES.include?(purpose.to_s)

    name = "#{KEY_SALT_PREFIX}#{purpose}"
    return Rails.application.message_verifier(name) unless encrypted?(purpose)

    key = Rails.application.key_generator.generate_key(name, ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key, serializer: :json)
  end
  private_class_method :codec
end
