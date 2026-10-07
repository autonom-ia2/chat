# Desliga e apaga a sessão WAHA de uma conexão híbrida que deixou de existir (chat#1067).
# Roda fora da transação: a conexão já foi apagada; o motor pode estar fora e isso não volta nada.
class WhatsappHybrid::TeardownSessionJob < ApplicationJob
  queue_as :low

  def perform(session_name)
    client = Waha::Client.new
    begin
      client.logout_session(session_name)
    rescue Waha::Client::Error => e
      Rails.logger.warn("[whatsapp_hybrid] teardown logout session=#{session_name}: #{e.class}")
    end
    client.delete_session(session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] teardown delete session=#{session_name}: #{e.class}")
  end
end
