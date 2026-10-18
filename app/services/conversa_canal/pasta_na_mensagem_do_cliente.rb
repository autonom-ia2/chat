# E-mail novo do cliente numa conversa que está numa pasta do painel (#1809):
# - na Lixeira: a conversa volta para a Entrada, como no Gmail (sem isso, o e-mail ficaria escondido, sem aviso);
# - no Spam, de remetente que continua no Spam desta caixa: a conversa não é reaberta (o Chatwoot reabre a conversa
#   resolvida quando chega mensagem; no Spam ela fica resolvida, para robô e contadores não a pegarem).
# Só caixa de e-mail, com a chave `conversa_email_nova`. Entra no Message por um prepend
# (config/initializers/conversa_canal_email.rb).
module ConversaCanal::PastaNaMensagemDoCliente
  def self.prepended(base)
    base.after_create_commit :conversa_canal_volta_da_lixeira
  end

  private

  def reopen_conversation
    return if conversa_canal_fica_no_spam?

    super
  end

  def conversa_canal_volta_da_lixeira
    return unless conversa_canal_email_novo?

    ConversaCanal::PastaDoEmail.where(conversation_id: conversation_id, pasta: 'lixeira').delete_all
  end

  def conversa_canal_fica_no_spam?
    conversa_canal_email_novo? &&
      ConversaCanal::PastaDoEmail.exists?(conversation_id: conversation_id, pasta: 'spam') &&
      ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: inbox_id, email: conversation.contact&.email)
  end

  def conversa_canal_email_novo?
    incoming? && inbox&.email? && account.feature_enabled?('conversa_email_nova')
  end
end
