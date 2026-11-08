# Converte o vídeo do topo de um modelo para o que o WhatsApp entrega e sobe (#2370, `VideoConversion`).
# Fila medium: a pessoa está esperando na tela. Uma conversão por vez: com outra rodando, volta para a fila.
class Whatsapp::Templates::VideoConversionJob < ApplicationJob
  queue_as :medium

  RETRY_WAIT = 15.seconds

  # Erro inesperado (Meta fora, ffmpeg ausente) encerra o pedido: a tela mostra o erro em vez de esperar até o fim.
  discard_on StandardError do |job, error|
    Rails.logger.error("[whatsapp_templates][video_conversion] request=#{job.arguments.first} error=#{error.class.name}")
    Whatsapp::Templates::VideoConversion.finish(job.arguments.first, 'status' => 'failed', 'error' => 'video_unreadable')
  end

  def perform(id)
    return unless Whatsapp::Templates::VideoConversion.pending?(id)
    return if Whatsapp::Templates::VideoConversion.with_lock { Whatsapp::Templates::VideoConversion.perform(id) }

    self.class.set(wait: RETRY_WAIT).perform_later(id)
  end
end
