# Fuso da conta do WhatsApp (WABA) de uma caixa, como a Meta o usa para virar o mês da franquia de respostas (#1592):
# "Essa redefinição acontece à meia-noite, de acordo com o fuso horário da conta de mensagens"
# (developers.facebook.com/docs/whatsapp/pricing, atualizada em 30/09/2026).
#
# A Graph devolve só um número (`GET /{waba_id}?fields=timezone_id`, campo `timezone_id` do WhatsApp Business Account).
# A tabela oficial da Meta (config/whatsapp_meta_timezone_ids.yml) traduz o número em nome (`TZ_AMERICA_SAO_PAULO`), e
# o nome vira o fuso IANA (`America/Sao_Paulo`) pela própria base IANA do TZInfo, sem tabela escrita à mão.
#
# Lido uma vez por WABA e guardado no cache (Redis em produção) por 30 dias: o fuso da WABA quase nunca muda e a Graph
# o devolve de novo a qualquer hora, então não precisa de coluna nem de tabela. Falha (sem token, Meta fora, número
# sem fuso conhecido) fica guardada por 10 minutos, para não perguntar de novo a cada contagem. Devolve nil quando não
# sabe; quem chama usa o fuso da conta do Chat2You.
class Whatsapp::WabaTimezone
  CACHE_TTL = 30.days
  FAILURE_TTL = 10.minutes
  TIMEOUT_SECONDS = 5
  UNKNOWN = ''.freeze
  META_IDS_PATH = Rails.root.join('config/whatsapp_meta_timezone_ids.yml')

  def self.for(channel)
    new(channel).zone
  end

  # { 25 => 'TZ_AMERICA_SAO_PAULO', ... }, da tabela oficial.
  def self.meta_names
    @meta_names ||= YAML.safe_load_file(META_IDS_PATH).transform_keys(&:to_i).freeze
  end

  # 'TZ_AMERICA_SAO_PAULO' => 'America/Sao_Paulo'. O nome da Meta é o IANA em maiúsculas, com `/` e `-` virando `_`
  # e o sinal dos fusos `Etc/GMT+N` escrito por extenso (`TZ_ETC_GMT_PLUS_1`).
  def self.iana_by_meta_name
    @iana_by_meta_name ||= TZInfo::Timezone.all_identifiers.each_with_object({}) do |identifier, index|
      upper = identifier.upcase.tr('/', '_')
      index["TZ_#{upper.tr('-', '_')}"] ||= identifier
      index["TZ_#{upper.gsub('+', '_PLUS_').gsub('-', '_MINUS_')}"] = identifier
    end.freeze
  end

  def self.iana_for(timezone_id)
    iana_by_meta_name[meta_names[Integer(timezone_id.to_s, exception: false)]]
  end

  def initialize(channel)
    @channel = channel
  end

  def zone
    return unless askable?

    identifier = Rails.cache.read(cache_key)
    if identifier.nil?
      identifier = ask_meta
      Rails.cache.write(cache_key, identifier, expires_in: identifier == UNKNOWN ? FAILURE_TTL : CACHE_TTL)
    end
    return if identifier == UNKNOWN

    ActiveSupport::TimeZone[identifier]
  end

  private

  def cache_key
    ['whatsapp_waba_timezone', waba_id]
  end

  def ask_meta
    return failure('no_token') if @channel.template_access_token.blank?

    response = HTTParty.get(url, query: { fields: 'timezone_id' }, timeout: TIMEOUT_SECONDS,
                                 headers: { 'Authorization' => "Bearer #{@channel.template_access_token}" })
    return failure("http_#{response.code}") unless response.success?

    timezone_id = response.parsed_response.is_a?(Hash) ? response.parsed_response['timezone_id'] : nil
    self.class.iana_for(timezone_id) || failure("unknown_timezone_id_#{timezone_id.to_s.first(8)}")
  rescue StandardError => e
    failure(e.class.name)
  end

  def failure(reason)
    Rails.logger.warn "[Whatsapp::WabaTimezone] channel=#{@channel.id} timezone_lookup_failed=#{reason}"
    UNKNOWN
  end

  def url
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{Whatsapp::Templates::MetaClient.api_version}/#{waba_id}"
  end

  # Só WhatsApp oficial (Cloud): na 360Dialog o `api_key` é da 360Dialog e não pode ir para a Meta. O id da WABA é
  # número; outro formato mudaria o endereço que recebe o token.
  def askable?
    @channel.provider == 'whatsapp_cloud' && Integer(waba_id.to_s, exception: false)&.positive?
  end

  def waba_id
    @channel.waba_id
  end
end
