# Os resultados das renovações da conta (E5, #2898): quantos seguros venceram, quantos renovaram e por que os outros
# não, por período. Só números; pede o mesmo que ver a carteira (ver contatos) e não aceita parâmetro. O recorte por
# quem cuida só vai para quem vê os relatórios (Carteira::Renovacao::Resultados).
class Api::V1::Accounts::Relacionamentos::Seguros::ResultadosController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros

  def show
    render json: ::Carteira::Renovacao::Resultados.new(Current.account, quem: pundit_user).call
  end
end
