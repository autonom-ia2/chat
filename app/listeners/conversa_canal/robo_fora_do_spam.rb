# Conversa de e-mail posta no Spam do painel (#1809, opção (b) do Rodrigo, 18/10) não chama o robô da caixa ao ser
# resolvida: sem conversation_resolved, conversation_status_changed e conversation_updated no webhook dele. O
# "Não é spam" tira a pasta antes de reabrir, e o robô recebe a reabertura normal. Entra no AgentBotListener do
# Chatwoot por um prepend (config/initializers/conversa_canal_email.rb). O AgentBotListener roda síncrono, no commit
# da conversa; a pasta já está gravada nessa hora (ConversaCanal::MoverParaPasta e SpamDoBloqueado gravam antes).
module ConversaCanal::RoboForaDoSpam
  %i[conversation_resolved conversation_status_changed conversation_updated].each do |evento|
    define_method(evento) do |event|
      return if ConversaCanal::PastaDoEmail.no_spam?(event.data[:conversation])

      super(event)
    end
  end
end
