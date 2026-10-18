# Conversa nova de remetente marcado como Spam NESTA caixa de e-mail vai direto para o Spam do painel, resolvida
# (#1809; decisão do Rodrigo, 18/10: "só a caixa de email" — ConversaCanal::RemetenteNoSpam). O contato e os outros
# canais dele seguem normais. Só caixa de e-mail, com a chave `conversa_email_nova`. Entra no Conversation por um
# include (config/initializers/conversa_canal_email.rb). Roda depois do commit da conversa e antes da mensagem dela.
module ConversaCanal::SpamDoBloqueado
  extend ActiveSupport::Concern

  included do
    after_create_commit :conversa_canal_spam_do_bloqueado
  end

  # Põe a conversa no Spam do painel, resolvida. Também usada quando o remetente no Spam responde numa conversa que já
  # existia (ConversaCanal::PastaNaMensagemDoCliente). Upsert: a conversa pode estar na Lixeira.
  def self.mandar_para_o_spam(conversa)
    ConversaCanal::PastaDoEmail.upsert( # rubocop:disable Rails/SkipsModelValidations -- pasta fixa, conferida no modelo
      { account_id: conversa.account_id, conversation_id: conversa.id, pasta: 'spam' },
      unique_by: :conversation_id, update_only: %i[pasta]
    )
    conversa.update!(status: :resolved) unless conversa.resolved?
  end

  private

  def conversa_canal_spam_do_bloqueado
    return unless inbox&.email? && account.feature_enabled?('conversa_email_nova')
    return unless ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: inbox_id, email: contact&.email)

    ConversaCanal::SpamDoBloqueado.mandar_para_o_spam(self)
  end
end
