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
    render json: @revisao.para_tela(visiveis: visiveis)
  end

  def continuar
    return render json: { error: erro_ao_continuar }, status: :unprocessable_entity unless @revisao.continuar!

    ::Autonomia::Guide::RevisaoJob.perform_later(@revisao.id)
    render json: @revisao.para_tela(visiveis: visiveis)
  end

  private

  # A permissão é conferida de novo na hora de mostrar: a conversa que a dona deixou de ver depois da leitura sai do
  # cartão, com o motivo e o link.
  def visiveis
    ids = @revisao.resultados.pluck('conversa_id')
    return Set.new if ids.empty?

    Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account, for_reading: true)
                                          .perform.where(id: ids).pluck(:id).to_set
  end

  def erro_ao_continuar
    outra = ::Autonomia::Guide::Revisao.de(Current.account, Current.user).andando.where.not(id: @revisao.id).exists?
    outra ? 'outra_andando' : 'nada_a_continuar'
  end

  def carregar_revisao
    @revisao = ::Autonomia::Guide::Revisao.de(Current.account, Current.user).find_by(id: params[:id])
    head :not_found if @revisao.nil?
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
