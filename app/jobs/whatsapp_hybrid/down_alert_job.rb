# Confere, depois da carência, se a queda do WhatsApp API continua (#2112). Ver WhatsappHybrid::DownAlert.
# Consulta o motor de novo (o webhook de volta pode ter se perdido) sem regravar o proxy, que reiniciaria a sessão.
class WhatsappHybrid::DownAlertJob < ApplicationJob
  queue_as :default

  def perform(connection_id, marco)
    connection = WhatsappHybrid::Connection.find_by(id: connection_id)
    return unless connection

    alerta = WhatsappHybrid::DownAlert.new(connection)
    return unless alerta.mesma_queda?(marco)

    WhatsappHybrid::SessionManager.new(connection).refresh!(sync_proxy: false)
    return unless connection.reload.routable_when_connected? && alerta.mesma_queda?(marco)

    alerta.avisar!(marco)
  end
end
