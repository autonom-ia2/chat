# Os seguros de uma pessoa (E4, #2897): o bloco Seguros da ficha e o painel da conversa leem daqui, já na ordem de
# urgência. Pede poder ver a pessoa, como as notas dela: função personalizada sem `contact_view` não vê os seguros do
# contato da conversa (401), e a tela não monta o bloco.
class Api::V1::Accounts::Relacionamentos::Pessoas::SegurosController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros

  def index
    pessoa = Current.account.contacts.find(params[:id])
    authorize pessoa, :show?
    render json: apresentacao.por_urgencia(seguros_da_conta.where(contact_id: pessoa.id))
  end
end
