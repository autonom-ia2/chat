# O porquê de uma troca de atendente (#1606), guardado durante o bloco de Crm::Passagens.com_motivo: o motivo, o card
# e, quando não é a pessoa logada, quem pediu. A conversa prende esse contexto no save que troca a pessoa
# (ConversationPassagem); o Crm::PassagensListener, que roda depois do commit, lê o que ficou preso nela. Assim o
# motivo chega mesmo quando o commit é depois do fim do bloco (a passagem do robô dentro do SyncLock da triagem).
#
# Zerado pelo Rails a cada requisição e a cada job.
class Crm::Passagens::Contexto < ActiveSupport::CurrentAttributes
  attribute :motivo, :card, :pedida_por
end
