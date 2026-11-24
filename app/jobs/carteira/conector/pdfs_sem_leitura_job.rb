# Os PDFs do Agger que estão guardados e nunca foram lidos (#3175; config/schedule.yml). A leitura na chegada
# (Carteira::Conector::LerPdfJob) só existe para o PDF que a busca guarda a partir dela: o que já estava guardado antes
# ficava sem leitura, e um job de leitura que se perdesse também. Esta rotina, de todo dia, põe na fila a leitura de cada
# seguro do conector cujo PDF ainda vale ler (Carteira::Conector::LerPdf#pendente?: tem PDF, não está cancelado, falta
# algo, a leitura está liberada na conta e este PDF não foi lido).
#
# A leitura continua UMA por PDF: a marca `pdf_lido` entra antes de ler, com o seguro travado, e o PDF que deu recusa
# também fica marcado. O seguro sem nada vazio, ou numa conta sem a leitura liberada, não entra na fila. A leitura vai
# ligada à busca que anexou o PDF (o `pdf_anexado` mais recente), como a da chegada. Nos registros, só ids.
#
# O PDF já lido sai na própria consulta (sem `pdf_lido` depois do último `pdf_anexado`): a rotina não percorre a carteira
# inteira todo dia. A leitura da cotação (Carteira::Cotacao::DadosDoPdf, passo `dados_lidos_pdf`) não conta como lida
# aqui, de propósito: ela grava só nascimento, sexo e CEP, e o resto que o PDF traz (valor, o que está segurado, tipo,
# placa, bônus) ficaria vazio para sempre. Esse PDF é lido mais uma vez, e a marca `pdf_lido` fecha a conta.
class Carteira::Conector::PdfsSemLeituraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    com_pdf.find_each do |apolice|
      next unless Carteira::Conector::LerPdf.new(apolice).pendente?

      Carteira::Conector::LerPdfJob.perform_later(apolice.id, busca_do_pdf(apolice))
    end
  end

  private

  SEM_LEITURA = Arel.sql(<<~SQL.squish)
    NOT EXISTS (
      SELECT 1 FROM carteira_apolice_eventos lido
      WHERE lido.apolice_id = carteira_apolices.id AND lido.tipo = 'pdf_lido'
        AND lido.id > COALESCE((SELECT MAX(pdf.id) FROM carteira_apolice_eventos pdf
                                WHERE pdf.apolice_id = carteira_apolices.id AND pdf.tipo = 'pdf_anexado'), 0)
    )
  SQL

  def com_pdf
    Carteira::Apolice.where(origem: 'conector', cancelado_em: nil).joins(:pdf_attachment).where(SEM_LEITURA).includes(:account)
  end

  def busca_do_pdf(apolice)
    apolice.eventos.where(tipo: Carteira::Pdf::ANEXADO).order(:id).last&.valores.to_h['leitura']
  end
end
