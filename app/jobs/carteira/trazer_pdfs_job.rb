# Grava o lote de "Trazer por PDFs" (E6.3, #2899). Recebe só o id da leitura; o que fazer está em
# Carteira::Trazer::Pdfs::Gravar. Sem nova tentativa automática: a gravação continua de onde parou quando a pessoa pede
# de novo (Carteira::Trazer::Pdfs::Trazer).
class Carteira::TrazerPdfsJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(leitura_id)
    leitura = Carteira::Leitura.do_trazer.find_by(id: leitura_id)
    Carteira::Trazer::Pdfs::Gravar.new(leitura).call if leitura
  end
end
