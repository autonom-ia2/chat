# Imagem de prévia do link de agendamento (#1282): a que o WhatsApp mostra junto do link. Uma por página (ou por
# link de pessoa), 1200×630, sem dia nem hora (a prévia fica em cache) e sem nenhum dado de cliente.
#
# Três desenhos, escolhidos sozinhos (`Content#design`):
# - `brand` (A): cor e logo da página, nome do atendimento e a chamada.
# - `person` (B): foto de quem atende, serviço, duração e local. Só no link de uma pessoa que tem foto.
# - `light` (C): claro, com ícone de agenda. Página sem logo nem foto.
#
# `Art` é o que o desenho precisa, já resolvido (textos prontos e bytes das imagens): o `Renderer` não consulta nada.
module Crm::BookingV2::PreviewImage
  DESIGNS = %i[brand person light].freeze
  NEUTRAL_FILE = 'booking-preview.png'.freeze
  CONTENT_TYPE = 'image/png'.freeze
  MAX_BYTES = 600.kilobytes

  class TooLarge < StandardError; end

  Art = Data.define(:design, :color, :title, :call, :host_line, :facts, :logo, :photo) do
    def initialize(design:, color:, title:, call:, host_line: nil, facts: [], logo: nil, photo: nil)
      super
    end
  end

  def self.neutral_path
    Rails.public_path.join(NEUTRAL_FILE)
  end
end
