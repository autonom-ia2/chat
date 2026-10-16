# A enquete nativa nossa do plano B do Híbrido pelo id físico do WhatsApp (chat#1709, fase 3), na caixa: pelo `source_id`
# igual ao id físico (antes do eco) ou, nas enquetes recentes, pelo id físico que a mensagem guarda (o de dentro do
# wamid do eco, ou o `whatsapp_web_id`; WhatsappHybrid::RichNative::Quote.physical_id_of). Sem o registro do ack do
# WebTransport, que expira em 7 dias. Devolve nil quando não é enquete nossa.
module WhatsappHybrid::RichNative::PollLookup
  # Mensagens de saída recentes da caixa olhadas quando o `source_id` não confere.
  LOOKBACK = 200

  module_function

  def find(inbox_id, physical_id)
    return if physical_id.blank?

    scope = Message.where(inbox_id: inbox_id, message_type: :outgoing)
    direct = scope.find_by(source_id: physical_id)
    return direct if Waha::RichNative::PollVote.native_poll?(direct)

    scope.reorder(id: :desc).limit(LOOKBACK).find do |message|
      Waha::RichNative::PollVote.native_poll?(message) && WhatsappHybrid::RichNative::Quote.physical_id_of(message) == physical_id
    end
  end
end
