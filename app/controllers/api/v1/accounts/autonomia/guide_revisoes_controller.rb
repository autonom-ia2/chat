# A revisão de conversas em lote do Guia (#3158, B8b): o cartão acompanha o andamento e, acima de 300, manda ler as
# que faltam.
#
# A revisão é de quem a pediu: de outra pessoa responde 404, igual a uma que não existe. Fica em `guide/`, fora do
# catálogo do próprio Guia (`Rotas::DO_PROPRIO_GUIA`): começar e parar são da ferramenta `revisar_conversas`.
# "Ler as que faltam" é clique da pessoa, sem confirmação (decisão do Rodrigo em 23/11: o uso é do cliente).
class Api::V1::Accounts::Autonomia::GuideRevisoesController < Api::V1::Accounts::BaseController
  before_action :ensure_guide_enabled
  before_action :carregar_revisao

  def show
    render json: @revisao.para_tela
  end

  def continuar
    return render json: { error: 'nada_a_continuar' }, status: :unprocessable_entity unless @revisao.continuar!

    ::Autonomia::Guide::RevisaoJob.perform_later(@revisao.id)
    render json: @revisao.para_tela
  end

  private

  def carregar_revisao
    @revisao = ::Autonomia::Guide::Revisao.de(Current.account, Current.user).find_by(id: params[:id])
    head :not_found if @revisao.nil?
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
