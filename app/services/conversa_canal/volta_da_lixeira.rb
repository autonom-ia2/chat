# O cliente respondeu numa conversa que está na Lixeira do painel (#1809): ela volta para a Entrada, como no Gmail.
# Sem isso, o e-mail novo ficaria escondido na Lixeira, sem aviso. O Spam fica como está (quem está no Spam está
# bloqueado). Só caixa de e-mail, com a chave `conversa_email_nova`. Entra no Message por um include
# (config/initializers/conversa_canal_email.rb).
module ConversaCanal::VoltaDaLixeira
  extend ActiveSupport::Concern

  included do
    after_create_commit :conversa_canal_volta_da_lixeira
  end

  private

  def conversa_canal_volta_da_lixeira
    return unless incoming? && inbox&.email? && account.feature_enabled?('conversa_email_nova')

    ConversaCanal::PastaDoEmail.where(conversation_id: conversation_id, pasta: 'lixeira').delete_all
  end
end
