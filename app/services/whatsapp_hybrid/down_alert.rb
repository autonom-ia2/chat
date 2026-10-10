# Avisa os administradores que o WhatsApp API de uma caixa caiu (chat#1067), pelo canal de avisos
# urgentes do Guia: conversa do Guia, sino, push e e-mail. Uma queda = um aviso (chave pelo instante).
class WhatsappHybrid::DownAlert
  def initialize(connection)
    @connection = connection
  end

  def deliver!
    Autonomia::Guide::Entrega.new(@connection.account).whatsapp_api_caiu!(@connection.inbox, @connection.down_alerted_at)
  rescue StandardError => e
    # O aviso nunca pode impedir a atualização do estado da conexão.
    Rails.logger.error("[whatsapp_hybrid] down alert failed inbox=#{@connection.inbox_id}: #{e.class}: #{e.message.to_s[0, 200]}")
  end
end
