# Prepend em Message (chat#1709): o evento da tela (`push_event_data`, ActionCable) leva o `c2y_revocable`
# (Waha::RichNative::Revocable), como o JSON da API (api/v1/models/_message.json.jbuilder).
module Waha::RichNative::RevocableEventData
  def push_event_data
    super.merge(Waha::RichNative::Revocable::KEY => Waha::RichNative::Revocable.for(self))
  end
end
