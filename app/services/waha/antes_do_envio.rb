# #1865 — caixa WAHA comum: quem envia é o conector dentro do motor (o chat2you só manda o webhook `message_created`).
# Antes do webhook sair, no próprio WebhookJob (fila dele, fora do EventDispatcherJob), o contato fica salvo na agenda do
# aparelho (Waha::AgendaDoContato) e, se for resposta, a conversa fica lida (ConversaCanal::LeituraAoResponder).
# Custo: só na primeira mensagem a cada contato (depois, o Redis responde), até alguns segundos com o motor lento; depois
# de uma falha, o contato fica um tempo sem nova tentativa (Waha::AgendaDoContato::FALHA_TTL). A campanha WhatsApp API
# continua criando uma mensagem por vez, com 3 a 8 s entre destinatários (WhatsappApiCampaigns::DeliveryEngine), e
# cada webhook leva o próprio salvamento: o intervalo real varia esses segundos, como já varia com a fila.
# Ordem: com trabalho a fazer, a mensagem segura a conversa até o webhook sair (ConversaCanal::EnvioEmOrdem), e a
# seguinte da mesma conversa espera. Nada daqui impede o webhook: falha vira log.
class Waha::AntesDoEnvio
  EVENT = 'message_created'.freeze

  # Payload do webhook da caixa: só a mensagem que sai para o cliente passa pelo trabalho; o bloco (o webhook) sai sempre.
  def self.em_ordem(payload, &)
    antes = para(payload)
    return yield if antes.nil?

    ConversaCanal::EnvioEmOrdem.executar(antes.conversation, -> { antes.trabalho? }) do
      antes.perform
      yield
    end
  end

  def self.para(payload)
    data = payload.to_h.with_indifferent_access
    return unless saindo?(data)

    antes = Message.find_by(id: data[:id])&.then { |message| new(message) }
    antes if antes&.aplicavel?
  rescue StandardError => e
    Rails.logger.info("[waha][antes_do_envio] falhou #{e.class}")
    nil
  end

  def self.saindo?(data)
    data[:event] == EVENT && data[:message_type].to_s == 'outgoing' && !data[:private]
  end

  def initialize(message)
    @message = message
  end

  def conversation
    @message.conversation
  end

  def aplicavel?
    canal.is_a?(Channel::Api) && canal.waha_provider? && Waha::AgendaDoContato.enabled?(@message.account) &&
      !Crm::WhatsappGroupDetector.group_conversation?(conversation)
  end

  def trabalho?
    agenda.a_fazer? || ConversaCanal::LeituraAoResponder.a_fazer?(@message)
  rescue StandardError => e
    Rails.logger.info("[waha][antes_do_envio] trabalho? falhou message=#{@message.id} #{e.class}")
    false
  end

  def perform
    agenda.garantir
    ConversaCanal::LeituraAoResponder.marcar(@message, waha_client: cliente)
  rescue StandardError => e
    Rails.logger.info("[waha][antes_do_envio] falhou message=#{@message.id} #{e.class}")
  end

  private

  def agenda
    @agenda ||= Waha::AgendaDoContato.new(client: cliente, session: sessao, contact: conversation.contact)
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
