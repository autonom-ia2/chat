# A leitura do PDF que a busca no conector guardou num seguro (#3175; Carteira::Conector::LerPdf). Recebe só ids: o PDF,
# o documento e o nome do segurado nunca entram na fila. Quem põe na fila é o download do PDF
# (Carteira::Conector::BaixarPdf), logo depois de guardar; nunca uma migration (o job de classe nova enfileirado numa
# migration cai no worker antigo durante a troca do deploy).
#
# A nova tentativa do Sidekiq não paga outra leitura: a marca da leitura entra antes de ler (Carteira::Conector::LerPdf).
class Carteira::Conector::LerPdfJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 3

  def perform(apolice_id, leitura_id = nil)
    apolice = Carteira::Apolice.find_by(id: apolice_id)
    return if apolice.nil?

    leitura = Carteira::Leitura.do_conector.find_by(id: leitura_id, account_id: apolice.account_id) if leitura_id
    Carteira::Conector::LerPdf.new(apolice, leitura: leitura).call
  end
end
