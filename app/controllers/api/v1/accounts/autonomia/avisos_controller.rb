# Os avisos do Guia para quem está pedindo (#935): a bolinha conta os novos, e abrir o Guia marca
# como vistos.
#
# Cada pessoa vê só os dela: o aviso de outra pessoa responde 404, igual a um que não existe. Só
# administrador recebe aviso (`AvisoPolicy`).
class Api::V1::Accounts::Autonomia::AvisosController < Api::V1::Accounts::BaseController
  AVISO = ::Autonomia::Guide::Aviso
  POR_PAGINA = 50
  # O que a pessoa (ou o Guia, por ela) pode marcar. `adiado` e `resumido` são do pulso.
  ESTADOS_DA_PESSOA = [AVISO::NOVO, AVISO::VISTO].freeze

  wrap_parameters false

  before_action :ensure_guide_enabled
  before_action :autorizar

  def index
    lista = avisos.recentes.includes(:turno)
    lista = lista.where(estado: params[:estado].to_s) if params[:estado].present?
    render json: { avisos: lista.limit(POR_PAGINA).map(&:para_tela), novos: avisos.where(estado: AVISO::NOVO).count }
  end

  def update
    aviso = avisos.find_by(id: params[:id])
    return head :not_found if aviso.nil?
    return render json: { error: "estado deve ser #{ESTADOS_DA_PESSOA.join(' ou ')}" }, status: :unprocessable_entity unless estado_valido?

    aviso.update!(estado: params[:estado].to_s)
    render json: aviso.para_tela
  end

  private

  def autorizar
    authorize(AVISO, "#{action_name}?")
  end

  def avisos
    AVISO.de(Current.account, Current.user)
  end

  def estado_valido?
    ESTADOS_DA_PESSOA.include?(params[:estado].to_s)
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
