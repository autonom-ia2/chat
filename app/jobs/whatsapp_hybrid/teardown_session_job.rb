# Desliga e apaga a sessão WAHA de uma conexão híbrida que deixou de existir (chat#1067).
# Roda fora da transação: a conexão já foi apagada. Se o motor estiver fora, tenta de novo (até 5 vezes,
# com espera crescente) para a sessão não ficar órfã com o aparelho ainda conectado ao celular.
# Sessão que o motor já não conhece (404) é sucesso: não há o que apagar.
# Sessão parada (WhatsApp API pausado, #1487) é religada antes: logout numa sessão parada pode não tirar o aparelho do
# celular. Se ela não ficar pronta a tempo, segue com logout e exclusão assim mesmo.
class WhatsappHybrid::TeardownSessionJob < ApplicationJob
  # A sessão parada foi religada e ainda está subindo.
  class Waking < StandardError; end

  WAKE_WAIT = 10.seconds
  WAKE_ATTEMPTS = 6

  queue_as :low
  retry_on Waha::Client::Error, wait: :polynomially_longer, attempts: 5
  retry_on Waking, wait: WAKE_WAIT, attempts: WAKE_ATTEMPTS do |job, _error|
    job.class.perform_later(job.arguments.first, wake: false)
  end

  def perform(session_name, wake: true)
    client = Waha::Client.new
    wake_up!(client, session_name) if wake
    logout(client, session_name)
    client.delete_session(session_name)
    release_proxy(session_name)
  rescue Waha::Client::NotFound
    Rails.logger.info("[whatsapp_hybrid] teardown session=#{session_name}: já não existia no motor")
    release_proxy(session_name)
  end

  private

  def wake_up!(client, session_name)
    case client.get_session(session_name)&.dig('status')
    when 'STOPPED'
      client.start_session(session_name)
      raise Waking
    when 'STARTING'
      raise Waking
    end
  end

  # Sessão apagada: o IP da Webshare volta para o pool (#1516).
  def release_proxy(session_name)
    WhatsappProxy::Assigner.new.release!(session_name)
  end

  # Logout falhando não impede a exclusão (que também desconecta o aparelho).
  def logout(client, session_name)
    client.logout_session(session_name)
  rescue Waha::Client::Error => e
    Rails.logger.warn("[whatsapp_hybrid] teardown logout session=#{session_name}: #{e.class}")
  end
end
