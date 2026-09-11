# A MEDIDA DA COTAÇÃO NO SUPER ADMIN (entrega 7, termo 4): a consulta que alguém da operação roda
# sozinho, sem engenheiro, sem token e sem `curl` — abre a página, escolhe o mês, lê os números.
#
# É a nossa ponta da medida (cobrar); a ponta da corretora (mostrar retorno) é o endpoint da conta,
# `…/autonomia/insurance/measurement`. As duas leem a MESMA `Insurance::Medida` — dois números para o
# mesmo mês que não batessem entre a fatura e a tela do cliente seriam pior do que número nenhum.
#
# Ler não é frear: a página não liga, desliga nem limita nada.
class SuperAdmin::InsuranceMeasurementsController < SuperAdmin::ApplicationController
  def show
    @medida = ::Autonomia::Insurance::Medida.new(inicio: params[:from], fim: params[:to])
    @linhas = @medida.por_conta
    @contas = Account.where(id: @linhas.pluck(:conta_id)).index_by(&:id)
  rescue ::Autonomia::Insurance::Medida::PeriodoInvalido => e
    # Data ilegível não vira janela padrão em silêncio. O aviso diz o que estava errado e a página
    # não mostra número nenhum — número de um período que ninguém pediu é pior do que nenhum.
    @erro = e.message
    @linhas = []
    @contas = {}
  end
end
