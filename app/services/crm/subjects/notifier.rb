# Multifunil 5b (#1145): avisa em tempo real que os assuntos de uma conversa mudaram (a IA criou, deu nome ou trocou o
# assunto atual, ou deixou uma sugestão). O painel Assuntos e o selo da lista leem de novo. O aviso leva só a conta e
# o número da conversa; quem recebe são os membros da caixa e os administradores, que podem abrir a conversa.
class Crm::Subjects::Notifier
  EVENT = 'crm.subjects.changed'.freeze

  def self.notify(conversation)
    new(conversation).notify
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def notify
    payload = { account_id: @conversation.account_id, conversation_id: @conversation.display_id }
    tokens.each { |token| ActionCable.server.broadcast(token, { event: EVENT, data: payload }) }
  rescue StandardError => e
    Rails.logger.warn("[crm][assunto] aviso em tempo real falhou conversa=#{@conversation.id}: #{e.class}")
    nil
  end

  private

  def tokens
    users = @conversation.inbox.members.to_a | @conversation.account.administrators.to_a
    users.filter_map(&:pubsub_token)
  end
end
