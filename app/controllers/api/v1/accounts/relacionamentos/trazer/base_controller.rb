# Base de "Trazer minha lista" (#2896): a planilha de contatos que a pessoa envia pela tela nova de Relacionamentos.
# Toda rota, leitura inclusive, pede a chave da conta (404 sem ela), a importação de contatos por planilha ligada na
# instalação (404 sem ela) e a permissão de importar contatos de hoje (ContactPolicy#import?: administrador ou função com
# contact_manage). Aqui só entram as importações de contatos por arquivo da conta: nunca as da automação nem os Públicos.
#
# Os arquivos da conferência são enviados ao armazenamento depois que a transação da leitura termina. Nesse intervalo o
# anexo já existe no banco e o arquivo ainda não: quem lê recebe "lendo" (a tela pergunta de novo, como já faz) e quem
# escreve é recusado com `leitura_nao_pronta`. Isso só vale enquanto o anexo mais novo da importação é recente
# (CHEGADA): se o envio falhou ou o processo morreu ali, o arquivo não vem mais, a leitura responde "falhou" (a tela
# manda enviar a planilha de novo) e a escrita segue recusada.
class Api::V1::Accounts::Relacionamentos::Trazer::BaseController < Api::V1::Accounts::Relacionamentos::BaseController
  # Quanto tempo o arquivo de um anexo novo tem para chegar ao armazenamento.
  CHEGADA = 2.minutes

  before_action :exigir_importacao_por_planilha
  rescue_from ActiveStorage::FileNotFoundError, with: :arquivo_fora_do_armazenamento

  private

  def arquivo_fora_do_armazenamento
    return recusar_com('leitura_nao_pronta') unless request.get?

    id = (params[:leitura_id] || params[:id]).to_i
    return render json: { id: id, situacao: 'lendo' } if anexo_recente?(id)

    render json: { id: id, situacao: 'falhou', erro: ::Relacionamentos::Trazer::Leitura::OUTRO_ERRO }
  end

  # O `rescue_from` roda por fora dos `around_action`, quando `Current` já foi limpo: a conta vem de `current_account`.
  def anexo_recente?(id)
    da_conta = current_account.campaign_imports.where(id: id)
    ActiveStorage::Attachment.joins(:blob).where(record_type: 'CampaignImport', record_id: da_conta.select(:id))
                             .exists?(active_storage_blobs: { created_at: CHEGADA.ago.. })
  end

  def conferir_permissao
    authorize(Contact, :import?)
  end

  def exigir_importacao_por_planilha
    head :not_found unless ::ContactImports::Config.enabled?
  end

  def importacoes
    Current.account.campaign_imports.contact_imports.where("COALESCE(options->>'origem', '') <> ?", CampaignImport::AUTOMATION_ORIGIN)
  end

  # As importações que nasceram nesta tela (a marca options['trazer']), em qualquer estado.
  def marcadas
    importacoes.where("options -> 'trazer' IS NOT NULL")
  end

  # A leitura é o rascunho que nasceu nesta tela; depois de trazida ela vira lista.
  def leituras
    marcadas.where(status: ::Relacionamentos::Trazer::Leitura::RASCUNHO)
  end

  def recusar_com(codigo, motivo = nil)
    render json: { error: codigo, motivo: motivo }.compact, status: :unprocessable_entity
  end
end
