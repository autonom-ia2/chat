# "Trazer minha lista" (#2896): os três arquivos da conferência, anexados à importação de contatos que nasceu na tela (a
# marca options['trazer']):
# - `linhas_com_problema`: as linhas da planilha que precisam da pessoa (ContactImports::Trazer::LinhasComProblema);
# - `consertos`: o que a pessoa consertou nelas (ContactImports::Trazer::Consertos);
# - `valores_cliente`: os valores da coluna que diz quem é cliente, contados (ContactImports::Trazer::ValoresDeCliente).
# Somem com a importação e, antes disso, no prazo da planilha original contado da criação da importação
# (ContactImports::Trazer::AnexosVencidos, chamado por CampaignImports::PurgeExpiredFilesJob).
module Relacionamentos::Trazer::ArquivoDeProblemas
  extend ActiveSupport::Concern

  ANEXO = :linhas_com_problema
  CONSERTOS = :consertos
  VALORES_CLIENTE = :valores_cliente
  ANEXOS = [ANEXO, CONSERTOS, VALORES_CLIENTE].freeze

  included do
    ANEXOS.each { |anexo| has_one_attached anexo }
  end
end
