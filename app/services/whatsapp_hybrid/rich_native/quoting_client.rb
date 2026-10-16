# O cliente do motor de um envio que cita outra mensagem (chat#1709, fase 3, WhatsappHybrid::RichNative::Quote): todo
# pedido de envio leva `reply_to` com o id físico da citada. O resto passa direto ao Waha::Client.
class WhatsappHybrid::RichNative::QuotingClient < SimpleDelegator
  SENDS = %i[send_text send_list send_location send_contact_vcard send_poll].freeze

  def initialize(client, reply_to)
    super(client)
    @reply_to = reply_to
  end

  SENDS.each do |name|
    define_method(name) { |**args| __getobj__.public_send(name, **args, reply_to: @reply_to) }
  end

  def send_media(kind, media:, **args)
    __getobj__.send_media(kind, **args, media: media.merge(reply_to: @reply_to))
  end
end
