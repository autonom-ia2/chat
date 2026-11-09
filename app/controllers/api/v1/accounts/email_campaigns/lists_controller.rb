# Listas de e-mail da conta (G52, #2760): o público "lista X" da campanha de e-mail e do passo "Pôr na lista de e-mail"
# da Automação livre. Cada lista diz quantas pessoas estão nela agora e quantas receberiam (com e-mail, sem ter pedido
# para não receber).
#
# Apagar a lista não apaga a etiqueta (quem estava continua com ela) e é recusado enquanto uma campanha agendada, em
# envio ou pausada usa a lista (EmailList::CAMPANHAS_EM_USO): ela ficaria sem lista no meio do caminho.
class Api::V1::Accounts::EmailCampaigns::ListsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_list, only: [:update, :destroy]

  def index
    authorize EmailList
    listas = list_scope.includes(:label).order(:name).to_a
    contagens = ve_contatos? ? EmailList.contagens(Current.account, listas) : {}
    render json: listas.map { |lista| list_json(lista, contagens[lista.id]) }
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

  # A conferência e a exclusão rodam sob a trava de envio de cada campanha da lista (EmailList#sem_campanha_em_uso).
  def destroy
    return head :no_content if @list.sem_campanha_em_uso { @list.destroy! }

    render json: { error: 'email_list.in_use' }, status: :unprocessable_entity
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

  # Os números da lista só para quem vê os contatos (a mesma regra do Autonomia::Automacao::Tempo::Selecao): sem isso,
  # quem só vê campanhas contaria quantos contatos têm uma etiqueta. Sem acesso, nil, e a tela não mostra o número.
  def ve_contatos?
    return @ve_contatos if defined?(@ve_contatos)

    @ve_contatos = ContactPolicy.new(pundit_user, Contact).index?
  end

  def list_json(lista, contagem = (EmailList.contagens(Current.account, [lista])[lista.id] if ve_contatos?))
    { id: lista.id, name: lista.name, label_id: lista.label_id,
      contatos_count: contagem&.dig(:contatos), recebem_count: contagem&.dig(:recebem) }
  end

  def render_invalid(lista)
    render json: { error: 'email_list.invalid', errors: lista.errors.details.transform_values { |erros| erros.pluck(:error) } },
           status: :unprocessable_entity
  end
end
