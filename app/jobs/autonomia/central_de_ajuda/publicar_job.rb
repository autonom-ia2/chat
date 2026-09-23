class Autonomia::CentralDeAjuda::PublicarJob < ApplicationJob
  queue_as :low

  # Conflito é configuração (portal "plataforma" em outra conta, conta sem administrador): repetir não
  # resolve. Registra uma vez, com o motivo, e não tenta de novo.
  discard_on Autonomia::CentralDeAjuda::Publicador::Conflito do |_job, erro|
    Rails.logger.error("[central_de_ajuda][publicar_job] conflito: #{erro.message}")
  end

  def perform
    resultado = ::Autonomia::CentralDeAjuda::Publicador.new.publicar!
    return Rails.logger.info('[central_de_ajuda][publicar_job] outra publicação em curso') if resultado.nil?

    log = resultado.ok? ? :info : :warn
    Rails.logger.public_send(log, "[central_de_ajuda][publicar_job] #{resultado}")
  end
end
