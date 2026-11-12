# "Trazer minha lista" (#2896): a pessoa mexe numa linha com problema na conferência. Conserta (o valor novo, ou com
# qual das duas linhas repetidas fica), deixa de fora ou volta atrás. Responde a linha como a tela a mostra agora
# (`problema`), quantas pessoas entram se ela mandar trazer agora (`entram`) e quantas delas como cliente (`clientes`).
class Api::V1::Accounts::Relacionamentos::Trazer::LinhasController < Api::V1::Accounts::Relacionamentos::Trazer::BaseController
  # PATCH leituras/:leitura_id/linhas/:linha  { valor: } ou { ficar_com: }
  def update
    pedido = params.permit(:valor, :ficar_com)
    responder(mudanca.consertar(valor: pedido[:valor], ficar_com: pedido[:ficar_com]))
  end

  # POST leituras/:leitura_id/linhas/:linha/deixar_de_fora
  def deixar_de_fora
    responder(mudanca.deixar_de_fora)
  end

  # POST leituras/:leitura_id/linhas/:linha/reabrir
  def reabrir
    responder(mudanca.reabrir)
  end

  private

  def mudanca
    ::Relacionamentos::Trazer::MudarLinha.new(marcadas.find(params[:leitura_id]), params[:linha])
  end

  def responder(resultado)
    return render json: resultado.to_h.slice(:problema, :entram, :clientes) unless resultado.erro

    recusar_com(resultado.erro, resultado.motivo)
  end
end
