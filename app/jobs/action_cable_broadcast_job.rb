class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  # widget_members are web widget sessions. They get widget_data, or the widget payload of a refreshed conversation.
  def perform(members, event_name, data, widget_members: [], widget_data: nil)
    return if members.blank? && widget_members.blank?

    conversation = latest_conversation(event_name, data)
    broadcast_to_people(members, event_name, conversation ? refreshed_data(conversation, data) : data)
    broadcast_to_members(widget_members, event_name, conversation ? refreshed_widget_data(conversation, data) : widget_data)
  end

  private

  def broadcast_to_people(members, event_name, broadcast_data)
    return if members.blank?

    # Anúncio de origem (#2271): quem não vê o anúncio recebe a conversa sem ele, no mesmo job e depois da busca acima.
    Crm::AnuncioDeOrigem::TempoReal.envios(broadcast_data[:account_id], members, broadcast_data).each do |destino, dados|
      broadcast_to_members(destino, event_name, dados)
    end
  end

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def latest_conversation(event_name, data)
    return unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    Account.find(data[:account_id]).conversations.find_by!(display_id: data[:id])
  end

  # Fork (upgrade 4.19.1, #3119): no `assignment` metadata on assignee.changed (refused with automatic_assignment).
  def refreshed_data(conversation, data)
    conversation.push_event_data.merge(account_id: data[:account_id])
  end

  def refreshed_widget_data(conversation, data)
    conversation.widget_push_event_data.merge(account_id: data[:account_id])
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
