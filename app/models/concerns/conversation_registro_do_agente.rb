# Conversa excluída por qualquer caminho que a destrói com callbacks (#2144): o DELETE da conversa, a exclusão em lote,
# a exclusão do contato (as conversas saem num job, uma a uma) e a da caixa. O registro do agente de IA dela perde o
# texto do cliente (Autonomia::Agents::RegistroDaConversaExcluida), dentro da transação do destroy: se falhar, a conversa
# não sai.
#
# Na exclusão da conta inteira não faz nada: lá as duas tabelas saem inteiras, em lote (Autonomia::ExclusaoDaConta), e
# limpar conversa por conversa antes só gastaria tempo.
module ConversationRegistroDoAgente
  extend ActiveSupport::Concern

  included do
    after_destroy :limpar_registro_do_agente
  end

  private

  def limpar_registro_do_agente
    return if Crm::Cards::Anonimizador.conta_saindo?

    Autonomia::Agents::RegistroDaConversaExcluida.new(account_id: account_id, conversation_id: id).perform
  end
end
