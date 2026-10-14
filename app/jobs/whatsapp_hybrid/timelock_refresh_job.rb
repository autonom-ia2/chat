# Atualiza o retrato do limite de conversas novas depois de um erro 463 do motor (chat#1486).
# Fora do envio: a consulta ao motor (timeout curto) não segura a fila :high do SendReplyJob.
# Falha na consulta só registra a tentativa, sem mexer no último retrato.
class WhatsappHybrid::TimelockRefreshJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    connection = WhatsappHybrid::Connection.find_by(id: connection_id)
    return if connection.nil?

    refresh(connection, WhatsappHybrid::Timelock.new(connection))
  end

  private

  def refresh(connection, timelock)
    timelock.apply!(Waha::Client.new.timelock(connection.session_name))
  rescue Waha::Client::Error => e
    timelock.checked!
    Rails.logger.warn("[whatsapp_hybrid] timelock refresh after 463 failed inbox=#{connection.inbox_id}: #{e.class}")
  end
end
