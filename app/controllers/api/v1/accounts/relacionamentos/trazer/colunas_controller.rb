# "Trazer minha lista" (#2896): a pessoa troca, na conferência, para onde vai uma coluna da planilha. Nesta fatia: os
# quatro alvos (nome, telefone, email, empresa), que fazem a planilha ser lida de novo, e "informacao" e "nao_guardar".
class Api::V1::Accounts::Relacionamentos::Trazer::ColunasController < Api::V1::Accounts::Relacionamentos::Trazer::BaseController
  # PATCH leituras/:leitura_id/colunas/:indice  { destino: }
  def update
    importacao = leituras.find(params[:leitura_id])
    troca = ::Relacionamentos::Trazer::TrocarDestino.new(importacao, indice: params[:indice], destino: params.permit(:destino)[:destino]).call
    return recusar_com(troca.erro) if troca.erro
    return render json: { id: importacao.id, situacao: 'pronta', colunas: colunas_de(importacao) } unless troca.revalida

    ::CampaignImports::ValidateJob.perform_later(importacao)
    render json: { id: importacao.id, situacao: 'lendo' }
  end

  private

  def colunas_de(importacao)
    ::Relacionamentos::Trazer::Colunas.new(importacao).call
  end
end
