# As conversas com o Guia (#861): a tela reabre a atual, lista as anteriores e
# apaga a que a pessoa pedir.
#
# Cada pessoa vê só as próprias. As respostas saíram com a permissão de quem
# perguntou; conversa de outra pessoa responde 404, igual a uma que não existe.
# Mesmo gate do Guia: conta sem o Guia não tem conversa nenhuma.
class Api::V1::Accounts::Autonomia::GuideConversasController < Api::V1::Accounts::BaseController
  POR_PAGINA = 20

  before_action :ensure_guide_enabled
  before_action :carregar_conversa, only: [:show, :destroy]

  def index
    pagina = [params[:page].to_i, 1].max
    lista = conversas.recentes.offset((pagina - 1) * POR_PAGINA).limit(POR_PAGINA).to_a
    contagem = ::Autonomia::Guide::Turno.where(conversation_id: lista.map(&:id)).group(:conversation_id).count
    render json: { conversas: lista.map { |conversa| conversa.resumo.merge('turnos' => contagem.fetch(conversa.id, 0)) } }
  end

  # A conversa mais recente, para a tela reabrir ao abrir o painel. Sem
  # nenhuma, `{}`: a tela mostra as sugestões de começo.
  def atual
    conversa = conversas.recentes.first
    render json: conversa ? conversa.para_tela : {}
  end

  def show
    render json: @conversa.para_tela
  end

  # Sem desfazer: a tela pede confirmação antes. Os turnos saem junto.
  def destroy
    @conversa.destroy!
    head :no_content
  end

  private

  def conversas
    ::Autonomia::Guide::Conversa.de(Current.account, Current.user)
  end

  def carregar_conversa
    @conversa = conversas.find_by(id: params[:id])
    head :not_found if @conversa.nil?
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
