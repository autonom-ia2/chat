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

  # Upsert pela conversa: dois toques ao mesmo tempo gravam a mesma linha, sem esbarrar no índice único (era 500).
  def mover
    ConversaCanal::PastaDoEmail.upsert( # rubocop:disable Rails/SkipsModelValidations -- a pasta já foi conferida no perform
      { account_id: @conversation.account_id, conversation_id: @conversation.id, pasta: @pasta, user_id: @user&.id },
      unique_by: :conversation_id, update_only: %i[pasta user_id]
    )
  end

  def restaurar
    ConversaCanal::PastaDoEmail.where(conversation_id: @conversation.id).delete_all
  end

  # `update_attribute` grava só o bloqueio: contato antigo com algum dado fora do formato de hoje não trava o Spam.
  def ajustar_bloqueio(anterior)
    contato = @conversation.contact
    return if contato.blank?

    if @pasta == 'spam'
      contato.update_attribute(:blocked, true) unless contato.blocked? # rubocop:disable Rails/SkipsModelValidations
    elsif anterior == 'spam' && contato.blocked?
      contato.update_attribute(:blocked, false) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
