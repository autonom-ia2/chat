# Caixas WAHA que não responderam nesta rodada do cron de avisos (#1270). Uma rodada (`NoticeDispatchJob#perform`)
# cria uma e a passa a cada `Notices::Sender`: depois do primeiro erro ou timeout de uma caixa, os outros avisos dela
# nesta rodada não chamam a WAHA de novo (cada chamada esperaria o timeout) e ficam para a próxima rodada.
# Vive só na memória da rodada: a rodada seguinte tenta de novo.
class Crm::BookingV2::Notices::WahaOutage
  def initialize
    @inbox_ids = Set.new
  end

  def down?(inbox)
    @inbox_ids.include?(inbox.id)
  end

  def down!(inbox)
    @inbox_ids << inbox.id
  end
end
