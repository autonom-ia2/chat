# As pendências do Guia (#943): o que ele fez para esta pessoa, nos 5 dias do desfazer, e deixou uma
# parte sem volta (`Execucao#pendencias`, as tabelas escritas sem o "antes" guardado).
#
# É uma leitura comum da conta, fora de `autonomia/guide/` de propósito: entra no catálogo do Guia e a
# vigia padrão "pendências do Guia" mede a contagem. Só leitura (D3 tirou `guide/*` do catálogo para
# o Guia não apagar a própria conversa; aqui não há escrita nenhuma).
#
# Cada pessoa vê só as dela, e só administrador (`ExecucaoPolicy`). Nada de texto da conversa: o
# nome da ação e as tabelas.
class Api::V1::Accounts::Autonomia::PendenciasDoGuiaController < Api::V1::Accounts::BaseController
  EXECUCAO = ::Autonomia::Guide::Execucao
  LIMITE = 50

  before_action :ensure_guide_enabled
  before_action { authorize(EXECUCAO, :index?) }

  # `horas`: só as das últimas tantas horas (a vigia mede um dia, para não avisar a mesma pendência
  # todo dia enquanto o desfazer vale).
  def index
    lista = EXECUCAO.de(Current.account, Current.user).vigentes.com_pendencia
    lista = lista.where(created_at: horas.hours.ago..) if horas.positive?
    render json: { pendencias: lista.order(created_at: :desc).limit(LIMITE).map(&:pendencia_para_tela) }
  end

  private

  def horas
    params[:horas].to_i
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
