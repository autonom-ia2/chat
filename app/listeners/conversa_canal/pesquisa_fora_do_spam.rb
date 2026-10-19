# Conversa de e-mail posta no Spam do painel (#1809, opção (b) do Rodrigo, 18/10) não manda a pesquisa de satisfação
# ao remetente. A Lixeira e o "Não é spam" seguem como o Resolver e o Reabrir de sempre. Entra no CsatSurveyListener
# do Chatwoot por um prepend (config/initializers/conversa_canal_email.rb).
module ConversaCanal::PesquisaForaDoSpam
  def conversation_status_changed(event)
    return if ConversaCanal::PastaDoEmail.no_spam?(event.data[:conversation])

    super
  end
end
