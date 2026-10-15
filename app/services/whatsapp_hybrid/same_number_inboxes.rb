# Outras caixas WhatsApp API comuns (WAHA, canal API com provider=waha) da mesma conta ligadas ao número desta caixa
# oficial (#1487). Duas conexões no mesmo número aumentam o risco de bloqueio: a aba avisa, sem impedir nada.
# A sessão WAHA comum tem o nome igual ao número. Celular brasileiro antigo, sem o 9 (55 + DDD + 8 dígitos), é o
# mesmo número que o atual com o 9: os dois viram a forma sem o 9 antes de comparar.
class WhatsappHybrid::SameNumberInboxes
  BRAZIL = '55'.freeze
  # 55 + DDD (2) + 9 + 8 dígitos.
  BRAZIL_MOBILE_LENGTH = 13
  NINTH_DIGIT_INDEX = 4

  def self.canonical(number)
    digits = number.to_s.delete('^0-9')
    return digits unless digits.start_with?(BRAZIL) && digits.length == BRAZIL_MOBILE_LENGTH && digits[NINTH_DIGIT_INDEX] == '9'

    digits[0, NINTH_DIGIT_INDEX] + digits[(NINTH_DIGIT_INDEX + 1)..]
  end

  # A aba avisa antes de conectar também: aí ainda não há conexão, só a conta e o número da caixa oficial.
  def initialize(account_id:, phone:)
    @account_id = account_id
    @phone = phone
  end

  def names
    number = self.class.canonical(@phone)
    return [] if number.blank?

    waha_channels.filter_map do |channel|
      channel.inbox.name if channel.inbox && self.class.canonical(channel.additional_attributes.to_h['session']) == number
    end
  end

  private

  def waha_channels
    Channel::Api.where(account_id: @account_id).where("additional_attributes ->> 'provider' = ?", 'waha').includes(:inbox)
  end
end
