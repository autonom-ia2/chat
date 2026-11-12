# "Trazer minha lista" (#2896): a pessoa troca, na conferência, para onde vai uma coluna da planilha: um dos quatro
# alvos (nome, telefone, email, empresa), que fazem a planilha ser lida de novo, ou cidade, telefone_da_empresa, cliente,
# informacao (com o nome e o "para que serve" do campo) e nao_guardar. A troca que vale na hora devolve a leitura
# inteira, igual à do GET (Relacionamentos::Trazer::Leitura): trocar uma coluna pode derrubar uma resposta ou apagar um
# aviso, e a tela fica sabendo sem pedir a leitura de novo.
class Api::V1::Accounts::Relacionamentos::Trazer::ColunasController < Api::V1::Accounts::Relacionamentos::Trazer::BaseController
  # PATCH leituras/:leitura_id/colunas/:indice  { destino:, nome:, para_que_serve: }
  def update
    importacao = leituras.find(params[:leitura_id])
    pedido = params.permit(:destino, :nome, :para_que_serve).to_h
    troca = ::Relacionamentos::Trazer::TrocarDestino.new(importacao, indice: params[:indice], destino: pedido['destino'], campo: pedido).call
    return recusar_com(troca.erro, troca.motivo) if troca.erro
    return render json: ::Relacionamentos::Trazer::Leitura.new(importacao).call unless troca.revalida

    ::CampaignImports::ValidateJob.perform_later(importacao)
    render json: { id: importacao.id, situacao: 'lendo' }
  end
end
