# Tokens assinados do agendamento v2 (#1187). Cada uso tem o seu `purpose` e o seu verificador
# (`crm_booking_v2_<purpose>`): um token de prévia não abre o formulário, nem o do ICS gere um convite.
# Não reaproveita o verificador `crm_public_booking` da página antiga.
#
# O token sai em Base64 URL-safe sem padding para viajar como segmento de caminho ou parâmetro de URL.
class Crm::BookingV2::Tokens
  PURPOSES = %w[preview form ics invite_manage].freeze

  class UnknownPurpose < ArgumentError; end

  def self.generate(purpose, payload, expires_in:)
    raw = verifier(purpose).generate(payload, purpose: purpose, expires_in: expires_in)
    Base64.urlsafe_encode64(raw, padding: false)
  end

  # Devolve o payload, ou nil quando o token é de outro purpose, venceu, foi adulterado ou não é Base64.
  def self.verify(purpose, token)
    signed = verifier(purpose)
    decode_and_verify(signed, purpose, token)
  end

  def self.decode_and_verify(signed, purpose, token)
    signed.verified(Base64.urlsafe_decode64(token.to_s), purpose: purpose)
  rescue ArgumentError
    # Base64 inválido: token que não saiu daqui.
    nil
  end
  private_class_method :decode_and_verify

  def self.verifier(purpose)
    raise UnknownPurpose, "unknown booking token purpose: #{purpose}" unless PURPOSES.include?(purpose.to_s)

    Rails.application.message_verifier("crm_booking_v2_#{purpose}")
  end
  private_class_method :verifier
end
