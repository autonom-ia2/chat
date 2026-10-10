# Desliga e apaga a sessão WAHA de uma conexão híbrida que deixou de existir (chat#1067).
# Roda fora da transação: a conexão já foi apagada. Se o motor estiver fora, tenta de novo (até 5 vezes,
# com espera crescente) para a sessão não ficar órfã com o aparelho ainda conectado ao celular.
# Sessão que o motor já não conhece (404) é sucesso: não há o que apagar.
class WhatsappHybrid::TeardownSessionJob < ApplicationJob
  queue_as :low
  retry_on Waha::Client::Error, wait: :polynomially_longer, attempts: 5

  def perform(session_name)
    client = Waha::Client.new
    logout(client, session_name)
    client.delete_session(session_name)
  rescue Waha::Client::NotFound
    Rails.logger.info("[whatsapp_hybrid] teardown session=#{session_name}: já não existia no motor")
  end

  private

  # Logout falhando não impede a exclusão (que também desconecta o aparelho).
  def logout(client, session_name)
    client.logout_session(session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] teardown logout session=#{session_name}: #{e.class}")
  end
end
