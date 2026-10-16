# Outras caixas WhatsApp API comuns (WAHA, canal API com provider=waha) da mesma conta ligadas ao número desta caixa
# oficial (#1487). Duas conexões no mesmo número aumentam o risco de bloqueio: a aba avisa, sem impedir nada.
#
# Só conta caixa cuja sessão está viva no motor (conectada, subindo ou mostrando QR): caixa antiga deslogada ou
# apagada no motor não é segunda conexão. Uma consulta ao motor (lista de sessões), guardada por um minuto, porque a
# aba consulta a conexão a cada poucos segundos. Motor fora: sem aviso (nunca um aviso inventado).
# O número vem do aparelho conectado na sessão (`me.id`) quando o motor informa; senão, do nome da sessão (a sessão
# WAHA comum nasce com o nome igual ao número; caixas migradas podem ter outro nome, por isso o nome é procurado na
# lista do motor e não comparado como número). Celular brasileiro antigo, sem o 9, é o mesmo número que o atual.
class WhatsappHybrid::SameNumberInboxes
  LIVE_STATUSES = %w[WORKING STARTING SCAN_QR_CODE].freeze
  CACHE_TTL = 1.minute
  BRAZIL = '55'.freeze
  # 55 + DDD (2) + 9 + 8 dígitos; o 9 a mais só existe antes de um celular (6 a 9).
  BRAZIL_MOBILE_LENGTH = 13
  NINTH_DIGIT_INDEX = 4
  MOBILE_FIRST_DIGITS = %w[6 7 8 9].freeze

  def self.canonical(number)
    digits = number.to_s.delete('^0-9')
    return digits unless extra_ninth_digit?(digits)

    digits[0, NINTH_DIGIT_INDEX] + digits[(NINTH_DIGIT_INDEX + 1)..]
  end

  def self.extra_ninth_digit?(digits)
    digits.start_with?(BRAZIL) && digits.length == BRAZIL_MOBILE_LENGTH && digits[NINTH_DIGIT_INDEX] == '9' &&
      MOBILE_FIRST_DIGITS.include?(digits[NINTH_DIGIT_INDEX + 1])
  end

  # A aba avisa antes de conectar também: aí ainda não há conexão, só a conta e o número da caixa oficial.
  def initialize(account_id:, phone:, client: Waha::Client.new)
    @account_id = account_id
    @phone = phone
    @client = client
  end

  def names
    number = self.class.canonical(@phone)
    channels = waha_channels.to_a
    return [] if number.blank? || channels.empty?

    Rails.cache.fetch(cache_key(number), expires_in: CACHE_TTL) { matching_names(channels, number) }
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] same number check skipped account=#{@account_id}: #{e.class}")
    []
  end

  private

  def matching_names(channels, number)
    live = live_sessions
    channels.filter_map do |channel|
      session = live[channel.additional_attributes.to_h['session'].to_s]
      channel.inbox.name if session && self.class.canonical(session_number(session)) == number
    end
  end

  # Nome da sessão → sessão, só as vivas.
  def live_sessions
    Array(@client.list_sessions).select { |session| LIVE_STATUSES.include?(session['status']) }.index_by { |session| session['name'].to_s }
  end

  def session_number(session)
    session.dig('me', 'id').to_s.split('@').first.presence || session['name']
  end

  def waha_channels
    Channel::Api.where(account_id: @account_id).where("additional_attributes ->> 'provider' = ?", 'waha').includes(:inbox)
                .select(&:inbox)
  end

  def cache_key(number)
    "whatsapp_hybrid:same_number:#{@account_id}:#{number}"
  end
end
