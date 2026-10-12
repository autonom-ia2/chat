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
# (integração sem configuração, caixa sem sessão, WAHA com erro, sem resposta ou com resposta fora do formato) e
# `waha_refused` (a WAHA recusou o pedido). A
# consulta só lê: com erro ou timeout nada saiu, e quem chama decide se tenta de novo (o `Sender` devolve o aviso à
# fila até o limite do tipo; o teste recusa na hora). A consulta espera no máximo LOOKUP_TIMEOUT segundos e, com
# `outage` (a rodada do cron, `Notices::WahaOutage`), não consulta de novo o que já falhou na rodada. Pedido que a WAHA
# recusa de vez (4xx que não seja 408, 425 ou 429) é `waha_refused`, definitivo.
class Crm::BookingV2::Notices::WahaChat
  LOOKUP_TIMEOUT = 5
  # 4xx passageiros: tempo esgotado, cedo demais e pedidos demais. Voltam para a fila como o 5xx.
  TRANSIENT_STATUSES = [408, 425, 429].freeze

  # A WAHA respondeu 200, mas sem o que a consulta promete: problema desta sessão, não do servidor.
  MalformedAnswer = Class.new(StandardError)

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

  # A recusa foi falha da WAHA na consulta (5xx, 408, 425, 429, sem conexão, timeout, resposta fora do formato, WAHA ou
  # caixa já marcada na rodada): vale tentar de novo depois. Integração sem configuração, caixa sem sessão e pedido
  # recusado pela WAHA (os outros 4xx) não mudam sozinhos: não.
  def retryable?
    @retryable == true
  end

  # nil quando pode abrir a conversa (e os atributos ficam no contato pelo `Waha::ContactChatId.store!`: gravados se
  # ele já existe, só atribuídos se é novo, para quem chama gravar junto); senão o motivo.
  def prepare
    return 'waha_unavailable' unless Waha::Config.enabled? && session.present?
    return transient_failure if outage&.down?(inbox)

    store_or_refuse(timed_lookup)
  rescue MalformedAnswer
    log_failure('MalformedAnswer')
    outage&.inbox_down!(inbox)
    transient_failure
  rescue Waha::Client::Error => e
    # A mensagem do erro traz a URL com o telefone: no log vai só a classe.
    log_failure(e.class.name)
    lookup_failure(e)
  end

  private

  attr_reader :inbox, :contact, :outage

  def timed_lookup
    outage ? outage.timed { lookup } : lookup
  end

  def store_or_refuse(chat_id)
    return 'no_whatsapp' if chat_id.blank?

    Waha::ContactChatId.store!(contact, chat_id)
    nil
  end

  def log_failure(name)
    Rails.logger.warn("CRM booking notice WAHA lookup failed for inbox #{inbox.id}: #{name}")
  end

  # Sem resposta (timeout, conexão) ou 5xx: o servidor WAHA, que é um só, fica fora na rodada. 408, 425 e 429 só
  # devolvem o aviso à fila. Os outros 4xx (chave, sessão ou número que a WAHA não aceita) vieram rápido e não mudam
  # sozinhos: recusa definitiva.
  def lookup_failure(error)
    status = error.status.to_i
    return 'waha_refused' if status.between?(400, 499) && TRANSIENT_STATUSES.exclude?(status)

    outage&.server_down! unless TRANSIENT_STATUSES.include?(status)
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
  # diz nada do número: é falha desta sessão da WAHA.
  def lookup
    phone = contact.phone_number.to_s.delete_prefix('+')
    result = client.check_contact_exists(phone: phone, session: session, timeout: LOOKUP_TIMEOUT)
    raise MalformedAnswer unless result.is_a?(Hash)
    return '' unless ActiveModel::Type::Boolean.new.cast(result['numberExists'])
    raise MalformedAnswer if result['chatId'].blank?

    result['chatId'].to_s
  end

  def client
    @client ||= Waha::Client.new
  end
end
