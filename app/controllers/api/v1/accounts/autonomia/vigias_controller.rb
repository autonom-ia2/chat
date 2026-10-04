# As vigias do Guia (#935): o "me avisa se…" de cada conta. Criar, ajustar, silenciar e apagar.
#
# Só administrador (`VigiaPolicy`), com o mesmo portão do Guia. O Guia mexe aqui pelo catálogo, como
# em qualquer tela: criar, ajustar e silenciar nascem com o desfazer de 5 dias, sem ferramenta nova.
class Api::V1::Accounts::Autonomia::VigiasController < Api::V1::Accounts::BaseController
  VIGIA = ::Autonomia::Guide::Vigia

  wrap_parameters false

  before_action :ensure_guide_enabled
  before_action :autorizar
  before_action :carregar_vigia, only: [:show, :update, :destroy]

  def index
    render json: { vigias: escopo.order(:id).map(&:para_tela), limite: VIGIA::TETO_POR_CONTA }
  end

  def show
    render json: @vigia.para_tela
  end

  def create
    vigia = escopo.new(vigia_params.merge(criado_por: Current.user))
    return render json: vigia.para_tela, status: :created if vigia.save

    render json: { error: vigia.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def update
    return render json: @vigia.para_tela if @vigia.update(vigia_params)

    render json: { error: @vigia.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    @vigia.destroy!
    head :ok
  end

  private

  def autorizar
    authorize(VIGIA, "#{action_name}?")
  end

  def escopo
    ::Autonomia::Guide::Vigia.da_conta(Current.account)
  end

  def carregar_vigia
    @vigia = ::Autonomia::Guide::Vigia.da_conta(Current.account).find_by(id: params[:id])
    head :not_found if @vigia.nil?
  end

  def vigia_params
    params.permit(:nome, :gravidade, :ativa, :silenciada_ate, leitura: {}, gatilho: {}, para_quem: [])
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
