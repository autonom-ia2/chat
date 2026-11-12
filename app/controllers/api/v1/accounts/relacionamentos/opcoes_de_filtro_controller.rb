# O que a gaveta "Mais filtros" da Lista nova de Relacionamentos oferece (#2894).
class Api::V1::Accounts::Relacionamentos::OpcoesDeFiltroController < Api::V1::Accounts::Relacionamentos::BaseController
  def show
    render json: ::Relacionamentos::OpcoesDeFiltro.new(Current.account).call
  end
end
