# E-mail novo do cliente numa conversa que está numa pasta do painel (#1809):
# - na Lixeira: a conversa volta para a Entrada, como no Gmail (sem isso, o e-mail ficaria escondido, sem aviso);
# - de remetente no Spam desta caixa: a conversa vai (ou fica) no Spam, resolvida, e não é reaberta. Vale também para
#   a conversa que ainda estava na Entrada (o remetente respondeu com In-Reply-To numa conversa aberta). O Chatwoot
#   reabre a conversa resolvida quando chega mensagem; no Spam ela fica resolvida, para robô e contadores não a pegarem.
# Só caixa de e-mail, com a chave `conversa_email_nova`. Entra no Message por um prepend
# (config/initializers/conversa_canal_email.rb).
module ConversaCanal::PastaNaMensagemDoCliente
  def self.prepended(base)
    base.after_create_commit :conversa_canal_volta_da_lixeira
    base.after_create_commit :conversa_canal_spam_do_remetente
  end

  private

  def reopen_conversation
    return if conversa_canal_remetente_no_spam?

    super
  end

  def conversa_canal_volta_da_lixeira
    return unless conversa_canal_email_novo?

    ConversaCanal::PastaDoEmail.where(conversation_id: conversation_id, pasta: 'lixeira').delete_all
  end

  def conversa_canal_spam_do_remetente
    return unless conversa_canal_remetente_no_spam?
    return if ConversaCanal::PastaDoEmail.exists?(conversation_id: conversation_id, pasta: 'spam') && conversation.resolved?

    ConversaCanal::SpamDoBloqueado.mandar_para_o_spam(conversation)
  end

  def conversa_canal_remetente_no_spam?
    return @conversa_canal_remetente_no_spam if defined?(@conversa_canal_remetente_no_spam)

    @conversa_canal_remetente_no_spam = conversa_canal_email_novo? &&
                                        ConversaCanal::RemetenteNoSpam.bloqueado?(inbox_id: inbox_id, email: conversation.contact&.email)
  end

  def conversa_canal_email_novo?
    incoming? && inbox&.email? && account.feature_enabled?('conversa_email_nova')
  end
end
