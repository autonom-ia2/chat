# O que o Guia lembra (#933), no painel "O que eu sei": ver, corrigir e apagar.
#
# Cada pessoa vê as dela e as da corretora. A de outra pessoa responde 404,
# igual a uma que não existe (como `GuideConversasController`). A da corretora
# todo mundo vê, e só administrador corrige ou apaga (403). Mesmo gate do Guia.
class Api::V1::Accounts::Autonomia::GuideMemoriasController < Api::V1::Accounts::BaseController
  MEMORIA = ::Autonomia::Guide::Memoria

  before_action :ensure_guide_enabled
  before_action :carregar_memoria, only: [:update, :destroy]
  before_action :so_administrador_na_corretora, only: [:update, :destroy]

  def index
    render json: {
      pessoais: MEMORIA.pessoais(Current.account, Current.user).em_ordem.includes(:turno).map(&:para_tela),
      corretora: MEMORIA.da_corretora(Current.account).em_ordem.includes(:autor).map(&:para_tela),
      pode_editar_corretora: administrador?,
      limites: { pessoais: MEMORIA::TETO_PESSOAL, corretora: MEMORIA::TETO_CORRETORA }
    }
  end

  def update
    if @memoria.update(texto: params[:texto].to_s.squish)
      render json: @memoria.para_tela
    else
      render json: { error: @memoria.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # Sem desfazer: a tela pede confirmação antes.
  def destroy
    @memoria.destroy!
    head :no_content
  end

  private

  def carregar_memoria
    @memoria = MEMORIA.visiveis(Current.account, Current.user).find_by(id: params[:id])
    head :not_found if @memoria.nil?
  end

  def so_administrador_na_corretora
    head :forbidden if @memoria.corretora? && !administrador?
  end

  def administrador?
    Current.account_user&.administrator? == true
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
