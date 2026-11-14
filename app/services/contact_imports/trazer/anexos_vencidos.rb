# "Trazer minha lista" (#2896): apaga os arquivos da conferência (as linhas com problema e os consertos) das importações
# criadas há mais tempo que o prazo da planilha original. O prazo conta da criação da IMPORTAÇÃO, não do anexo: os dois
# anexos nascem de novo a cada leitura e a cada conserto, e nem por isso podem viver mais que a planilha de onde saíram.
#
# A importação que está fechando (`confirmed`: a pessoa mandou trazer e o ContactImports::Trazer::FecharConferenciaJob
# ainda não rodou) fica de fora: o fechamento é quem lê os consertos, e a lista mandada trazer no último dia do prazo
# não pode fechar sem eles. Depois de fechada os anexos somem na passada seguinte. A importação com a marca só chega a
# `queued` pela mão do próprio fechamento, na mesma transação, então `confirmed` é o único estado "no meio".
class ContactImports::Trazer::AnexosVencidos
  NOMES = Relacionamentos::Trazer::ArquivoDeProblemas::ANEXOS.map(&:to_s).freeze
  FECHANDO = %w[confirmed].freeze

  def call
    vencidas = CampaignImport.where(created_at: ...CampaignImports::Config.original_file_retention.ago).where.not(status: FECHANDO)
    ActiveStorage::Attachment.where(record_type: 'CampaignImport', name: NOMES, record_id: vencidas.select(:id)).find_each(&:purge_later)
  end
end
