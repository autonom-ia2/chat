# Conversa nova pelo painel numa caixa Cloud com WhatsApp Híbrido (chat#1457). Conversa nova não tem
# janela de 24h aberta: o texto livre de um atendente sai pelo WhatsApp API, sem modelo. A tela de nova
# conversa usa isto para mostrar o campo de texto ao lado do modelo.
class WhatsappHybrid::NewConversation
  HUMAN_ORIGIN = 'human'.freeze

  def initialize(inbox:, contact:)
    @inbox = inbox
    @contact = contact
  end

  def free_text_available?
    return false unless hybrid_inbox?

    connection = WhatsappHybrid::Connection.find_by(inbox_id: @inbox.id)
    connection.present? && connection.routable? && connection.origin_enabled?(HUMAN_ORIGIN) && contact_phone.present?
  end

  private

  # Conta liberada, caixa com conexão (resposta do cache) e roteador ligado: só então consulta o banco.
  def hybrid_inbox?
    @inbox.channel_type == 'Channel::Whatsapp' &&
      WhatsappHybrid::Config.account_allowed?(@inbox.account_id) &&
      WhatsappHybrid::Config.hybrid_inbox?(@inbox.id) &&
      WhatsappHybrid::Config.routing_enabled?
  end

  # Mesmo critério do roteador: só telefone de verdade vai para o WhatsApp API.
  def contact_phone
    @contact&.phone_number.to_s.delete('^0-9').presence
  end
end
