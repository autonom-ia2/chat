# "Trazer minha lista" (#2896): os dois arquivos da conferência, anexados à importação de contatos que nasceu na tela (a
# marca options['trazer']):
# - `linhas_com_problema`: as linhas da planilha que precisam da pessoa (ContactImports::Trazer::LinhasComProblema);
# - `consertos`: o que a pessoa consertou nelas (ContactImports::Trazer::Consertos).
# Somem com a importação e, antes disso, no prazo da planilha original contado da criação da importação
# (ContactImports::Trazer::AnexosVencidos, chamado por CampaignImports::PurgeExpiredFilesJob).
module Relacionamentos::Trazer::ArquivoDeProblemas
  extend ActiveSupport::Concern

  ANEXO = :linhas_com_problema
  CONSERTOS = :consertos
  ANEXOS = [ANEXO, CONSERTOS].freeze

  included do
    ANEXOS.each { |anexo| has_one_attached anexo }
  end
end
