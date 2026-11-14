# "Apólice nova" feita à mão (E5, #2898): a apólice que chegou da seguradora, guardada a partir do seguro que ela
# renovou (`anteriorId`). Pede poder editar a pessoa do seguro anterior, que é a dona do novo. Devolve o seguro novo.
# O seguro anterior que não existe, ou é de outra conta, responde 422 `anterior_desconhecida`.
class Api::V1::Accounts::Relacionamentos::Seguros::ApolicesNovasController < Api::V1::Accounts::Relacionamentos::CarteiraController
  CAMPOS = ::Carteira::Renovacao::ApoliceNova::CAMPOS

  def create
    dados = corpo(*CAMPOS)
    anterior = achar_anterior(dados['anteriorId'])
    authorize anterior.contact, :update?
    nova = ::Carteira::Renovacao::ApoliceNova.new(anterior, dados, user: Current.user).call
    render json: apresentacao.de(seguros_da_conta.find(nova.id)), status: :created
  end

  private

  def achar_anterior(id)
    seguros_da_conta.find_by(id: Integer(id.to_s, 10, exception: false)) || raise(CustomExceptions::CarteiraRecusa, 'anterior_desconhecida')
  end
end
