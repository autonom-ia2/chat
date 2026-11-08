# Por cima do ConversationFinder do Chatwoot (#1809, fase 1): com a chave `conversa_email_nova` ligada, as conversas que
# estão no Spam ou na Lixeira do painel saem das listas de sempre (Entrada, Minhas, Todas). Com `pasta=spam|lixeira`, a
# lista mostra só a pasta, em qualquer situação (aberta ou resolvida: o contato bloqueado nasce resolvido). Contadores
# seguem a mesma regra, porque o filtro entra no `set_up`. Sem a chave, nada muda.
# #1938: `pasta=enviados` (com a chave `email_enviados`) é uma vista, como no Gmail: as conversas em que nós mandamos
# mensagem ao cliente (resposta, Escrever, robô), em qualquer situação. A conversa continua na Entrada; o Spam e a
# Lixeira ficam de fora. Nada é gravado.
module ConversaCanal::ConversationFinderComPastas
  ENVIADOS = 'enviados'.freeze

  private

  def set_up
    super
    filtrar_por_pasta_do_email if pastas_do_email_ligadas?
  end

  def filter_by_status
    return if pastas_do_email_ligadas? && (pasta_pedida || enviados_pedidos?)

    super
  end

  def filtrar_por_pasta_do_email
    fora = ConversaCanal::PastaDoEmail.where(account_id: current_account.id)
    @conversations = if enviados_pedidos?
                       @conversations.where.not(id: fora.select(:conversation_id)).where(com_mensagem_nossa)
                     elsif pasta_pedida
                       @conversations.where(id: fora.where(pasta: pasta_pedida).select(:conversation_id))
                     else
                       @conversations.where.not(id: fora.select(:conversation_id))
                     end
  end

  def pasta_pedida
    ConversaCanal::PastaDoEmail::PASTAS.include?(params[:pasta]) ? params[:pasta] : nil
  end

  def enviados_pedidos?
    params[:pasta] == ENVIADOS && current_account.feature_enabled?('email_enviados')
  end

  # Mensagem nossa ao cliente: saída, pública e que não falhou (nota interna, aviso do sistema e envio com erro não contam).
  def com_mensagem_nossa
    Message.where(Message.arel_table[:conversation_id].eq(Conversation.arel_table[:id]))
           .where(message_type: :outgoing, private: false).where.not(status: :failed).arel.exists
  end

  def pastas_do_email_ligadas?
    current_account.feature_enabled?('conversa_email_nova')
  end
end
