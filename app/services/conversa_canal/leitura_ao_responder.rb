# #1865 — lida no WhatsApp do cliente na hora de responder, como quem usa o app: abriu ou respondeu, leu. Soma à lida ao
# abrir a conversa (#1702, ConversaCanal::LeituraAoAbrir), que fica igual: aqui entra quem responde sem abrir (robô do
# n8n, follow-up, automação). Nunca na chegada da mensagem do cliente.
#
# Prepend em SendReplyJob para o WhatsApp oficial e o Híbrido (a lida vai pela Cloud, ConversaCanal::LeituraNaCloud); a
# caixa WAHA comum marca no Waha::AntesDoEnvio, antes de o webhook mandar a resposta ao conector.
# Reaproveita ConversaCanal::LeituraNoCanal: a mesma flag da lida (`conversa_cara_do_canal`), o mesmo prazo e a mesma
# marca `read_receipt_sent_at` (a IA da Autonomia, que já marca junto do "digitando", não manda de novo).
# Só com a flag `whatsapp_agenda_do_contato`. Vale também para a caixa WhatsApp oficial (Cloud), como combinado no #1865.
# A lida vem antes da resposta, como no app (leu, depois responde). Custa uma chamada à Meta (até TIMEOUT de
# ConversaCanal::LeituraNoCanal quando a Meta não responde) e só na primeira resposta depois de cada mensagem recebida;
# falha vira log e a resposta segue. Se a resposta falhar depois, os tiques azuis ficam: quem respondeu leu.
module ConversaCanal::LeituraAoResponder
  # Resposta ao cliente: sai para ele e não é nota, modelo aprovado nem campanha (que não responde a nada).
  def self.resposta?(message)
    attrs = message.additional_attributes.to_h
    message.outgoing? && !message.private? && attrs['template_params'].blank? &&
      attrs['campaign_id'].blank? && attrs['whatsapp_api_campaign_id'].blank?
  end

  def self.marcar(message, waha_client: nil)
    return unless Waha::AgendaDoContato.enabled?(message.account) && resposta?(message)

    ConversaCanal::LeituraNoCanal.new(conversation: message.conversation, waha_client: waha_client).perform
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][leitura] ao responder falhou message=#{message.id} #{e.class}")
  end

  def perform(message_id)
    marcar_lida_antes(message_id)
    super
  end

  private

  def marcar_lida_antes(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil? || !message.inbox.channel.is_a?(Channel::Whatsapp)

    ConversaCanal::LeituraAoResponder.marcar(message)
  end
end
