# Move uma conversa de e-mail entre Entrada, Spam e Lixeira do painel (#1809, fase 1). Nada muda na conta de e-mail.
# - spam: sai da Entrada, fica resolvida e o remetente fica no Spam só desta caixa (ConversaCanal::RemetenteNoSpam;
#   decisão do Rodrigo, 18/10: "só a caixa de email"). E-mail novo dele nesta caixa cai direto no Spam
#   (ConversaCanal::SpamDoBloqueado). O contato (contacts.blocked) e os outros canais dele não mudam;
# - lixeira: sai da Entrada e fica resolvida, sem apagar; dá para restaurar;
# - entrada (pasta nil): volta e é reaberta. Saindo do Spam, o remetente volta a chegar nesta caixa ("Não é spam").
# Resolver e reabrir usam o status da conversa, como o botão Resolver: os eventos e a atividade são os de sempre.
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
      anterior = ConversaCanal::PastaDoEmail.find_by(conversation_id: @conversation.id)&.pasta
      @pasta ? mover : restaurar
      ajustar_remetente(anterior)
      ajustar_status
    end
    @pasta
  end

  private

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

  def ajustar_remetente(anterior)
    email = ConversaCanal::RemetenteNoSpam.normalizar(@conversation.contact&.email)
    return if email.blank?

    if @pasta == 'spam'
      ConversaCanal::RemetenteNoSpam.upsert( # rubocop:disable Rails/SkipsModelValidations -- endereço normalizado acima
        { account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, email: email, user_id: @user&.id },
        unique_by: %i[inbox_id email], update_only: %i[user_id]
      )
    elsif anterior == 'spam'
      ConversaCanal::RemetenteNoSpam.where(inbox_id: @conversation.inbox_id, email: email).delete_all
    end
  end

  def ajustar_status
    if @pasta
      @conversation.update!(status: :resolved) unless @conversation.resolved?
    elsif @conversation.resolved?
      @conversation.update!(status: :open)
    end
  end
end
