# #1865 — caixa WAHA comum: quem envia é o conector dentro do motor (o chat2you só manda o webhook `message_created`).
# Antes do webhook sair, no próprio WebhookJob (fila dele, fora do EventDispatcherJob), o contato fica salvo na agenda do
# aparelho (Waha::AgendaDoContato) e, se for resposta, a conversa fica lida (ConversaCanal::LeituraAoResponder).
# Custo: só na primeira mensagem a cada contato (depois, o Redis responde), até alguns segundos com o motor lento; depois
# de uma falha, o contato fica um tempo sem nova tentativa (Waha::AgendaDoContato::FALHA_TTL). A campanha WhatsApp API
# continua criando uma mensagem por vez, com 3 a 8 s entre destinatários (WhatsappApiCampaigns::DeliveryEngine), e
# cada webhook leva o próprio salvamento: o intervalo real varia esses segundos, como já varia com a fila. Duas
# mensagens ao mesmo contato não se ultrapassam: a segunda espera a decisão da primeira (trava do AgendaDoContato).
# Nada daqui impede o webhook: falha vira log.
class Waha::AntesDoEnvio
  EVENT = 'message_created'.freeze

  # Payload do webhook da caixa: só a mensagem que sai para o cliente.
  def self.para_payload(payload)
    data = payload.to_h.with_indifferent_access
    return unless data[:event] == EVENT && data[:message_type].to_s == 'outgoing' && !data[:private]

    message = Message.find_by(id: data[:id])
    new(message).perform if message
  rescue StandardError => e
    Rails.logger.info("[waha][antes_do_envio] falhou message=#{data && data[:id]} #{e.class}")
  end

  def initialize(message)
    @message = message
  end

  def perform
    return unless aplicavel?

    Waha::AgendaDoContato.new(client: cliente, session: sessao, contact: @message.conversation.contact).garantir
    ConversaCanal::LeituraAoResponder.marcar(@message, waha_client: cliente)
  end

  private

  def aplicavel?
    canal.is_a?(Channel::Api) && canal.waha_provider? && Waha::AgendaDoContato.enabled?(@message.account) &&
      !Crm::WhatsappGroupDetector.group_conversation?(@message.conversation)
  end

  def canal
    @message.inbox.channel
  end

  def sessao
    canal.additional_attributes.to_h['session']
  end

  def cliente
    @cliente ||= ConversaCanal::ClienteDoMotor.para(canal)
  end
end
