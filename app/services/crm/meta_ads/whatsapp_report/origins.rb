# De quais números da conta o resumo pode sair (#1100, F4b): só os conectados agora.
#
# - `waha`: caixa API do conector WhatsApp API com a sessão `WORKING` no motor (o mesmo estado que a tela de
#   caixas mostra como conectado). Envia texto livre.
# - `whatsapp_cloud` (inclui o Híbrido): caixa do WhatsApp Oficial sem reautorização pendente. Envia só modelo
#   aprovado; a lista traz o status dos dois modelos.
#
# 360dialog e Twilio ficam fora. A lista é refeita a cada leitura e na hora do envio: um número que caiu deixa de
# ser origem válida.
class Crm::MetaAds::WhatsappReport::Origins
  WAHA = 'waha'.freeze
  CLOUD = 'whatsapp_cloud'.freeze
  WAHA_CONNECTED = 'WORKING'.freeze

  Origin = Struct.new(:inbox, :kind, :phone_number, :session, keyword_init: true) do
    def channel
      inbox.channel
    end

    def waha?
      kind == WAHA
    end

    def payload
      templates = waha? ? nil : Crm::MetaAds::WhatsappReport::TemplateStatus.for(channel)
      { inbox_id: inbox.id, name: inbox.name, phone_number: phone_number, kind: kind, templates: templates }
    end
  end

  def initialize(account)
    @account = account
  end

  def list
    @list ||= inboxes.filter_map { |inbox| origin_for(inbox) }
  end

  def find(inbox_id)
    list.find { |origin| origin.inbox.id == inbox_id.to_i }
  end

  private

  def inboxes
    @account.inboxes.where(channel_type: %w[Channel::Api Channel::Whatsapp]).includes(:channel).order(:id)
  end

  def origin_for(inbox)
    channel = inbox.channel
    return cloud_origin(inbox) if channel.is_a?(Channel::Whatsapp)

    waha_origin(inbox) if channel.waha_provider?
  end

  def cloud_origin(inbox)
    channel = inbox.channel
    return if channel.provider != CLOUD || channel.reauthorization_required?

    Origin.new(inbox: inbox, kind: CLOUD, phone_number: channel.phone_number)
  end

  # O motor fora do ar conta como desconectado: o número não é origem até a sessão voltar. O detalhe do erro
  # leva a URL do motor; no log vai só a classe.
  def waha_origin(inbox)
    session = inbox.channel.additional_attributes.to_h['session']
    return if session.blank? || !Waha::Config.enabled?

    remote = waha_client.get_session(session).to_h
    return unless remote['status'] == WAHA_CONNECTED

    Origin.new(inbox: inbox, kind: WAHA, phone_number: waha_phone(remote), session: session)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[meta_ads_whatsapp_report] origin_unreachable inbox=#{inbox.id} error=#{e.class}")
    nil
  end

  # `me.id` vem como "5511999990000@c.us".
  def waha_phone(remote)
    digits = remote.dig('me', 'id').to_s.split('@').first
    digits.present? ? "+#{digits}" : nil
  end

  def waha_client
    @waha_client ||= Waha::Client.new
  end
end
