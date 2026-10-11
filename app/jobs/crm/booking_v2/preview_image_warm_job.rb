# Desenha e guarda a imagem de prévia do link de UMA página (#1303), fora do pedido web. Respeita o teto global de
# desenhos (`PreviewImage::DrawLimit`): com o teto cheio, tenta de novo mais tarde, e desiste (com registro) depois
# de `ATTEMPTS` vezes. Quem pedir a imagem nesse meio tempo ainda pode desenhá-la pelo web, dentro do mesmo teto.
class Crm::BookingV2::PreviewImageWarmJob < ApplicationJob
  ATTEMPTS = 5
  RETRY_WAIT = 30.seconds

  class DrawLimitFull < StandardError; end

  queue_as :low

  retry_on DrawLimitFull, wait: RETRY_WAIT, attempts: ATTEMPTS do |job, _error|
    Rails.logger.warn("Booking preview warmup gave up: draw limit still full for page #{job.arguments.first}")
  end

  # A marca de "já está na fila" (`Warmup.later_once`) sai antes de ler a página: o que for gravado daqui em diante
  # enfileira outro job. Só na primeira execução: na nova tentativa, a marca já pode ser de outro job enfileirado depois.
  def perform(profile_id)
    ::Redis::Alfred.delete(::Crm::BookingV2::PreviewImage::Warmup.queued_key(profile_id)) if executions == 1
    profile = ::Crm::AgentBookingProfile.find_by(id: profile_id)
    return if profile.nil?

    raise DrawLimitFull if ::Crm::BookingV2::PreviewImage::Warmup.page(profile).include?(:draw_limit)
  end
end
