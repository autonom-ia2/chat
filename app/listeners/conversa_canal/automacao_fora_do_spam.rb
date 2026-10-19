# Conversa de e-mail no Spam do painel (#1809, opção (b) do Rodrigo, 18/10) não roda as automações de conversa
# (criada, atualizada, aberta, resolvida), nem arma as com atraso. O "Não é spam" tira a pasta antes de reabrir, e as
# automações de reabertura rodam normais. Entra no AutomationRuleListener do Chatwoot por um prepend
# (config/initializers/conversa_canal_email.rb). Ele roda num job (AsyncDispatcher), depois do commit; a pasta já está
# gravada nessa hora.
module ConversaCanal::AutomacaoForaDoSpam
  private

  def process_conversation_event(event, event_name)
    return if ConversaCanal::PastaDoEmail.no_spam?(event.data[:conversation])

    super
  end
end
