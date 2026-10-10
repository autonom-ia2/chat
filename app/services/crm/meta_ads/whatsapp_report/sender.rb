# Envia o resumo ou o alerta ao número do dono (#1100, F4b). Não cria contato nem conversa: o destinatário é o
# dono da conta, não um cliente, e uma conversa dispararia agente, automação e follow-up.
#
# - WAHA: confere o número no WhatsApp (resolve o nono dígito), gera o id e manda texto livre. Sem resposta do
#   envio (`Waha::Client::Timeout`) não dá para saber se saiu: vira `send_uncertain` e nunca é reenviado.
# - Oficial: só o modelo aprovado do tipo, com o nome exato e o idioma pt_BR. Sem ele, `template_not_approved` e
#   nada sai; o envio nunca troca para texto livre.
#
# Falha vira Error com o código que a tela e o `last_error` mostram. No log vai só a classe do erro e o número
# mascarado: a URL do WAHA leva o número.
class Crm::MetaAds::WhatsappReport::Sender
  Error = Crm::MetaAds::WhatsappReport::Settings::Error

  # Falhas de rede no Oficial: o pedido não chegou à Meta (nada saiu) ou a conexão caiu no meio (pode ter saído).
  CLOUD_NOT_SENT = [SocketError, Net::OpenTimeout, Errno::ECONNREFUSED, HTTParty::Error].freeze
  CLOUD_UNCERTAIN = [Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, Errno::EPIPE, OpenSSL::SSL::SSLError].freeze

  # `settings`: a do controller, para não montar de novo a lista de origens (cada WAHA é uma consulta).
  def initialize(connection, settings: nil)
    @connection = connection
    @settings = settings || Crm::MetaAds::WhatsappReport::Settings.new(connection)
    @builder = Crm::MetaAds::WhatsappReport::MessageBuilder.new(connection.account)
  end

  def send_summary(digest, test: false)
    origin = @settings.origin!
    if origin.waha?
      send_waha(origin, @builder.summary_text(digest, test: test))
    else
      send_cloud(origin, 'summary', @builder.summary_parameters(digest, test: test))
    end
  end

  def send_alert(alert)
    origin = @settings.origin!
    origin.waha? ? send_waha(origin, @builder.alert_text(alert)) : send_cloud(origin, 'alert', @builder.alert_parameters(alert))
  end

  private

  def phone
    @connection.whatsapp_report_phone
  end

  def digits
    phone.delete_prefix('+')
  end

  def send_waha(origin, text)
    client = Waha::Client.new
    chat_id = waha_chat_id(client, origin.session)
    id = before_send { client.new_message_id(origin.session) }
    client.send_text(session: origin.session, chat_id: chat_id, text: text, id: id)
    true
  rescue Waha::Client::Timeout => e
    failure!('send_uncertain', e)
  rescue Waha::Client::Error => e
    failure!('send_failed', e)
  end

  # Antes do envio, um Timeout ainda é falha clara: nada saiu.
  def waha_chat_id(client, session)
    result = before_send { client.check_contact_exists(phone: digits, session: session) }.to_h
    raise Error, 'whatsapp_number_not_found' unless ActiveModel::Type::Boolean.new.cast(result['numberExists']) && result['chatId'].present?

    result['chatId']
  end

  def before_send
    yield
  rescue Waha::Client::Error => e
    failure!('send_failed', e)
  end

  def send_cloud(origin, kind, parameters)
    template = Crm::MetaAds::WhatsappReport::TemplateStatus.approved(origin.channel, kind)
    raise Error, 'template_not_approved' if template.nil?

    info = { name: template['name'], namespace: template['namespace'], lang_code: Crm::MetaAds::WhatsappReport::TemplateStatus::LANGUAGE,
             parameters: parameters }
    message_id = origin.channel.send_template(digits, info, nil)
    raise Error, 'send_failed' if message_id.blank?

    true
  rescue *CLOUD_UNCERTAIN => e
    failure!('send_uncertain', e)
  rescue *CLOUD_NOT_SENT => e
    failure!('send_failed', e)
  end

  def failure!(code, error)
    Rails.logger.warn(
      "[meta_ads_whatsapp_report] #{code} account=#{@connection.account_id} to=#{CampaignImports::PhoneMask.mask(phone)} error=#{error.class}"
    )
    raise Error, code
  end
end
