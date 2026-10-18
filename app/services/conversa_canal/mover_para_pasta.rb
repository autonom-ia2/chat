# Move uma conversa de e-mail entre Entrada, Spam e Lixeira do painel (#1809, fase 1). Nada muda na conta de e-mail.
# - spam: sai da Entrada e o contato fica bloqueado (o Chatwoot já resolve sozinho as conversas novas de quem está
#   bloqueado; ConversaCanal::SpamDoBloqueado põe essas conversas novas direto no Spam);
# - lixeira: sai da Entrada, sem apagar; dá para restaurar;
# - entrada (pasta nil): volta. Saindo do Spam, o contato é desbloqueado ("Não é spam").
class ConversaCanal::MoverParaPasta
  class Recusa < StandardError; end

  def initialize(conversation:, pasta:, user:)
    @conversation = conversation
    @pasta = pasta.presence
    @user = user
  end

  def perform
    raise Recusa, I18n.t('conversa_canal.pastas.so_email') unless @conversation.inbox&.email?
    raise Recusa, I18n.t('conversa_canal.pastas.pasta_invalida') if @pasta && ConversaCanal::PastaDoEmail::PASTAS.exclude?(@pasta)

    ActiveRecord::Base.transaction do
      anterior = atual&.pasta
      @pasta ? mover : restaurar
      ajustar_bloqueio(anterior)
    end
    @pasta
  end

  private

  def atual
    @atual ||= ConversaCanal::PastaDoEmail.find_by(conversation_id: @conversation.id)
  end

  def mover
    registro = atual || ConversaCanal::PastaDoEmail.new(account_id: @conversation.account_id, conversation: @conversation)
    registro.update!(pasta: @pasta, user: @user)
  end

  def restaurar
    atual&.destroy!
  end

  def ajustar_bloqueio(anterior)
    contato = @conversation.contact
    return if contato.blank?

    if @pasta == 'spam'
      contato.update!(blocked: true) unless contato.blocked?
    elsif anterior == 'spam' && contato.blocked?
      contato.update!(blocked: false)
    end
  end
end
