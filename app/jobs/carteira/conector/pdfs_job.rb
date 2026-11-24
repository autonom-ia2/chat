# Os PDFs dos seguros que uma busca no conector trouxe (E7, #2900; Carteira::Conector::BaixarPdf), um bloco por vez e um
# pedido ao conector por vez, nunca em rajada. Recebe só o id da leitura; o `pdf_ref` e o endereço do PDF nunca entram na
# fila. O PDF que não veio não trava os outros: o seguro fica sem ele, como estava, e o registro volta depois da espera
# (#3175: Carteira::Conector::PdfsPendentes, com teto de tentativas por seguro).
class Carteira::Conector::PdfsJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false
  ESPERA = 2.seconds

  def perform(leitura_id)
    leitura = Carteira::Leitura.do_conector.find_by(id: leitura_id)
    return if leitura.nil?

    case Carteira::Conector::BaixarPdf.new(leitura).bloco
    when :continua then self.class.set(wait: ESPERA).perform_later(leitura_id)
    when :mais_tarde then self.class.set(wait: Carteira::Conector::PdfsPendentes::ESPERA).perform_later(leitura_id)
    end
  end
end
