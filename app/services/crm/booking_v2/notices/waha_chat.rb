# Antes de abrir uma conversa pelo nosso lado numa caixa WAHA (#1270): pergunta à WAHA, pela sessão da caixa, o chat id
# real do telefone do contato (`Waha::Client#check_contact_exists`, o mesmo da prospecção e do relatório de anúncios).
#
# Onde fica o chat id. O app Chatwoot da WAHA cria o contato pela API pública da caixa sem `source_id` (o Chatwoot
# gera um UUID) e guarda o chat id nos atributos do contato: `waha_whatsapp_chat_id`, `waha_whatsapp_jid` (`@c.us`) e
# `waha_whatsapp_lid` (`@lid`). Para mandar, a WAHA lê esses atributos e, sem eles, pergunta pelo telefone; ao receber,
# acha o contato por eles (ou pelo telefone) e usa a conversa dele nesta caixa. Gravar aqui os mesmos atributos, no
# mesmo formato, faz o aviso ir para o chat certo (também no número brasileiro sem o 9º dígito) e a resposta do
# cliente cair na MESMA conversa. O `ContactInbox` segue com o UUID, como o da WAHA.
#
# O chat id confirmado vira o `waha_whatsapp_chat_id`, como a WAHA faz a cada mensagem recebida; os outros atributos
# do contato ficam. Recusa, sem abrir conversa: `no_whatsapp` (o número não tem WhatsApp) e `waha_unavailable`
# (integração sem configuração, caixa sem sessão, WAHA com erro, sem resposta ou com resposta fora do formato). A
# consulta só lê: com erro ou timeout nada saiu, e quem chama decide se tenta de novo (o `Sender` devolve o aviso à
# fila até o limite do tipo; o teste recusa na hora). A consulta espera no máximo LOOKUP_TIMEOUT segundos e, com
# `outage` (a rodada do cron), uma caixa que falhou não é consultada de novo na mesma rodada.
class Crm::BookingV2::Notices::WahaChat
  CHAT_ID = 'waha_whatsapp_chat_id'.freeze
  JID = 'waha_whatsapp_jid'.freeze
  LID = 'waha_whatsapp_lid'.freeze
  LID_SUFFIX = '@lid'.freeze
  LOOKUP_TIMEOUT = 5

  # Só o caminho de texto da WAHA sem conversa abre uma; o oficial e o canal API nunca passam por aqui.
  def self.needed?(decision, inbox)
    decision.send? && decision.mode == :session && decision.conversation.nil? &&
      Crm::AgentBookingProfile.notice_channel_kind(inbox) == 'waha'
  end

  def initialize(inbox:, contact:, client: nil, outage: nil)
    @inbox = inbox
    @contact = contact
    @client = client
    @outage = outage
  end

  # A recusa foi falha da WAHA na consulta (erro 5xx, sem conexão, timeout, resposta fora do formato, caixa já marcada
  # na rodada): vale tentar de novo depois. Integração sem configuração, caixa sem sessão e pedido recusado pela WAHA
  # (4xx) não mudam sozinhos: não.
  def retryable?
    @retryable == true
  end

  # nil quando pode abrir a conversa (e os atributos ficam no contato: gravados se ele já existe, só atribuídos se é
  # novo, para quem chama gravar junto); senão o motivo.
  def prepare
    return 'waha_unavailable' unless Waha::Config.enabled? && session.present?
    return transient_failure if outage&.down?(inbox)

    store_or_refuse(lookup)
  rescue Waha::Client::Error => e
    # A mensagem do erro traz a URL com o telefone: no log vai só a classe.
    Rails.logger.warn("CRM booking notice WAHA lookup failed for inbox #{inbox.id}: #{e.class.name}")
    lookup_failure(e)
  end

  private

  attr_reader :inbox, :contact, :outage

  def store_or_refuse(chat_id)
    return 'no_whatsapp' if chat_id.blank?

    store!(chat_id)
    nil
  end

  # A WAHA respondeu e recusou o pedido (4xx: chave, sessão ou número que ela não aceita). Respondeu rápido e não
  # muda sozinha: não é caixa fora do ar, e tentar de novo não adianta.
  def refused_request?(error)
    error.status.to_i.between?(400, 499)
  end

  def lookup_failure(error)
    return 'waha_unavailable' if refused_request?(error)

    outage&.down!(inbox)
    transient_failure
  end

  def transient_failure
    @retryable = true
    'waha_unavailable'
  end

  def session
    inbox.channel.additional_attributes.to_h['session'].to_s
  end

  # O chat id, '' quando o número não tem WhatsApp. Resposta fora do formato (sem objeto, ou "existe" sem chat id) não
  # diz nada do número: é falha da WAHA.
  def lookup
    phone = contact.phone_number.to_s.delete_prefix('+')
    result = client.check_contact_exists(phone: phone, session: session, timeout: LOOKUP_TIMEOUT)
    raise Waha::Client::Error, 'check-exists sem objeto' unless result.is_a?(Hash)
    return '' unless ActiveModel::Type::Boolean.new.cast(result['numberExists'])
    raise Waha::Client::Error, 'check-exists sem chatId' if result['chatId'].blank?

    result['chatId'].to_s
  end

  def client
    @client ||= Waha::Client.new
  end

  # Como a WAHA faz a cada mensagem recebida: o chat id confirmado agora passa a ser o `waha_whatsapp_chat_id` (o
  # endereço que a WAHA usa para mandar) e vai também na chave do tipo dele (jid ou lid); a outra chave fica como está.
  def store!(chat_id)
    current = contact.custom_attributes.to_h
    merged = current.merge(CHAT_ID => chat_id, (chat_id.end_with?(LID_SUFFIX) ? LID : JID) => chat_id)
    return if merged == current

    contact.new_record? ? contact.assign_attributes(custom_attributes: merged) : contact.update!(custom_attributes: merged)
  end
end
