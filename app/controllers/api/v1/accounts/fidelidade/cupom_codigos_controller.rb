# "Marcar como usado" (#3100): o código de um cupom que chegou à pessoa, pelo Conferir da aba Cupons ou pela ficha.
#
# Quem pode (decisão D1 do Rodrigo, 23/11): quem pode mexer no contato dono do código, inclusive o atendente; não passa
# pela permissão do cartão. Com a linha travada (Fidelidade::UsarCupom): o toque repetido devolve o mesmo código, já
# usado, sem erro (`ja_estava`). Código vencido responde 422 `vencido`; código que não chegou à pessoa, 404.
class Api::V1::Accounts::Fidelidade::CupomCodigosController < Api::V1::Accounts::BaseController
  rescue_from ::Fidelidade::UsarCupom::Vencido do
    render json: { error: 'vencido' }, status: :unprocessable_entity
  end

  def usar
    codigo = ::Fidelidade::CupomCodigo.where(account_id: Current.account.id).where.not(enviado_em: nil).preload(:cupom).find(params[:id])
    authorize codigo.contact, :update?
    resultado = ::Fidelidade::UsarCupom.new(Current.user).call(codigo)
    render json: { codigo: resultado.codigo.para_a_ficha(Time.current), ja_estava: resultado.ja_estava }
  end
end
