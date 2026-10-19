# #1865 — lida no WhatsApp do cliente na hora de responder, como quem usa o app: abriu ou respondeu, leu. Soma à lida ao
# abrir a conversa (#1702, ConversaCanal::LeituraAoAbrir), que fica igual: aqui entra quem responde sem abrir (robô do
# n8n, follow-up, automação). Nunca na chegada da mensagem do cliente.
#
# Prepend em SendReplyJob para o WhatsApp oficial e o Híbrido (a lida vai pela Cloud, ConversaCanal::LeituraNaCloud); a
# caixa WAHA comum marca no Waha::AntesDoEnvio, antes de o webhook mandar a resposta ao conector.
# Reaproveita ConversaCanal::LeituraNoCanal: a mesma flag da lida (`conversa_cara_do_canal`), o mesmo prazo e a mesma
# marca `read_receipt_sent_at` (a IA da Autonomia, que já marca junto do "digitando", não manda de novo).
# Só com a flag `whatsapp_agenda_do_contato`. Vale também para a caixa WhatsApp oficial (Cloud), como combinado no #1865.
# A lida vem antes da resposta, como no app (leu, depois responde). Custa uma chamada à Meta (até o TIMEOUT de
# ConversaCanal::LeituraNoCanal) na primeira resposta depois de cada mensagem recebida; se a Meta recusar, a lida não
# fica gravada e a resposta seguinte tenta de novo (mesma regra da lida ao abrir). Falha vira log e a resposta segue. Se
# a resposta falhar depois, os tiques azuis ficam: quem respondeu leu.
# Ordem: com trabalho a fazer (lida, ou contato a salvar na agenda do Híbrido), a resposta segura a conversa até sair
# (ConversaCanal::EnvioEmOrdem), e a seguinte da mesma conversa espera um pouco: reduz a troca de ordem, não a garante.
module ConversaCanal::LeituraAoResponder
  # Resposta ao cliente: sai para ele e não é nota, modelo aprovado nem campanha (que não responde a nada).
  def self.resposta?(message)
    attrs = message.additional_attributes.to_h
    message.outgoing? && !message.private? && attrs['template_params'].blank? &&
      attrs['campaign_id'].blank? && attrs['whatsapp_api_campaign_id'].blank?
  end

  def self.a_fazer?(message)
    Waha::AgendaDoContato.enabled?(message.account) && resposta?(message) &&
      ConversaCanal::LeituraNoCanal.new(conversation: message.conversation).pendente?
  end

  def self.marcar(message, waha_client: nil)
    return unless Waha::AgendaDoContato.enabled?(message.account) && resposta?(message)

    ConversaCanal::LeituraNoCanal.new(conversation: message.conversation, waha_client: waha_client).perform
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][leitura] ao responder falhou message=#{message.id} #{e.class}")
  end

  # Contato do Híbrido ainda por salvar na agenda, numa mensagem que vai sair pelo WhatsApp API: o salvamento em si é do
  # WhatsappHybrid::AgendaNoEnvio, que só roda nessa rota. Pela Cloud não há agenda a salvar.
  def self.agenda_do_hibrido_a_fazer?(message)
    connection = WhatsappHybrid::Connection.find_by(inbox_id: message.inbox_id)
    return false if connection.nil?

    agenda = Waha::AgendaDoContato.new(client: nil, session: connection.session_name, contact: message.conversation.contact)
    agenda.a_fazer? && WhatsappHybrid::Router.new(message.conversation).route_for(message) == :web
  end

  def self.trabalho?(message)
    a_fazer?(message) || agenda_do_hibrido_a_fazer?(message)
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][leitura] trabalho? falhou message=#{message.id} #{e.class}")
    false
  end

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return super unless message && message.inbox.channel.is_a?(Channel::Whatsapp) && Waha::AgendaDoContato.enabled?(message.account)

    ConversaCanal::EnvioEmOrdem.executar(message.conversation, -> { ConversaCanal::LeituraAoResponder.trabalho?(message) }) do
      ConversaCanal::LeituraAoResponder.marcar(message)
      super
    end
  end
end
