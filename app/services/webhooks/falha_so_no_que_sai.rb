# #1941 — Prepend em Webhooks::Trigger. Quando o webhook da caixa API falha, o Chatwoot marca a mensagem do evento como
# `failed` ("Falha ao enviar"), seja ela qual for. Mas o webhook leva ao conector também a mensagem que o cliente
# mandou, o eco do que saiu pelo celular (`external_echo`) e a nota interna, e nenhuma delas depende dele para existir:
# o cliente via "Falha ao enviar" em mensagem recebida (6.144 em conversas abertas, na queda do conector de 16/10).
# Aqui só fica `failed` o que o chat2you manda ao cliente por esse webhook e que ainda não chegou: entregue ou lida já
# está no celular do cliente, e um `message_updated` depois (recibo, edição) que falhe não desfaz isso. O resto da
# falha segue igual (log).
module Webhooks::FalhaSoNoQueSai
  private

  def update_message_status(error)
    return unless sai_pelo_webhook?(message)

    super
  end

  def sai_pelo_webhook?(message)
    (message.outgoing? || message.template?) && !message.private? && !message.delivered? && !message.read? &&
      message.content_attributes.to_h['external_echo'].blank?
  end
end
