# Lida no WhatsApp do cliente (#1702): quando o atendente abre a conversa no painel, a última mensagem recebida ganha os
# tiques azuis no aparelho do cliente, como no app. Quem chama é o ConversaCanal::LeituraNoCanalJob, enfileirado pelo
# update_last_seen do painel (ConversaCanal::LeituraAoAbrir).
#
# - WhatsApp oficial (Cloud API) e caixa híbrida: ConversaCanal::LeituraNaCloud. A mensagem recebida na caixa híbrida
#   chega sempre pela Meta (o WhatsApp API só envia), então o canal que recebeu é a Cloud.
# - Caixa WhatsApp API (WAHA): POST /api/sendSeen da conversa (marca as não lidas do chat). Grupo fica de fora, como no
#   "digitando" (Conversations::ChannelTyping::Deliverer).
# - Uma vez por mensagem: a hora do aviso fica em `content_attributes.read_receipt_sent_at` da mensagem recebida. Marcar a
#   última marca as anteriores (doc da Meta), então só a última é olhada.
# - Prazo: a Meta só aceita marcar até 30 dias depois do recebimento; mais velha que isso, nada é enviado.
# - Lida não é mensagem: não abre nem renova a janela de 24 h (que conta a partir da última mensagem do cliente) e não é
#   cobrada (só modelo é cobrado). https://developers.facebook.com/docs/whatsapp/pricing
# - Falha do provedor: log info (sem token e sem corpo), nada gravado; a próxima abertura tenta de novo.
class ConversaCanal::LeituraNoCanal
  CHAVE = 'read_receipt_sent_at'.freeze
  FLAG = ConversaCanal::Pele::FLAG
  PRAZO = 30.days
  TIMEOUT = 5
  # Maior que o envio (TIMEOUT) com folga; depois de gravado, `read_receipt_sent_at` é quem segura.
  RESERVA = 30.seconds
  JID_SEPARATOR = '@'.freeze

  def self.supports?(conversation)
    return false unless conversation.account.feature_enabled?(FLAG)

    channel = conversation.inbox.channel
    case channel
    when Channel::Whatsapp then channel.provider == 'whatsapp_cloud'
    when Channel::Api then channel.waha_provider? && Waha::Config.enabled?
    else false
    end
  end

  def initialize(conversation:, waha_client: nil)
    @conversation = conversation
    @waha_client = waha_client
  end

  # Há o que avisar: canal atendido e a última recebida (dentro do prazo) ainda sem o aviso.
  def pendente?
    self.class.supports?(@conversation) && mensagem.present? && !marcada?(mensagem)
  end

  # A reserva da mensagem cobre o envio: dois jobs da mesma conversa (fila atrasada, debounce vencido) não mandam o
  # aviso duas vezes. Falha do provedor solta a reserva para a próxima abertura tentar.
  def perform
    return unless pendente?
    return unless reservar

    # #2246: antes do pedido, porque a leitura pode voltar do motor antes da resposta do canal.
    ConversaCanal::LeituraDoSistema.registrar(@conversation, ate: ate_onde_marca)
    enviar ? registrar : soltar
  end

  private

  def canal
    @conversation.inbox.channel
  end

  def mensagem
    return @mensagem if defined?(@mensagem)

    # reorder: Message tem default_scope por created_at asc. A Cloud marca pelo wamid (source_id); o WAHA marca o chat
    # inteiro (sendSeen sem messageIds), e o conector nem sempre grava source_id na recebida.
    recebidas = @conversation.messages.incoming
    recebidas = recebidas.where.not(source_id: [nil, '']) if canal.is_a?(Channel::Whatsapp)
    ultima = recebidas.reorder(created_at: :desc, id: :desc).first
    @mensagem = ultima if ultima && ultima.created_at >= PRAZO.ago
  end

  # #2246: a Cloud marca a mensagem e as anteriores; o sendSeen do WAHA marca o chat inteiro, inclusive o que chegou agora.
  def ate_onde_marca
    canal.is_a?(Channel::Api) ? Time.current : mensagem.created_at
  end

  def chave_da_reserva
    "conversa_canal:leitura:mensagem:#{mensagem.id}"
  end

  def reservar
    Redis::Alfred.set(chave_da_reserva, '1', nx: true, ex: RESERVA.to_i)
  end

  def soltar
    Redis::Alfred.delete(chave_da_reserva)
  end

  def marcada?(message)
    message.content_attributes.to_h[CHAVE].present?
  end

  def enviar
    case canal
    when Channel::Whatsapp then ConversaCanal::LeituraNaCloud.new(message: mensagem, timeout: TIMEOUT).enviar
    when Channel::Api then enviar_pelo_waha
    else false
    end
  end

  def enviar_pelo_waha
    sessao = canal.additional_attributes.to_h['session']
    chat_id = Waha::ContactChatId.primary(@conversation.contact, contact_inbox: @conversation.contact_inbox).to_s
    return false if sessao.blank? || chat_id.exclude?(JID_SEPARATOR)
    return false if Crm::WhatsappGroupDetector.group_conversation?(@conversation)

    (@waha_client || ConversaCanal::ClienteDoMotor.para(canal)).send_seen(session: sessao, chat_id: chat_id, timeout: TIMEOUT)
    true
  rescue Waha::Client::Error => e
    # A mensagem do erro do cliente traz URL e corpo: no log, só a classe e o status.
    Rails.logger.info("[conversa_canal][leitura] waha refused conversation=#{@conversation.id} #{e.class} status=#{e.status}")
    false
  end

  def registrar
    mensagem.with_lock do
      attrs = mensagem.content_attributes.to_h
      next if attrs[CHAVE].present?

      ConversaCanal::GravarNaMensagem.atualizar!(mensagem, content_attributes: attrs.merge(CHAVE => Time.current.iso8601))
    end
  end
end
