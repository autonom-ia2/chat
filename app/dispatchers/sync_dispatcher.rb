class SyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    # Crm::PassagensListener (#1606): precisa de Current.user, que só existe na thread de quem mudou.
    [ActionCableListener.instance, AgentBotListener.instance, Crm::PassagensListener.instance]
  end
end

SyncDispatcher.prepend_mod_with('SyncDispatcher')
