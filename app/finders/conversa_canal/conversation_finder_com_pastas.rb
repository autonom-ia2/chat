# Por cima do ConversationFinder do Chatwoot (#1809, fase 1): com a chave `conversa_email_nova` ligada, as conversas que
# estão no Spam ou na Lixeira do painel saem das listas de sempre (Entrada, Minhas, Todas). Com `pasta=spam|lixeira`, a
# lista mostra só a pasta, em qualquer situação (aberta ou resolvida: o contato bloqueado nasce resolvido). Contadores
# seguem a mesma regra, porque o filtro entra no `set_up`. Sem a chave, nada muda.
module ConversaCanal::ConversationFinderComPastas
  private

  def set_up
    super
    filtrar_por_pasta_do_email if pastas_do_email_ligadas?
  end

  def filter_by_status
    return if pastas_do_email_ligadas? && pasta_pedida

    super
  end

  def filtrar_por_pasta_do_email
    fora = ConversaCanal::PastaDoEmail.where(account_id: current_account.id)
    @conversations = if pasta_pedida
                       @conversations.where(id: fora.where(pasta: pasta_pedida).select(:conversation_id))
                     else
                       @conversations.where.not(id: fora.select(:conversation_id))
                     end
  end

  def pasta_pedida
    ConversaCanal::PastaDoEmail::PASTAS.include?(params[:pasta]) ? params[:pasta] : nil
  end

  def pastas_do_email_ligadas?
    current_account.feature_enabled?('conversa_email_nova')
  end
end
