# Uma regra só de "qual funil manda" numa conversa (#1606, corrida h): o card aberto do assunto em foco, relido do
# banco na hora em que se pergunta. Antes, a Entrega, o ResponsibleAgentSync e o Evaluator tinham cada um a sua (o card
# guardado na memória do job, o primeiro card aberto, o card da avaliação de 15 s atrás).
#
#   Crm::Assunto.funil_atual(conversation) -> Crm::Card | nil
#   Crm::Assunto.atual?(card, conversation) -> o card ainda é o assunto em foco desta conversa?
#
# Quem usa: Crm::Entrega (sob a trava da conversa), Crm::Ai::ResponsibleAgentSync, Crm::Ai::Evaluator (antes de passar
# a conversa), o Canceler do follow-up e o Crm::Ai::Config.robo_do_funil. A saída da triagem (Crm::Access::TriageExit)
# continua olhando todos os cards abertos de propósito: é pergunta de acesso ("esta pessoa cuida de algum assunto
# desta conversa?"), e a decisão "a" do Rodrigo (15/10) mantém com a pessoa a conversa cujo assunto mudou depois que
# ela recebeu.
module Crm::Assunto
  module_function

  def funil_atual(conversation)
    return if conversation.blank?

    card = Crm::Cards::ConversationCardFinder.new(account: conversation.account).find(conversation)
    card if card&.open?
  end

  def atual?(card, conversation)
    card.present? && funil_atual(conversation)&.id == card.id
  end
end
