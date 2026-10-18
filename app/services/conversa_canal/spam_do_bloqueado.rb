# Conversa nova de remetente marcado como Spam NESTA caixa de e-mail vai direto para o Spam do painel, resolvida
# (#1809; decisão do Rodrigo, 18/10: "só a caixa de email" — ConversaCanal::RemetenteNoSpam). O contato e os outros
# canais dele seguem normais. Só caixa de e-mail, com a chave `conversa_email_nova`. Entra no Conversation por um
# include (config/initializers/conversa_canal_email.rb). Roda depois do commit da conversa e antes da mensagem dela.
module ConversaCanal::SpamDoBloqueado
  extend ActiveSupport::Concern

  included do
    after_create_commit :conversa_canal_spam_do_bloqueado
  end

  private

  def conversa_canal_spam_do_bloqueado
    return unless inbox&.email? && account.feature_enabled?('conversa_email_nova')
    return unless ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: inbox_id, email: contact&.email)

    ConversaCanal::PastaDoEmail.find_or_create_by!(conversation_id: id) do |pasta|
      pasta.account_id = account_id
      pasta.pasta = 'spam'
    end
    update!(status: :resolved) unless resolved?
  end
end
