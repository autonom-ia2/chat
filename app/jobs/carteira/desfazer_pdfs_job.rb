# Desfaz um lote de "Trazer por PDFs" (E6.3, #2899). Recebe só o id da leitura; o que fazer está em
# Carteira::Trazer::Pdfs::Desfazer.
class Carteira::DesfazerPdfsJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(leitura_id)
    leitura = Carteira::Leitura.do_trazer.find_by(id: leitura_id)
    Carteira::Trazer::Pdfs::Desfazer.new(leitura).call if leitura
  end
end
