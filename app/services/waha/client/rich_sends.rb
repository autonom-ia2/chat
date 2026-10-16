# Envio nativo de mensagem rica e ações sobre mensagem já enviada pelo motor WAHA (chat#1709), incluído em Waha::Client.
# Payloads conferidos no motor 2026.9.2 GOWS. Quem monta a partir do `rich_message` é o Waha::RichPayload.
# reply_to (fase 3): o id físico da mensagem citada (só o id). nil = a chave não vai no corpo (o pedido de antes).
module Waha::Client::RichSends
  # message: { title:, description:, footer:, button:, sections: [{ title:, rows: [{ title:, rowId:, description: }] }] }
  # Sem `id`: o pedido do `sendList` não aceita id gerado antes; o id físico volta na resposta.
  def send_list(session:, chat_id:, message:, reply_to: nil)
    post('/api/sendList', with_reply_to({ session: session, chatId: chat_id, message: message }, reply_to))
  end

  # location: { latitude:, longitude:, title: } (o motor não tem endereço à parte: vai no título)
  def send_location(session:, chat_id:, id:, location:, reply_to: nil)
    body = { session: session, chatId: chat_id, id: id, **location.slice(:latitude, :longitude, :title) }
    post('/api/sendLocation', with_reply_to(body, reply_to))
  end

  # contacts: [{ fullName:, phoneNumber:, whatsappId:, organization: }] (`whatsappId` só dígitos, sem + nem @c.us)
  def send_contact_vcard(session:, chat_id:, id:, contacts:, reply_to: nil)
    post('/api/sendContactVcard', with_reply_to({ session: session, chatId: chat_id, id: id, contacts: contacts }, reply_to))
  end

  # poll: { name:, options: [títulos], multipleAnswers: } (fase 3). Aceita o id gerado antes; o voto volta pelo evento
  # `poll.vote`, com o id da enquete.
  def send_poll(session:, chat_id:, id:, poll:, reply_to: nil)
    post('/api/sendPoll', with_reply_to({ session: session, chatId: chat_id, id: id, poll: poll }, reply_to))
  end

  # Apaga "para todos" (fase 3). message_id no formato que o motor exige: "true_<chatId>_<id físico>".
  def delete_message(session:, chat_id:, message_id:)
    chat = URI.encode_www_form_component(chat_id)
    delete("/api/#{session}/chats/#{chat}/messages/#{URI.encode_www_form_component(message_id)}")
  end

  private

  def with_reply_to(body, reply_to)
    reply_to.present? ? body.merge(reply_to: reply_to) : body
  end
end
