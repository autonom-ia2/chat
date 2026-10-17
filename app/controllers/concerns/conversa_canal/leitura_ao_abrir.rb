# #1702 — Prepend em Api::V1::Accounts::ConversationsController. update_last_seen segue igual; quando o painel avisa que o
# atendente abriu a conversa (read_receipt verdadeiro), a última mensagem recebida do cliente é marcada como lida no
# WhatsApp dele (ConversaCanal::LeituraNoCanal), por job.
# - Só atendente (User). Robô (AgentBot) não marca: a IA da Autonomia já marca a dela junto do "digitando".
# - O painel só manda read_receipt da conversa aberta na tela (MessagesView), e não manda quando o superadmin está
#   entrando como o usuário: o servidor não distingue essa sessão. "Marcar como lida" do menu da lista não manda.
# Nada daqui muda a resposta: qualquer falha depois do super vira log.
module ConversaCanal::LeituraAoAbrir
  def update_last_seen
    super
    agendar_leitura_no_canal
  end

  private

  def agendar_leitura_no_canal
    return unless leitura_no_canal_pedida?

    ConversaCanal::LeituraNoCanalJob.agendar(@conversation)
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][leitura] enqueue failed conversation=#{@conversation.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
  end

  def leitura_no_canal_pedida?
    ActiveModel::Type::Boolean.new.cast(params[:read_receipt]) &&
      Current.user.is_a?(User) &&
      ConversaCanal::LeituraNoCanal.new(conversation: @conversation).pendente?
  end
end
