# Listas de e-mail da conta (G52, #2760): o público "lista X" da campanha de e-mail e do passo "Pôr na lista de e-mail"
# da Automação livre. Cada lista diz quantas pessoas estão nela agora e quantas receberiam (com e-mail, sem ter pedido
# para não receber).
#
# Apagar a lista não apaga a etiqueta (quem estava continua com ela) e é recusado enquanto uma campanha agendada, em
# envio ou pausada usa a lista: ela ficaria sem lista no meio do caminho.
class Api::V1::Accounts::EmailCampaigns::ListsController < Api::V1::Accounts::EmailCampaigns::BaseController
  EM_USO = %i[scheduled sending paused].freeze

  before_action :fetch_list, only: [:update, :destroy]

  def index
    authorize EmailList
    render json: list_scope.includes(:label).order(:name).map { |lista| list_json(lista) }
  end

  def create
    authorize EmailList.new(account: Current.account)
    lista = EmailList.criar(account: Current.account, name: list_params[:name])
    return render_invalid(lista) unless lista.persisted?

    render json: list_json(lista), status: :created
  end

  def update
    return render_invalid(@list) unless @list.update(name: list_params[:name])

    render json: list_json(@list)
  end

  # A conferência e a exclusão rodam sob a trava de envio de cada campanha da lista: nenhuma é agendada ou sai entre as
  # duas.
  def destroy
    em_uso = @list.com_as_campanhas_travadas do
      next true if @list.email_campaigns.exists?(status: EM_USO)

      @list.destroy!
      false
    end
    return render json: { error: 'email_list.in_use' }, status: :unprocessable_entity if em_uso

    head :no_content
  end

  private

  def list_scope
    EmailList.where(account: Current.account)
  end

  def fetch_list
    @list = list_scope.find(params[:id])
    authorize @list
  end

  def list_params
    params.require(:email_list).permit(:name)
  end

  def list_json(lista)
    { id: lista.id, name: lista.name, label_id: lista.label_id,
      contatos_count: lista.contatos.count, recebem_count: lista.elegiveis.count }
  end

  def render_invalid(lista)
    render json: { error: 'email_list.invalid', errors: lista.errors.details.transform_values { |erros| erros.pluck(:error) } },
           status: :unprocessable_entity
  end
end
