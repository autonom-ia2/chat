# Avisa os administradores que o WhatsApp API de uma caixa caiu (chat#1067), pelo canal de avisos
# urgentes do Guia: conversa do Guia, sino, push e e-mail. Uma queda = um aviso (chave pelo instante).
#
# Carência (#2112): o WhatsApp fecha o websocket de tempos em tempos e o motor reconecta em 1 a 3 s. Por isso a
# queda não avisa na hora: `agendar!` guarda o instante da queda no Redis e agenda a conferência para depois da
# CARENCIA (WhatsappHybrid::DownAlertJob). Se a caixa voltar antes, `voltou!` apaga o instante e a conferência
# desiste; se cair de novo, o instante novo substitui o antigo e só a conferência da queda nova vale.
# Sem Redis para agendar, avisa na hora, como antes da carência: queda de verdade nunca fica sem aviso.
class WhatsappHybrid::DownAlert
  CARENCIA = 5.minutes

  def self.chave_da_queda(connection)
    "whatsapp_hybrid:queda:#{connection.id}"
  end

  def initialize(connection)
    @connection = connection
  end

  # Só é chamado na passagem de conectado para fora: cada chamada é uma queda nova.
  def agendar!
    marco = Time.current.to_i
    ::Redis::Alfred.setex(self.class.chave_da_queda(@connection), marco, 1.day.to_i)
    WhatsappHybrid::DownAlertJob.set(wait: CARENCIA).perform_later(@connection.id, marco)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] down alert schedule failed inbox=#{@connection.inbox_id}: #{e.class}; avisando já")
    avisar!(marco)
  end

  def voltou!
    ::Redis::Alfred.delete(self.class.chave_da_queda(@connection))
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] down alert clear failed inbox=#{@connection.inbox_id}: #{e.class}")
  end

  # A conferência ainda é desta queda (a caixa não voltou nem caiu de novo depois).
  def mesma_queda?(marco)
    ::Redis::Alfred.get(self.class.chave_da_queda(@connection)).to_i == marco.to_i
  end

  # Marca a queda e avisa, só se ninguém marcou antes e a caixa continua fora (um webhook de volta pode ter chegado
  # entre a conferência e aqui).
  def avisar!(marco)
    # rubocop:disable Rails/SkipsModelValidations -- UPDATE condicional: a marca e a conferência são um passo só no banco
    marcou = WhatsappHybrid::Connection.where(id: @connection.id, down_alerted_at: nil).where.not(status: 'connected')
                                       .update_all(down_alerted_at: Time.zone.at(marco), updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    return unless marcou == 1

    @connection.reload
    deliver!
  end

  def deliver!
    Autonomia::Guide::Entrega.new(@connection.account).whatsapp_api_caiu!(@connection.inbox, @connection.down_alerted_at)
  rescue StandardError => e
    # O aviso nunca pode impedir a atualização do estado da conexão.
    Rails.logger.error("[whatsapp_hybrid] down alert failed inbox=#{@connection.inbox_id}: #{e.class}: #{e.message.to_s[0, 200]}")
  end
end
