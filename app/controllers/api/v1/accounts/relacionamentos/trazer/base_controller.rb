# Base de "Trazer minha lista" (#2896): a planilha de contatos que a pessoa envia pela tela nova de Relacionamentos.
# Toda rota, leitura inclusive, pede a chave da conta (404 sem ela), a importação de contatos por planilha ligada na
# instalação (404 sem ela) e a permissão de importar contatos de hoje (ContactPolicy#import?: administrador ou função com
# contact_manage). Aqui só entram as importações de contatos por arquivo da conta: nunca as da automação nem os Públicos.
class Api::V1::Accounts::Relacionamentos::Trazer::BaseController < Api::V1::Accounts::Relacionamentos::BaseController
  before_action :exigir_importacao_por_planilha

  private

  def conferir_permissao
    authorize(Contact, :import?)
  end

  def exigir_importacao_por_planilha
    head :not_found unless ::ContactImports::Config.enabled?
  end

  def importacoes
    Current.account.campaign_imports.contact_imports.where("COALESCE(options->>'origem', '') <> ?", CampaignImport::AUTOMATION_ORIGIN)
  end

  # A leitura é o rascunho que nasceu nesta tela (a marca options['trazer']); depois de trazida ela vira lista.
  def leituras
    importacoes.where("options -> 'trazer' IS NOT NULL").where(status: ::Relacionamentos::Trazer::Leitura::RASCUNHO)
  end

  def recusar_com(codigo)
    render json: { error: codigo }, status: :unprocessable_entity
  end
end
