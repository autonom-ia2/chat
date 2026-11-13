class SyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    # Crm::PassagensListener (#1606): precisa de Current.user, que só existe na thread de quem mudou.
    # Carteira::RenovacaoListener (#2898): the outcome of a renewal card is written on its policy before the request
    # that closed the card answers.
    [ActionCableListener.instance, AgentBotListener.instance, Crm::PassagensListener.instance, Carteira::RenovacaoListener.instance]
  end
end

SyncDispatcher.prepend_mod_with('SyncDispatcher')
