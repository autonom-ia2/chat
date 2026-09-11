# A MEDIDA DA COTAÇÃO pela porta da conta (entrega 7).
#
# Herda o gate do módulo: feature ligada + conta marcada + ADMINISTRADOR. É o número que a corretora
# usa para ver o retorno do que paga, e o mesmo que nós usamos para cobrar — não é dado de
# atendente. O escopo é sempre `Current.account`: a medida de outra corretora não existe por aqui.
#
# Ler NÃO É FREAR. Este é um endpoint de leitura; nenhum caminho de cotação passa por ele, e quem
# decide volume é a corretora que paga.
class Api::V1::Accounts::Autonomia::Insurance::MeasurementController <
  Api::V1::Accounts::Autonomia::Insurance::BaseController
  # GET ?from=2026-09-01&to=2026-09-30 — sem janela, os últimos 30 dias.
  def show
    @medida = ::Autonomia::Insurance::Medida.new(conta: Current.account, inicio: params[:from], fim: params[:to]).call
    render :show
  rescue ::Autonomia::Insurance::Medida::PeriodoInvalido => e
    # Data ilegível não vira janela padrão em silêncio: um número de cobrança de um período que
    # ninguém pediu é pior do que erro nenhum. A frase é NOSSA e não carrega nada de quem perguntou.
    render json: { error: 'periodo_invalido', detail: e.message }, status: :unprocessable_entity
  end
end
