# Varredura de pré-aquecimento da imagem de prévia do link (#1303): passa pelas páginas novas que estão no ar, em
# lotes, e desenha as imagens que faltam ou ficaram velhas. Enfileirada uma vez por versão do desenho
# (`PreviewImage::Warmup.sweep_once`), quando `Content::RENDER_VERSION` sobe.
#
# Desenha uma página de cada vez (ocupa no máximo uma vaga do teto global) e continua de onde parou em outro job,
# para nenhum job ficar longo. Página que achou o teto cheio vai para o job dela, que tenta de novo sozinho: a
# varredura não para por causa disso. Rodar de novo é inofensivo: imagem já guardada na versão atual é pulada.
class Crm::BookingV2::PreviewImageSweepJob < ApplicationJob
  BATCH = 20

  queue_as :low

  def perform(after_id = 0)
    profiles = ::Crm::AgentBookingProfile.new_pages.where(enabled: true).where('id > ?', after_id).order(:id).limit(BATCH).to_a
    profiles.each { |profile| warm(profile) }
    self.class.perform_later(profiles.last.id) if profiles.size == BATCH
  end

  private

  def warm(profile)
    results = ::Crm::BookingV2::PreviewImage::Warmup.page(profile)
    ::Crm::BookingV2::PreviewImage::Warmup.later_once(profile) if results.include?(:draw_limit)
  end
end
