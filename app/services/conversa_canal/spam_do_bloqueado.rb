# Conversa nova de quem foi marcado como spam vai direto para o Spam do painel (#1809, fase 1). O Chatwoot já faz a
# conversa de contato bloqueado nascer resolvida; aqui ela também sai da Entrada. Só caixa de e-mail, com a chave
# `conversa_email_nova`. Entra no Conversation por um include (config/initializers/conversa_canal_email.rb).
module ConversaCanal::SpamDoBloqueado
  extend ActiveSupport::Concern

  included do
    after_create_commit :conversa_canal_spam_do_bloqueado
  end

  private

  def conversa_canal_spam_do_bloqueado
    return unless contact&.blocked? && inbox&.email? && account.feature_enabled?('conversa_email_nova')

    ConversaCanal::PastaDoEmail.find_or_create_by!(conversation_id: id) do |pasta|
      pasta.account_id = account_id
      pasta.pasta = 'spam'
    end
  end
end
