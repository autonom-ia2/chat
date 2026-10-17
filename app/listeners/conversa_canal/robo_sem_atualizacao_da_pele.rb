# Prepend em AgentBotListener (#1702): atualização só de marca da pele não vai ao robô. Ver ConversaCanal::AtualizacaoDaPele.
module ConversaCanal::RoboSemAtualizacaoDaPele
  def message_updated(event)
    return if ConversaCanal::AtualizacaoDaPele.so_da_pele?(event.data[:previous_changes])

    super
  end
end
