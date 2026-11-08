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
  # Quem resolve é o Spam da caixa (#2616): a atividade diz por que a conversa foi para lá, e não "por inatividade".
  # Uma linha por ida ao Spam: conversa nova, conversa que estava em outra pasta ou na Entrada (aberta ou já resolvida),
  # ou reaberta no Spam. Roda no after_create_commit da conversa ou da mensagem, fora de transação.
  def self.mandar_para_o_spam(conversa)
    no_spam = ConversaCanal::PastaDoEmail.exists?(conversation_id: conversa.id, pasta: 'spam')
    ConversaCanal::PastaDoEmail.upsert( # rubocop:disable Rails/SkipsModelValidations -- pasta fixa, conferida no modelo
      { account_id: conversa.account_id, conversation_id: conversa.id, pasta: 'spam' },
      unique_by: :conversation_id, update_only: %i[pasta]
    )
    return if no_spam && conversa.resolved?

    ConversaCanal::AtividadeDaPasta.com_autor(ConversaCanal::PastaDoEmail.find_by!(conversation_id: conversa.id)) do
      conversa.transaction do
        conversa.update!(status: :resolved) unless conversa.resolved?
        ConversaCanal::AtividadeDaPasta.registrar!(conversa, 'spam_do_remetente')
      end
    end
  end

  private

  def conversa_canal_spam_do_bloqueado
    return unless inbox&.email? && account.feature_enabled?('conversa_email_nova')
    return unless ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: inbox_id, email: contact&.email)

    ConversaCanal::SpamDoBloqueado.mandar_para_o_spam(self)
  end
end
