# Configuração do resumo e do alerta no WhatsApp de uma conexão (#1100, F4b): o que a tela lê e grava.
#
# Vem desligado. Para ligar (resumo ou alerta) é preciso um número de origem conectado da conta e um número de
# destino válido; no Oficial, também o modelo do tipo aprovado. Desligar sempre funciona, mesmo sem origem: só se
# confere o que o pedido liga ou troca (um tipo que acende, a origem, o destino).
# Chaves ausentes no pedido ficam como estão.
#
# Toda gravação junta só as chaves que mudaram sobre a linha relida sob lock, para o envio (que grava
# last_*_at/last_error) e a tela (que grava os flags) não apagarem a mudança um do outro.
class Crm::MetaAds::WhatsappReport::Settings
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  SCHEDULE = { summary_local_time: '08:00', alert_local_time: '16:30', time_zone: 'America/Sao_Paulo' }.freeze
  FLAGS = Crm::MetaAdsConnection::WHATSAPP_REPORT_FLAGS

  def initialize(connection)
    @connection = connection
  end

  def payload
    settings = @connection.whatsapp_report_settings
    {
      enabled: settings['enabled'], alert_enabled: settings['alert_enabled'], inbox_id: settings['inbox_id'],
      phone: @connection.whatsapp_report_phone, last_summary_at: settings['last_summary_at'],
      last_alert_at: settings['last_alert_at'], last_error: settings['last_error'], last_error_at: settings['last_error_at'],
      origins: origins.list.map(&:payload), template_texts: template_texts, schedule: SCHEDULE
    }
  end

  # params: { 'enabled', 'alert_enabled', 'inbox_id', 'phone' }, só as chaves enviadas.
  def update!(params)
    changes = flags(params)
    changes['inbox_id'] = parse_inbox(params['inbox_id']) if params.key?('inbox_id')
    phone = params.key?('phone') ? parse_phone(params['phone']) : @connection.whatsapp_report_phone
    validate_on!(@connection.whatsapp_report_settings, changes, phone)

    attributes = params.key?('phone') ? { whatsapp_report_phone: phone } : {}
    store!(changes, attributes)
  end

  # O que falta para enviar agora (teste ou agendado): a origem salva, ainda conectada, e o destino salvo.
  def origin!
    inbox_id = @connection.whatsapp_report_settings['inbox_id']
    raise Error, 'origin_required' if inbox_id.blank?
    raise Error, 'phone_required' if @connection.whatsapp_report_phone.blank?

    origins.find(inbox_id) || raise(Error, 'inbox_not_connected')
  end

  def record_sent!(kind, at = Time.current)
    stamp = kind == 'alert' ? 'last_alert_at' : 'last_summary_at'
    store!(stamp => at.iso8601, 'last_error' => nil, 'last_error_at' => nil)
  end

  def record_error!(code, at = Time.current)
    store!('last_error' => code, 'last_error_at' => at.iso8601)
  end

  def origins
    @origins ||= Crm::MetaAds::WhatsappReport::Origins.new(@connection.account)
  end

  private

  # with_lock relê a linha (SELECT ... FOR UPDATE) antes do merge.
  def store!(values, attributes = {})
    @connection.with_lock { @connection.update!(attributes.merge(whatsapp_report: @connection.whatsapp_report_settings.merge(values))) }
  end

  def flags(params)
    bool = ActiveModel::Type::Boolean.new
    FLAGS.values.select { |flag| params.key?(flag) }.index_with { |flag| bool.cast(params[flag]) == true }
  end

  def parse_phone(raw)
    return if raw.to_s.strip.empty?

    region = Autonomia::Prospecting::PhoneContract.region_for(@connection.account)
    Autonomia::Prospecting::PhoneContract.parse(raw, region: region)&.e164 || raise(Error, 'invalid_phone')
  end

  # Uma origem escolhida precisa estar conectada agora; caixa de outra conta nunca aparece na lista.
  def parse_inbox(raw)
    return if raw.blank?

    origin = origins.find(raw) || raise(Error, 'inbox_not_connected')
    origin.inbox.id
  end

  # Confere só o que o pedido liga ou troca enquanto algum tipo fica ligado. Desligar nunca esbarra aqui.
  def validate_on!(saved, changes, phone)
    settings = saved.merge(changes)
    kinds = on_kinds(settings)
    return if kinds.empty?

    to_check = kinds_to_check(saved, settings, kinds)
    validate_numbers!(settings, phone) if to_check || phone != @connection.whatsapp_report_phone
    validate_origin!(settings['inbox_id'], to_check) if to_check
  end

  # Os tipos ligados cujo envio o pedido muda: todos, se a origem troca; senão os que acendem agora. nil = nenhum.
  def kinds_to_check(saved, settings, kinds)
    return kinds if settings['inbox_id'] != saved['inbox_id']

    (kinds - on_kinds(saved)).presence
  end

  def validate_numbers!(settings, phone)
    raise Error, 'origin_required' if settings['inbox_id'].blank?
    raise Error, 'phone_required' if phone.blank?
  end

  def validate_origin!(inbox_id, kinds)
    origin = origins.find(inbox_id) || raise(Error, 'inbox_not_connected')
    validate_templates!(origin, kinds) unless origin.waha?
  end

  def on_kinds(settings)
    FLAGS.select { |_kind, flag| settings[flag] }.keys
  end

  # No Oficial cada tipo ligado precisa do seu modelo aprovado.
  def validate_templates!(origin, kinds)
    kinds.each do |kind|
      raise Error, 'template_not_approved' unless Crm::MetaAds::WhatsappReport::TemplateStatus.approved(origin.channel, kind)
    end
  end

  def template_texts
    Crm::MetaAds::WhatsappReport::TemplateStatus::NAMES.to_h do |kind, name|
      [kind, { name: name, body: I18n.t("meta_ads_whatsapp_report.templates.#{kind}") }]
    end
  end
end
