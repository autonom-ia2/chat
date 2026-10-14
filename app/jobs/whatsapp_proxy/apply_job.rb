# Aplica no motor o proxy atribuído a uma sessão (#1516), agendado pela reconciliação. Recebe só o nome da sessão:
# a credencial vem de novo da API aqui dentro, para nunca passar pela fila (Redis). O motor reinicia a sessão.
# Falha do motor não é repetida aqui: a próxima rodada da reconciliação vê a credencial ainda não aplicada e reagenda.
class WhatsappProxy::ApplyJob < ApplicationJob
  queue_as :low

  def perform(session_name)
    assigner = WhatsappProxy::Assigner.new
    proxy = assigner.for(session_name)
    return if proxy.nil?

    apply(session_name, proxy)
    assigner.mark_applied!(session_name, proxy)
    Rails.logger.info("[whatsapp_proxy] session=#{session_name} agora sai por #{proxy.server}")
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_proxy] troca de proxy falhou session=#{session_name}: #{e.class}")
  end

  private

  def apply(session_name, proxy)
    connection = WhatsappHybrid::Connection.find_by(session_name: session_name)
    return WhatsappHybrid::SessionManager.new(connection).apply_proxy!(proxy) if connection

    WhatsappProxy::SessionUpdater.new.apply!(session_name, proxy)
  end
end
